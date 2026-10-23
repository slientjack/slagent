"""
对话路由（/api/chat/*）。

设计意图：
- 三个端点：history（查历史）、clear（清空）、send（发送消息并执行 Agent）。
- 对话历史按工作区持久化在 conversations/{workspace_id}.json，
  格式：{"workspace_id","messages","updatedAt"}；本模块封装其读写。
- send 是同步阻塞端点（LLM 完成后一次性返回）。端点用普通 def 定义，
  FastAPI 会自动把 def 端点放进线程池执行，agent.invoke（同步调用）
  不会阻塞事件循环，服务期间 /health 等端点仍可响应。
- 错误约定（中文 detail）：
  - workspace 不存在 → 404；
  - 未配置 API Key → 400；
  - LLM 调用失败（key 无效/网络/超时）→ 502。
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException

from agent.agent_executor import AgentExecutor
from config import ConfigManager
from schemas.chat_schema import (
    ChatClearRequest,
    ChatHistoryResponse,
    ChatSendRequest,
    ChatSendResponse,
    ChatStatusResponse,
    MessageRecord,
    ToolCallRecord,
)
from tools.permission import PermissionManager

logger = logging.getLogger(__name__)


def _now_iso() -> str:
    """当前时间的 ISO8601 UTC 字符串。"""
    return datetime.now(timezone.utc).isoformat()


def build_router(
    config_manager: ConfigManager,
    agent_executor: AgentExecutor,
    permission_manager: PermissionManager | None = None,
) -> APIRouter:
    """构建对话路由。

    Args:
        config_manager: 配置管理器（定位数据目录、读取设置与 API Key）。
        agent_executor: Agent 执行器（真正调用 LLM 与工具）。
        permission_manager: 权限管理器（清空对话时同步清空会话级授权）。

    Returns:
        挂载了 chat 三端点的 APIRouter。
    """
    router = APIRouter(prefix="/api/chat", tags=["chat"])
    conversations_dir = config_manager.conversations_dir

    # ------------------------------------------------------------------
    # workspaces.json 辅助：确认工作区存在
    # ------------------------------------------------------------------

    def _load_workspaces() -> list[dict]:
        """加载工作区列表（与 workspace_routes 相同的文件格式）。"""
        file = config_manager.workspaces_file
        if not file.exists():
            return []
        try:
            data = json.loads(file.read_text(encoding="utf-8"))
            raw = data.get("workspaces", []) if isinstance(data, dict) else data
            return raw if isinstance(raw, list) else []
        except (json.JSONDecodeError, OSError):
            return []

    def _get_workspace_or_404(workspace_id: str) -> dict:
        """按 id 取工作区记录；不存在时抛 404（中文信息）。"""
        workspace = next(
            (w for w in _load_workspaces() if w.get("id") == workspace_id), None
        )
        if workspace is None:
            raise HTTPException(status_code=404, detail=f"工作区不存在：{workspace_id}")
        return workspace

    # ------------------------------------------------------------------
    # 对话文件读写封装
    # ------------------------------------------------------------------

    def _conversation_file(workspace_id: str) -> Path:
        """工作区对应的对话历史文件路径。"""
        return conversations_dir / f"{workspace_id}.json"

    def _load_conversation(workspace_id: str) -> dict[str, Any]:
        """加载对话历史；无文件时返回空结构（不报错，视为新对话）。"""
        file = _conversation_file(workspace_id)
        if not file.exists():
            return {"workspace_id": workspace_id, "messages": [], "updatedAt": _now_iso()}
        try:
            data = json.loads(file.read_text(encoding="utf-8"))
            if isinstance(data, dict) and isinstance(data.get("messages"), list):
                return data
        except (json.JSONDecodeError, OSError) as exc:
            logger.warning("对话历史文件损坏（%s），按空历史处理：%s", workspace_id, exc)
        return {"workspace_id": workspace_id, "messages": [], "updatedAt": _now_iso()}

    def _save_conversation(workspace_id: str, messages: list[dict[str, Any]]) -> None:
        """把对话历史落盘（原子性由 write_text 的单次写入近似保证）。"""
        file = _conversation_file(workspace_id)
        file.write_text(
            json.dumps(
                {"workspace_id": workspace_id, "messages": messages, "updatedAt": _now_iso()},
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )

    # ------------------------------------------------------------------
    # 端点
    # ------------------------------------------------------------------

    @router.get("/history", response_model=ChatHistoryResponse)
    def get_history(workspace_id: str) -> ChatHistoryResponse:
        """获取指定工作区的对话历史（无历史返回空数组）。"""
        _get_workspace_or_404(workspace_id)
        conversation = _load_conversation(workspace_id)
        # 经 Pydantic 模型过滤，保证输出字段与契约一致
        messages = [MessageRecord(**m) for m in conversation.get("messages", [])]
        return ChatHistoryResponse(messages=messages)

    @router.post("/clear", response_model=ChatStatusResponse)
    def clear_history(request: ChatClearRequest) -> ChatStatusResponse:
        """清空指定工作区的对话历史（删除历史文件）。"""
        _get_workspace_or_404(request.workspace_id)
        file = _conversation_file(request.workspace_id)
        if file.exists():
            try:
                file.unlink()
                logger.info("对话历史已清空：%s", request.workspace_id)
            except OSError as exc:
                raise HTTPException(status_code=500, detail=f"清空对话历史失败：{exc}")
        # 清空对话同时作废"本轮对话允许"的授权，避免旧授权残留
        if permission_manager is not None:
            permission_manager.clear_session(request.workspace_id)
        return ChatStatusResponse()

    @router.post("/send", response_model=ChatSendResponse)
    def send_message(request: ChatSendRequest) -> ChatSendResponse:
        """发送用户消息，执行 Agent（含工具调用）并返回最终回复。

        流程：校验工作区(404) → 校验 API Key(400) → 加载历史 →
        追加用户消息 → Agent 执行（内部按上下文长度裁剪历史）→
        提取回复与工具调用 → 追加 assistant 消息并持久化 → 返回响应。

        LLM 调用失败（key 无效、网络错误、超时）抛 502 + 中文说明。
        """
        # ---- 1. 校验工作区存在 ----
        workspace = _get_workspace_or_404(request.workspace_id)

        # ---- 2. 校验 API Key 已配置 ----
        if not config_manager.get_decrypted_api_key():
            raise HTTPException(status_code=400, detail="请先在设置中配置 Deepseek API Key")

        # ---- 3. 校验消息非空 ----
        message = (request.message or "").strip()
        if not message:
            raise HTTPException(status_code=400, detail="消息内容不能为空")

        # ---- 4. 加载历史并追加用户消息（内存中）----
        conversation = _load_conversation(request.workspace_id)
        messages: list[dict[str, Any]] = list(conversation.get("messages", []))
        user_record = {
            "id": str(uuid.uuid4()),
            "role": "user",
            "content": message,
            "timestamp": _now_iso(),
            "tool_calls": [],
        }
        messages.append(user_record)

        # ---- 5. 合并请求级设置覆盖（不持久化）----
        effective_settings = dict(config_manager.load_settings())
        if request.settings is not None:
            if request.settings.temperature is not None:
                effective_settings["temperature"] = request.settings.temperature
            if request.settings.max_context_length is not None:
                effective_settings["max_context_length"] = request.settings.max_context_length

        # ---- 6. 执行 Agent（历史裁剪在 AgentExecutor 内完成）----
        try:
            reply_text, tool_call_records = agent_executor.run(
                history_messages=messages[:-1],  # 历史不含本轮用户消息（作为独立参数传入）
                user_message=message,
                workspace_root=workspace.get("path", ""),
                settings=effective_settings,
                workspace_id=request.workspace_id,
            )
        except RuntimeError as exc:
            # AgentExecutor 已翻译成中文错误（如 "Deepseek API 调用失败：..."）
            logger.error("Agent 执行失败：%s", exc)
            raise HTTPException(status_code=502, detail=str(exc)) from exc
        except Exception as exc:  # noqa: BLE001 —— 兜底，防止堆栈泄露给前端
            logger.exception("Agent 执行发生未预期异常")
            raise HTTPException(status_code=502, detail=f"Agent 执行失败：{exc}") from exc

        # ---- 7. 追加 assistant 消息并持久化 ----
        assistant_record = {
            "id": str(uuid.uuid4()),
            "role": "assistant",
            "content": reply_text,
            "timestamp": _now_iso(),
            "tool_calls": tool_call_records,
        }
        messages.append(assistant_record)
        try:
            _save_conversation(request.workspace_id, messages)
        except OSError as exc:
            # 历史落盘失败不影响本轮回复（用户仍能拿到答案），记录日志即可
            logger.error("对话历史持久化失败：%s", exc)

        # ---- 8. 组装响应 ----
        return ChatSendResponse(
            response=reply_text,
            tool_calls=[ToolCallRecord(**tc) for tc in tool_call_records],
        )

    return router
