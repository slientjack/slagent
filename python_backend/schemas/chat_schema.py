"""
对话（chat）相关的 Pydantic 模型。

设计意图：
- 定义 /api/chat/* 三个端点的请求与响应结构，以及对话历史的持久化消息格式。
- MessageRecord 同时承担两个角色：API 响应中的历史消息、
  conversations/{workspace_id}.json 中的落盘消息，保证前后端与磁盘格式一致。
- ToolCallRecord 记录 Agent 的每一次工具调用（工具名 / 参数 / 结果），
  前端据此渲染"Agent 执行了什么操作"。
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class ToolCallRecord(BaseModel):
    """一次工具调用的记录。"""

    # 工具名（如 "read_file"、"execute_command"）
    tool: str
    # 调用参数（JSON 可序列化的 dict，如 {"path": "src/main.py"}）
    args: dict[str, Any] = Field(default_factory=dict)
    # 工具返回的字符串结果（可能被截断）
    result: str = ""


class MessageRecord(BaseModel):
    """一条对话消息（同时用于 API 响应与磁盘持久化）。"""

    # 消息唯一标识（uuid4）
    id: str
    # 角色：用户 或 助手
    role: Literal["user", "assistant"]
    # 消息正文
    content: str
    # 创建时间（ISO8601 UTC）
    timestamp: str
    # 该消息产生的工具调用记录（仅 assistant 消息会有）
    tool_calls: list[ToolCallRecord] = Field(default_factory=list)


class ChatSendSettingsOverride(BaseModel):
    """单次发送请求的临时设置覆盖（不持久化到 settings.json）。"""

    temperature: float | None = None
    max_context_length: int | None = None


class ChatSendRequest(BaseModel):
    """POST /api/chat/send 请求体。"""

    # 用户输入的消息文本（非空校验在路由层做，以便返回 400 中文错误）
    message: str
    # 目标工作区 id
    workspace_id: str
    # 可选：本次请求的临时设置覆盖
    settings: ChatSendSettingsOverride | None = None


class ChatSendResponse(BaseModel):
    """POST /api/chat/send 响应。"""

    # Agent 的最终文本回复
    response: str
    # 本轮产生的工具调用记录
    tool_calls: list[ToolCallRecord] = Field(default_factory=list)


class ChatClearRequest(BaseModel):
    """POST /api/chat/clear 请求体。"""

    workspace_id: str


class ChatHistoryResponse(BaseModel):
    """GET /api/chat/history 响应。"""

    messages: list[MessageRecord] = Field(default_factory=list)


class ChatStatusResponse(BaseModel):
    """操作成功状态响应（clear 等）。"""

    status: str = "ok"
