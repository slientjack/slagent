"""
工具注册中心。

设计意图：
- ToolRegistry 是所有工具的统一登记入口：AgentExecutor 只调用
  build_all_tools(...) 一处，即可拿到当前工作区可用的全部工具。
- 未来新增工具（如代码搜索、数据库查询等）只需：
  1. 在 tools/ 下新建模块实现 build_xxx_tools()；
  2. 在本模块的 build_all_tools 中登记一行。
- 文件/终端工具与工作区绑定（每次对话按 workspace_root 重建），
  网络工具无状态可复用。
- 注入 workspace_id 与 PermissionManager 后，文件越界访问与白名单外命令
  会走用户实时授权流程；不注入时保持默认的严格限制。
"""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING, Callable

from config import ConfigManager
from tools.file_tools import build_file_tools
from tools.terminal_tool import build_terminal_tool
from tools.web_tool import build_web_tool

if TYPE_CHECKING:
    from tools.permission import PermissionManager


class ToolRegistry:
    """工具注册中心：汇总构建 Agent 可用的全部工具。"""

    @staticmethod
    def build_all_tools(
        workspace_root: Path | str,
        config_manager: ConfigManager,
        workspace_id: str | None = None,
        permission_manager: "PermissionManager | None" = None,
    ) -> list[Callable]:
        """构建指定工作区的全部工具。

        Args:
            workspace_root: 当前工作区根目录（文件/终端工具的作用域）。
            config_manager: 配置管理器（终端工具读取安全白名单用）。
            workspace_id: 工作区 id（权限请求按工作区隔离会话授权）。
            permission_manager: 权限管理器；注入后允许用户实时授权越界操作。

        Returns:
            LangChain 工具列表（文件工具 + 终端工具 + 网络工具）。
        """
        tools: list[Callable] = []
        # 文件操作工具：默认限定工作区，越界时申请用户授权
        tools.extend(
            build_file_tools(workspace_root, workspace_id, permission_manager)
        )
        # 终端命令工具：白名单来自 ConfigManager，白名单外命令申请用户授权
        tools.append(
            build_terminal_tool(
                workspace_root, config_manager, workspace_id, permission_manager
            )
        )
        # HTTP 网络工具：无工作区依赖
        tools.append(build_web_tool())
        return tools

