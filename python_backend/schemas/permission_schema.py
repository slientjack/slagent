"""
权限（permission）相关的 Pydantic 模型。

设计意图：
- 越界操作（工作区外文件 / 白名单外命令）需要用户实时授权，
  前端通过轮询 pending 接口获取待处理请求，再通过 respond 接口提交决策。
- 决策取值与前端对话框的四个按钮一一对应：
  allow_once / allow_session / allow_always / deny。
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

# 权限请求类型：文件访问 / 终端命令
PermissionType = Literal["file_access", "command"]
# 用户决策
PermissionDecision = Literal["allow_once", "allow_session", "allow_always", "deny"]


class PermissionRequestInfo(BaseModel):
    """一条等待用户决策的权限请求。"""

    id: str
    workspace_id: str
    type: PermissionType
    # 文件为绝对路径；命令为完整命令字符串
    target: str
    # 给用户看的说明（如"命令不在安全白名单内"）
    detail: str = ""
    # normal / high：高风险操作在前端用警示样式展示
    risk: Literal["normal", "high"] = "normal"
    created_at: str


class PendingPermissionsResponse(BaseModel):
    """GET /api/permissions/pending 响应。"""

    requests: list[PermissionRequestInfo] = Field(default_factory=list)


class PermissionRespondRequest(BaseModel):
    """POST /api/permissions/respond 请求体。"""

    request_id: str
    decision: PermissionDecision


class PermissionStatusResponse(BaseModel):
    """权限操作状态响应。"""

    status: str = "ok"
