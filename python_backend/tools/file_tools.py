"""
文件操作工具集。

设计意图：
- build_file_tools(workspace_root) 为指定工作区构建一套文件工具
  （读 / 建 / 改 / 删 / 重命名 / 列目录），所有路径参数均经过
  base_tool._safe_path 安全校验。
- 默认只允许操作工作区内文件；若注入 workspace_id 与权限管理器，
  访问工作区外路径会触发前端授权弹窗，用户允许后才放行。
- 每个工具用 LangChain 的 @tool 装饰器封装，docstring 用中文详细说明
  参数含义与返回值 —— 这些文本会作为工具描述发送给 LLM，
  直接决定 Agent 能否正确调用工具。
- 工具返回值统一为字符串：成功 "✅ ..."、失败 "❌ 错误：..."。
- 注意闭包用法：workspace_root 被 build_file_tools 的内层函数捕获，
  因此同一进程可以为多个工作区各构建一套互不干扰的工具实例。
"""

from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING, Callable

from langchain_core.tools import tool

from tools.base_tool import _safe_path, truncate_output

if TYPE_CHECKING:
    from tools.permission import PermissionManager

# 单文件读取上限：100KB（超过则截断并提示，防止超大文件撑爆上下文）
MAX_FILE_READ_CHARS = 100 * 1024


