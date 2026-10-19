"""
Pydantic 数据模型（schemas）包。

设计意图：
- 用 Pydantic 模型描述全部 API 的请求/响应结构，
  FastAPI 借此自动完成：JSON 校验（非法请求直接 422）、
  OpenAPI 文档生成、响应字段过滤。
- 按领域拆分为三个模块：chat（对话）、workspace（工作区）、settings（设置）。
"""

from schemas.chat_schema import (
    ChatClearRequest,
    ChatSendRequest,
    ChatSendResponse,
    MessageRecord,
    ToolCallRecord,
)
from schemas.settings_schema import (
    AvailableModel,
    SettingsData,
    SettingsResponse,
    SettingsUpdateRequest,
)
from schemas.workspace_schema import (
    StatusResponse,
    WorkspaceCreateRequest,
    WorkspaceData,
    WorkspaceResponse,
    WorkspacesListResponse,
)

__all__ = [
    "ChatClearRequest",
    "ChatSendRequest",
    "ChatSendResponse",
    "MessageRecord",
    "ToolCallRecord",
    "AvailableModel",
    "SettingsData",
    "SettingsResponse",
    "SettingsUpdateRequest",
    "StatusResponse",
    "WorkspaceCreateRequest",
    "WorkspaceData",
    "WorkspaceResponse",
    "WorkspacesListResponse",
]
