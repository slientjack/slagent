"""
工具基类与公共安全辅助函数。

设计意图：
- _safe_path：所有文件工具的路径安全闸门。把 LLM 提供的相对路径解析为
  工作区内的绝对路径，resolve 后校验「必须以工作区根目录为前缀」。
  默认情况下越界即拒绝；若构建工具时注入了权限管理器，则改为向用户
  发起实时授权请求 —— 用户同意后本次操作才放行，拒绝则抛出 PermissionError。
- truncate_output：统一的输出截断函数。工具输出（文件内容、命令 stdout、
  HTTP body）直接回填进 LLM 上下文，超长输出会撑爆 token 预算甚至超出
  模型上下文窗口，因此统一截断到约 10KB 并附提示，让 LLM 知道内容不完整。
"""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    # 仅用于类型标注，避免 tools.permission 与本模块产生运行期循环依赖
    from tools.permission import PermissionManager

# 输出截断上限（约 10KB 字符）。取整为 10240 便于记忆：10 * 1024
MAX_OUTPUT_CHARS = 10 * 1024


def _safe_path(
    workspace_root: Path | str,
    rel_path: str,
    *,
    workspace_id: str | None = None,
    permission_manager: "PermissionManager | None" = None,
    operation: str = "访问",
) -> Path:
    """把 LLM 提供的路径解析为绝对路径，并校验/申请越界访问权限。

    解析规则：
    1. rel_path 为绝对路径时，`root / rel_path` 会直接得到该绝对路径
       （Path 的拼接语义），因此绝对路径同样会走越界校验；
    2. resolve() 会展开符号链接、消除 ../、./ 等冗余片段；
    3. 校验 resolve 后的路径必须位于工作区根目录内：
       - 在目录内：直接返回；
       - 越界且未注入权限管理器：抛出 PermissionError（默认安全行为）；
       - 越界且已注入权限管理器：向用户发起授权请求，同意后返回。

    Args:
        workspace_root: 工作区根目录（Path 或 str）。
        rel_path: LLM 提供的路径（如 "src/main.py"、"../etc/passwd"）。
        workspace_id: 工作区 id（权限请求按工作区隔离会话授权）。
        permission_manager: 权限管理器；为 None 时越界即拒绝。
        operation: 操作名称（"读取"/"创建"/"修改"/"删除"/"重命名"/"列出"），
                   用于生成给用户看的授权说明。

    Returns:
        解析后的绝对路径（Path 对象）。

    Raises:
        PermissionError: 路径越界且用户拒绝授权（或没有授权通道）时抛出。
    """
    root = Path(workspace_root).resolve()
    candidate = (root / rel_path).resolve()
    # 关键安全校验：resolve 后必须仍位于根目录之内（含根目录本身）
    if candidate == root or root in candidate.parents:
        return candidate

    # ---- 越界：尝试申请用户授权 ----
    if permission_manager is None or workspace_id is None:
        raise PermissionError(f"路径越界：{rel_path} 不在工作区目录内，已拒绝访问")

    allowed = permission_manager.request(
        workspace_id=workspace_id,
        ptype="file_access",
        target=str(candidate),
        detail=f"Agent 请求{operation}工作区之外的路径：{candidate}",
        risk="normal",
    )
    if not allowed:
        raise PermissionError(f"用户拒绝了{operation}工作区之外的路径：{candidate}")
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
