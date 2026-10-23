"""
工作区管理路由（/api/workspaces）。

设计意图：
- 工作区 = 用户本机的一个目录登记（id、名称、路径），是文件工具与
  终端工具的作用域。列表持久化在数据目录的 workspaces.json。
- 删除工作区时联动删除其对话历史文件（conversations/{id}.json），
  避免留下孤儿数据。
- 路由通过 build_router(config_manager) 工厂创建，依赖显式注入。
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException

from config import ConfigManager
from schemas.workspace_schema import (
    StatusResponse,
    WorkspaceCreateRequest,
    WorkspaceData,
    WorkspaceResponse,
    WorkspacesListResponse,
)
from tools.permission import PermissionManager

logger = logging.getLogger(__name__)


def _now_iso() -> str:
    """当前时间的 ISO8601 UTC 字符串（带时区信息）。"""
    return datetime.now(timezone.utc).isoformat()


def build_router(
    config_manager: ConfigManager,
    permission_manager: PermissionManager | None = None,
) -> APIRouter:
    """构建工作区路由。

    Args:
        config_manager: 配置管理器（定位 workspaces.json 与 conversations 目录）。
        permission_manager: 权限管理器（删除工作区时清空其会话级授权）。

    Returns:
        挂载了 CRUD 端点的 APIRouter。
    """
    router = APIRouter(prefix="/api/workspaces", tags=["workspaces"])
    workspaces_file = config_manager.workspaces_file

    # ------------------------------------------------------------------
    # workspaces.json 读写辅助
    # ------------------------------------------------------------------

    def _load_workspaces() -> list[dict]:
        """从磁盘加载工作区列表；文件不存在或损坏时返回空列表。"""
        if not workspaces_file.exists():
            return []
        try:
            data = json.loads(workspaces_file.read_text(encoding="utf-8"))
            raw = data.get("workspaces", []) if isinstance(data, dict) else data
            return raw if isinstance(raw, list) else []
        except (json.JSONDecodeError, OSError) as exc:
            logger.warning("workspaces.json 读取失败：%s", exc)
            return []

    def _save_workspaces(workspaces: list[dict]) -> None:
        """把工作区列表写回磁盘。"""
        workspaces_file.write_text(
            json.dumps({"workspaces": workspaces}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def _find_workspace(workspace_id: str) -> dict | None:
        """按 id 查找工作区记录，找不到返回 None。"""
        return next((w for w in _load_workspaces() if w.get("id") == workspace_id), None)

    # ------------------------------------------------------------------
    # 端点
    # ------------------------------------------------------------------

    @router.get("", response_model=WorkspacesListResponse)
    def list_workspaces() -> WorkspacesListResponse:
        """获取全部工作区列表。"""
        items = [WorkspaceData(**w) for w in _load_workspaces()]
        return WorkspacesListResponse(workspaces=items)

    @router.post("", response_model=WorkspaceResponse)
    def create_workspace(request: WorkspaceCreateRequest) -> WorkspaceResponse:
        """登记新工作区（name 非空、path 必须是已存在的目录）。

        校验失败分别返回：
        - 400：name 为空 / path 不是目录；
        - 404：path 指向的目录不存在。
        """
        name = (request.name or "").strip()
        if not name:
            raise HTTPException(status_code=400, detail="工作区名称不能为空")

        path = (request.path or "").strip()
        if not path:
            raise HTTPException(status_code=400, detail="工作区路径不能为空")

        target = Path(path).expanduser()
        if not target.exists():
            raise HTTPException(status_code=404, detail=f"目录不存在：{path}")
        if not target.is_dir():
            raise HTTPException(status_code=400, detail=f"路径不是目录：{path}")

        workspace = {
            "id": str(uuid.uuid4()),
            "name": name,
            "path": str(target),
            "createdAt": _now_iso(),
        }
        workspaces = _load_workspaces()
        workspaces.append(workspace)
        _save_workspaces(workspaces)
        logger.info("工作区已创建：%s（%s）", name, target)
        return WorkspaceResponse(workspace=WorkspaceData(**workspace))

    @router.delete("/{workspace_id}", response_model=StatusResponse)
    def delete_workspace(workspace_id: str) -> StatusResponse:
        """删除工作区登记，并联动删除其对话历史文件。"""
        workspaces = _load_workspaces()
        workspace = _find_workspace(workspace_id)
        if workspace is None:
            raise HTTPException(status_code=404, detail=f"工作区不存在：{workspace_id}")

        # 从列表移除并保存
        workspaces = [w for w in workspaces if w.get("id") != workspace_id]
        _save_workspaces(workspaces)

        # 联动删除对话历史文件（存在才删）
        conversation_file = config_manager.conversations_dir / f"{workspace_id}.json"
        if conversation_file.exists():
            try:
                conversation_file.unlink()
            except OSError as exc:
                # 历史删除失败不影响工作区删除本身，记录日志即可
                logger.warning("删除对话历史文件失败：%s", exc)

        logger.info("工作区已删除：%s（%s）", workspace.get("name"), workspace_id)
        # 同步清空该工作区的会话级授权
        if permission_manager is not None:
            permission_manager.clear_session(workspace_id)
        return StatusResponse()

    return router