def build_file_tools(
    workspace_root: Path | str,
    workspace_id: str | None = None,
    permission_manager: "PermissionManager | None" = None,
) -> list[Callable]:
    """为工作区构建一组文件操作 LangChain 工具。

    Args:
        workspace_root: 工作区根目录，默认所有文件操作被限制在该目录内。
        workspace_id: 工作区 id（权限请求按工作区隔离会话授权）。
        permission_manager: 权限管理器；注入后允许用户实时授权访问工作区外路径。

    Returns:
        LangChain 工具列表（read_file / create_file / edit_file /
        delete_file / rename_file / list_files）。
    """
    root = Path(workspace_root)

    def resolve(path: str, operation: str) -> Path:
        """统一调用 _safe_path，把授权参数与操作名一并传入。"""
        return _safe_path(
            root,
            path,
            workspace_id=workspace_id,
            permission_manager=permission_manager,
            operation=operation,
        )

    @tool
    def read_file(path: str) -> str:
        """读取指定文本文件的内容（可读取工作区外文件，需用户授权）。

        参数：
            path: 文件路径，可以是相对工作区根目录的路径（如 "src/main.py"），
                  也可以是绝对路径（如 "/Users/me/notes.txt"）。
                  工作区之外的路径会触发用户授权确认。

        返回：
            文件全文内容（超大文件超过 100KB 时截断并附提示）；
            二进制文件（含 \\0 字节）无法读取，会返回错误说明。
        """
        try:
            target = resolve(path, "读取")
        except PermissionError as exc:
            return f"❌ 错误：{exc}"

        if not target.exists():
            return f"❌ 错误：文件不存在：{path}"
        if target.is_dir():
            return f"❌ 错误：{path} 是目录而不是文件，请用 list_files 查看目录内容"

        try:
            raw = target.read_bytes()
        except OSError as exc:
            return f"❌ 错误：读取文件失败：{exc}"

        # 二进制文件检测：内容含 \0 字节即视为二进制（文本文件几乎不会包含 \0）
        if b"\x00" in raw:
            return f"❌ 错误：{path} 是二进制文件，无法以文本方式读取"

        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            # 非 UTF-8 编码也按二进制/不支持的编码处理
            return f"❌ 错误：{path} 不是 UTF-8 文本文件，无法读取"

        # 超过 100KB 的文件截断（先按文件专属上限截断，再走通用 10KB 上限由调用方决定）
        if len(content) > MAX_FILE_READ_CHARS:
            content = (
                content[:MAX_FILE_READ_CHARS]
                + f"\n\n⚠️ 文件过大（{len(content)} 字符），已截断，仅显示前 100KB 内容。"
            )
        return truncate_output(content)

    @tool
    def create_file(path: str, content: str) -> str:
        """创建新文件并写入内容（可在工作区外创建，需用户授权）。若文件已存在则会报错（不会覆盖）。

        参数：
            path: 新文件路径（相对工作区根目录或绝对路径），例如 "notes/todo.txt"。
                  父目录不存在时会自动创建；工作区之外的路径会触发用户授权确认。
            content: 要写入的完整文件内容（UTF-8 文本）。

        返回：
            成功时返回确认信息与文件路径；文件已存在时返回错误说明。
        """
        try:
            target = resolve(path, "创建")
        except PermissionError as exc:
            return f"❌ 错误：{exc}"

        if target.exists():
            return f"❌ 错误：文件已存在：{path}。如需修改请用 edit_file，如需覆盖请先 delete_file"

        try:
            # parents=True：自动创建缺失的父目录
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8")
            return f"✅ 文件创建成功：{path}（写入 {len(content)} 字符）"
        except OSError as exc:
            return f"❌ 错误：创建文件失败：{exc}"

    @tool
    def edit_file(path: str, old_text: str, new_text: str) -> str:
        """修改已有文件：把文件中第一次出现的 old_text 替换为 new_text（可修改工作区外文件，需用户授权）。

        参数：
            path: 文件路径（相对工作区根目录或绝对路径）。
            old_text: 要被替换的原文（必须与文件内容完全一致，包括缩进与空行；
                      未在文件中找到时会报错，请先 read_file 确认原文）。
            new_text: 替换后的新文本（替换 old_text 第一次出现的位置）。

        返回：
            成功时返回确认信息；old_text 未找到或文件不存在时返回错误说明。
        """
        try:
            target = resolve(path, "修改")
        except PermissionError as exc:
            return f"❌ 错误：{exc}"

        if not target.is_file():
            return f"❌ 错误：文件不存在：{path}"

        try:
            content = target.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            return f"❌ 错误：读取文件失败：{exc}"

        if old_text not in content:
            # 给 LLM 明确指引：先读文件再编辑，避免反复盲试
            return f"❌ 错误：在 {path} 中未找到要替换的文本。请先 read_file 确认原文内容"

        try:
            # 只替换第一次出现（count=1），避免意外改动多处
            new_content = content.replace(old_text, new_text, 1)
            target.write_text(new_content, encoding="utf-8")
            return f"✅ 文件修改成功：{path}"
        except OSError as exc:
            return f"❌ 错误：写入文件失败：{exc}"

    @tool
    def delete_file(path: str) -> str:
        """删除文件或空目录（可删除工作区外文件，需用户授权）。注意：目录非空时删除会失败。

        参数：
            path: 要删除的文件路径（相对工作区根目录或绝对路径）。

        返回：
            成功时返回确认信息；文件不存在或删除失败时返回错误说明。
        """
        try:
            target = resolve(path, "删除")
        except PermissionError as exc:
            return f"❌ 错误：{exc}"

        if not target.exists():
            return f"❌ 错误：文件不存在：{path}"
        # 防御：不允许删除工作区根目录本身
        if target == root.resolve():
            return "❌ 错误：不能删除工作区根目录"

        try:
            if target.is_dir():
                # rmdir 只能删空目录，避免误删整棵目录树
                target.rmdir()
                return f"✅ 空目录已删除：{path}"
            target.unlink()
            return f"✅ 文件已删除：{path}"
        except OSError as exc:
            # 常见失败：目录非空、权限不足
            return f"❌ 错误：删除失败：{exc}"

    @tool
    def rename_file(old_path: str, new_path: str) -> str:
        """重命名（或移动）文件/目录（可跨出工作区，需用户授权）。

        参数：
            old_path: 原路径（相对工作区根目录或绝对路径）。
            new_path: 新路径（父目录不存在时自动创建；目标已存在时会报错）。
                      跨出工作区时会触发用户授权确认。

        返回：
            成功时返回确认信息；原路径不存在或目标已存在时返回错误说明。
        """
        try:
            src = resolve(old_path, "重命名")
            dst = resolve(new_path, "重命名")
        except PermissionError as exc:
            return f"❌ 错误：{exc}"

        if not src.exists():
            return f"❌ 错误：原路径不存在：{old_path}"
        if dst.exists():
            return f"❌ 错误：目标路径已存在：{new_path}"
        # 禁止把工作区根目录挪走
        if src == root.resolve():
            return "❌ 错误：不能重命名工作区根目录"

        try:
            dst.parent.mkdir(parents=True, exist_ok=True)
            src.rename(dst)
            return f"✅ 重命名成功：{old_path} → {new_path}"
        except OSError as exc:
            return f"❌ 错误：重命名失败：{exc}"

    @tool
    def list_files(path: str = ".") -> str:
        """列出指定目录下一层的文件与子目录（不递归进入子目录；可列工作区外目录，需用户授权）。

        参数：
            path: 目录路径（相对工作区根目录或绝对路径），默认 "." 表示工作区根目录。

        返回：
            每行一项，格式为 "[目录] 名称/" 或 "[文件] 名称"；目录不存在时返回错误。
        """
        try:
            target = resolve(path, "列出")
        except PermissionError as exc:
            return f"❌ 错误：{exc}"

        if not target.is_dir():
            return f"❌ 错误：目录不存在或不是目录：{path}"

        try:
            entries = sorted(target.iterdir())  # 排序保证输出稳定
        except OSError as exc:
            return f"❌ 错误：读取目录失败：{exc}"

        if not entries:
            return f"目录 {path} 为空"

        lines = []
        for entry in entries:
            if entry.is_dir():
                lines.append(f"[目录] {entry.name}/")
            else:
                lines.append(f"[文件] {entry.name}")
        return truncate_output("\n".join(lines))

    # 返回工具列表；@tool 装饰后的对象本身即可调用
    return [read_file, create_file, edit_file, delete_file, rename_file, list_files]
