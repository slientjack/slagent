"""
终端命令执行工具。

设计意图：
- 让 Agent 能在工作区内执行开发类命令（git、python3、npm...），
  同时通过双层安全机制防止危险命令执行：
  1. 白名单层：命令名（首个 token）必须在安全白名单内
     （默认白名单见 config.py，用户可用 safe_commands.json 覆盖）；
  2. 黑名单层：即使命令名合法，再叠加危险参数模式拦截
     （rm -rf、mkfs、dd if=、sudo、shutdown、reboot、fork 炸弹等，不区分大小写）。
- 使用 subprocess.run(shell=False) 执行：不经 shell 解析，杜绝命令注入
  （管道、反引号、&& 拼接等 shell 语法不会被解释）。
- 超时 30 秒；stdout 与 stderr 合并返回并标注来源，方便 LLM 区分正常输出与报错。
"""

from __future__ import annotations

import shlex
import subprocess
from pathlib import Path
from typing import Callable

from langchain_core.tools import tool

from config import ConfigManager
from tools.base_tool import truncate_output

# 命令执行超时（秒）
COMMAND_TIMEOUT_SECONDS = 30

# 危险参数模式黑名单：命令名合法但参数危险时在此拦截（小写匹配）。
# 说明：这些模式覆盖了常见的破坏性操作与提权操作。
DANGEROUS_PATTERNS = [
    "rm -rf",       # 递归强制删除（rm 在白名单外，双保险）
    "rm -fr",
    "mkfs",         # 格式化文件系统
    "dd if=",       # 磁盘级覆写（如 dd if=/dev/zero of=/dev/sda）
    "sudo",         # 提权执行
    "su ",          # 切换用户
    "shutdown",     # 关机
    "reboot",       # 重启
    "halt",         # 停机
    "poweroff",     # 关机
    ":(){:|:&};:",  # fork 炸弹经典形式
    ":(){ :|:& };:",  # fork 炸弹带空格变体
    "mkfifo",       # 可用于构造特殊攻击，一般开发场景不需要
    "> /dev/sd",    # 直接写块设备
    "chmod 777 /",  # 对根目录放开权限
    "chown -r /",   # 递归改根目录属主
]


def build_terminal_tool(workspace_root: Path | str, config_manager: ConfigManager) -> Callable:
    """为工作区构建终端命令执行工具。

    Args:
        workspace_root: 命令的工作目录（cwd），命令只能"看到"这个目录。
        config_manager: 配置管理器，用于读取安全命令白名单
                        （safe_commands.json 存在时覆盖默认白名单）。

    Returns:
        execute_command LangChain 工具。
    """
    root = Path(workspace_root)
    # 每次构建工具时读取一次白名单（配置管理器负责默认值/用户覆盖逻辑）
    safe_commands = set(config_manager.get_safe_commands())

    @tool
    def execute_command(command: str) -> str:
        """在工作区目录内执行一条终端命令（仅限安全白名单命令，超时 30 秒）。

        参数：
            command: 要执行的完整命令字符串，例如 "ls -la"、"git status"。
                     不支持管道、重定向等 shell 语法（出于安全考虑按空格拆分直接执行）。

        返回：
            命令的 stdout 与 stderr（分段标注来源）、退出码；
            命令不在白名单、命中危险参数或超时时返回错误说明。
        """
        # shlex.split 正确处理引号内的空格，如 grep "hello world" file.txt
        try:
            parts = shlex.split(command)
        except ValueError as exc:
            return f"❌ 错误：命令解析失败（引号不匹配？）：{exc}"

        if not parts:
            return "❌ 错误：命令为空"

        # ---- 第一层：白名单校验（首 token 即命令名，小写比较）----
        cmd_name = parts[0].lower()
        if cmd_name not in safe_commands:
            allowed = "、".join(sorted(safe_commands))
            return (
                f"❌ 错误：命令 “{parts[0]}” 不在安全白名单内，已拒绝执行。"
                f"允许的命令：{allowed}"
            )

        # ---- 第二层：危险参数模式拦截（整条命令小写后做子串匹配）----
        lowered = command.lower()
        for pattern in DANGEROUS_PATTERNS:
            if pattern in lowered:
                return f"❌ 错误：命令包含危险模式 “{pattern}”，已拒绝执行"

        # ---- 执行：shell=False，不经 shell 解析，天然免疫命令注入 ----
        try:
            proc = subprocess.run(
                parts,
                cwd=str(root),           # 工作目录锁定在工作区
                shell=False,              # 关键安全开关
                capture_output=True,      # 捕获 stdout + stderr
                text=True,                # 输出解码为 str
                timeout=COMMAND_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired:
            return f"❌ 错误：命令执行超时（>{COMMAND_TIMEOUT_SECONDS} 秒），已终止：{command}"
        except FileNotFoundError:
            return f"❌ 错误：找不到可执行程序：{parts[0]}"
        except OSError as exc:
            return f"❌ 错误：命令启动失败：{exc}"

        # ---- 组装输出：标注来源，便于 LLM 区分正常输出与报错 ----
        sections = []
        if proc.stdout:
            sections.append(f"--- stdout ---\n{proc.stdout}")
        if proc.stderr:
            sections.append(f"--- stderr ---\n{proc.stderr}")
        sections.append(f"--- 退出码：{proc.returncode} ---")
        return truncate_output("\n".join(sections))

    return execute_command
