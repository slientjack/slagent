"""
工具基类与公共安全辅助函数。

设计意图：
- _safe_path：所有文件工具的路径安全闸门。把 LLM 提供的相对路径解析为
  工作区内的绝对路径，resolve 后强制校验「必须以工作区根目录为前缀」，
  从根源上阻止 ../ 路径穿越攻击（即使 LLM 被提示注入诱导也越不出工作区）。
- truncate_output：统一的输出截断函数。工具输出（文件内容、命令 stdout、
  HTTP body）直接回填进 LLM 上下文，超长输出会撑爆 token 预算甚至超出
  模型上下文窗口，因此统一截断到约 10KB 并附提示，让 LLM 知道内容不完整。
"""

from __future__ import annotations

from pathlib import Path

# 输出截断上限（约 10KB 字符）。取整为 10240 便于记忆：10 * 1024
MAX_OUTPUT_CHARS = 10 * 1024


def _safe_path(workspace_root: Path | str, rel_path: str) -> Path:
    """把相对路径安全地解析为工作区内的绝对路径。

    解析规则：
    1. rel_path 若为绝对路径，也按「相对工作区根」理解（取其 basename 不安全，
       这里直接尝试在工作区下解析，绝对路径会被 resolve 夹到工作区内或报错）；
    2. resolve() 会展开符号链接、消除 ../、./ 等冗余片段；
    3. 校验 resolve 后的路径必须以工作区根（同样 resolve 过）为前缀，
       否则视为越界，抛出 PermissionError。

    Args:
        workspace_root: 工作区根目录（Path 或 str）。
        rel_path: LLM 提供的相对路径（如 "src/main.py"、"../etc/passwd"）。

    Returns:
        工作区内的绝对路径（Path 对象）。

    Raises:
        PermissionError: 路径越出工作区根目录时抛出（中文错误信息）。
    """
    root = Path(workspace_root).resolve()
    candidate = (root / rel_path).resolve()
    # 关键安全校验：resolve 后必须仍位于根目录之内（含根目录本身）
    if candidate != root and root not in candidate.parents:
        raise PermissionError(f"路径越界：{rel_path} 不在工作区目录内，已拒绝访问")
    return candidate


def truncate_output(text: str, max_chars: int = MAX_OUTPUT_CHARS) -> str:
    """把超长文本截断到约 max_chars 字符，并附中文提示。

    Args:
        text: 原始文本。
        max_chars: 截断上限，默认约 10KB。

    Returns:
        截断后的文本；未超长时原样返回。
    """
    if len(text) <= max_chars:
        return text
    # 末尾附提示，让 LLM 明确知道内容被截断、不是文件本来就这么短
    return (
        text[:max_chars]
        + f"\n\n⚠️ 输出过长，已截断（原始长度 {len(text)} 字符，仅保留前 {max_chars} 字符）。"
        + "如需查看其余内容，请分段读取。"
    )
