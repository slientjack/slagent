"""
权限路由（/api/permissions/*）。

设计意图：
- 前端在发送消息期间持续轮询 /pending，发现待授权请求就弹窗；
  用户选择后调用 /respond，后端唤醒阻塞中的工具线程继续执行。
- 这是"同步聊天请求 + 中途需要用户输入"的经典解法：
  聊天请求保持阻塞，把权限交互拆成独立的轻量端点，无需引入 WebSocket/SSE。
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException

from schemas.permission_schema import (
    PendingPermissionsResponse,
    PermissionRequestInfo,
    PermissionRespondRequest,
    PermissionStatusResponse,
)
from tools.permission import PermissionManager

logger = logging.getLogger(__name__)


def build_router(permission_manager: PermissionManager) -> APIRouter:
    """构建权限路由。

    Args:
        permission_manager: 权限管理器（与工具层共享同一个实例）。

    Returns:
        挂载了 pending / respond 两个端点的 APIRouter。
    """
    router = APIRouter(prefix="/api/permissions", tags=["permissions"])

    @router.get("/pending", response_model=PendingPermissionsResponse)
    def get_pending(workspace_id: str | None = None) -> PendingPermissionsResponse:
        """获取等待用户决策的权限请求列表（可按工作区过滤）。"""
        items = permission_manager.get_pending(workspace_id)
        return PendingPermissionsResponse(
            requests=[PermissionRequestInfo(**item) for item in items]
        )

    @router.post("/respond", response_model=PermissionStatusResponse)
    def respond(request: PermissionRespondRequest) -> PermissionStatusResponse:
        """提交对某条权限请求的决策。

        请求不存在或已被处理时返回 404（例如超时后前端才提交）。
        """
        ok = permission_manager.respond(request.request_id, request.decision)
        if not ok:
            raise HTTPException(
                status_code=404,
                detail="权限请求不存在或已处理（可能已超时）",
            )
        return PermissionStatusResponse()

    return router
