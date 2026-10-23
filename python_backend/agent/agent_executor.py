"""
Agent 执行器。

设计意图：
- 封装 LangChain `create_agent` 的完整调用链路，向 API 层暴露一个简单接口：
  run(history_messages, user_message, workspace_root, settings) -> (reply, tool_calls)
- 内部职责：
  1. 通过 ModelFactory 取模型 Provider 并构造 LLM；
  2. 通过 ToolRegistry 构建当前工作区的全部工具；
  3. 用中文系统提示词（注入工作区路径）创建 Agent；
  4. 对话历史按 token 估算裁剪（防超模型上下文窗口）；
  5. invoke 后从结果消息里提取最终回复与工具调用记录；
  6. 把 LLM 厂商异常翻译成带中文说明的 RuntimeError（API 层转 502）。
- 学习要点：LangChain 1.x 的 create_agent 是"预装配"的 Agent 运行时，
  invoke 返回 dict，result["messages"] 是完整消息轨迹
  （HumanMessage / AIMessage / ToolMessage 交替），工具调用信息藏在
  AIMessage.tool_calls（调用请求）与 ToolMessage.content（执行结果）里。
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from langchain.agents import create_agent
from langchain_core.messages import AIMessage, ToolMessage

from agent.prompt_templates import SYSTEM_PROMPT_TEMPLATE
from config import ConfigManager
from models.model_factory import ModelFactory
from tools.base_tool import truncate_output
from tools.permission import PermissionManager
from tools.tool_registry import ToolRegistry

logger = logging.getLogger(__name__)

# 裁剪历史时至少保留的最近消息条数（保证模型至少能看到当前轮上下文）
MIN_KEEP_MESSAGES = 2


def estimate_tokens(text: str) -> int:
    """粗略估算文本的 token 数。

    估算规则（够用即可，无需精确 tokenizer）：
    - CJK 字符（中日韩统一表意文字等）平均 1 字 ≈ 1 token；
    - 其他字符（英文/数字/符号）平均 4 字符 ≈ 1 token（0.25/字符）。

    Args:
        text: 待估算文本。

    Returns:
        估算 token 数（int）。
    """
    if not text:
        return 0
    cjk = 0
    for ch in text:
        # CJK 统一表意文字 + 扩展A + 常用全角标点/假名/谚文区间
        if (
            "\u4e00" <= ch <= "\u9fff"
            or "\u3400" <= ch <= "\u4dbf"
            or "\u3000" <= ch <= "\u30ff"
            or "\uac00" <= ch <= "\ud7af"
        ):
            cjk += 1
    other = len(text) - cjk
    return int(cjk + other * 0.25)


def _estimate_messages_tokens(messages: list[dict[str, Any]]) -> int:
    """估算一组消息记录的总 token 数（只统计 content 正文）。"""
    return sum(estimate_tokens(m.get("content") or "") for m in messages)


def trim_history(messages: list[dict[str, Any]], max_context_length: int) -> list[dict[str, Any]]:
    """按最大上下文长度裁剪历史：从最早的消息开始丢弃。

    规则：
    - 只要总 token 估算超过 max_context_length 且消息数 > MIN_KEEP_MESSAGES，
      就从头部（最早）删除一条；
    - 无论预算多小，都至少保留最近 MIN_KEEP_MESSAGES 条消息，
      保证模型能看到当前对话的即时上下文。

    Args:
        messages: 历史消息记录列表（原地修改）。
        max_context_length: 最大上下文 token 数。

    Returns:
        裁剪后的消息列表（同一对象，便于链式使用）。
    """
    while (
        len(messages) > MIN_KEEP_MESSAGES
        and _estimate_messages_tokens(messages) > max_context_length
    ):
        removed = messages.pop(0)
        logger.debug("历史裁剪：移除早期消息（%s）", removed.get("role"))
    return messages


class AgentExecutor:
    """Agent 执行器：一次 run() 调用完成一轮对话（可能含多次工具调用）。"""

    def __init__(
        self,
        config_manager: ConfigManager,
        permission_manager: PermissionManager | None = None,
    ) -> None:
        """注入配置管理器与权限管理器。

        Args:
            config_manager: 应用配置管理器实例（读取 API Key、白名单等）。
            permission_manager: 权限管理器。注入后文件越界访问与白名单外命令
                会向前端发起实时授权请求；为 None 时保持严格限制。
        """
        self.config_manager = config_manager
        self.permission_manager = permission_manager

    def run(
        self,
        history_messages: list[dict[str, Any]],
        user_message: str,
        workspace_root: Path | str,
        settings: dict[str, Any],
        workspace_id: str | None = None,
    ) -> tuple[str, list[dict[str, Any]]]:
        """执行一轮 Agent 对话。

        Args:
            history_messages: 已持久化的历史消息记录
                （[{"role","content",...}, ...]，assistant 的 tool_calls 不重发给模型）。
            user_message: 本轮用户输入。
            workspace_root: 当前工作区根目录（工具作用域 + 提示词注入）。
            settings: 已合并请求级覆盖后的生效设置
                （model / temperature / max_context_length）。
            workspace_id: 当前工作区 id（权限请求按工作区隔离会话授权）。

        Returns:
            二元组 (reply_text, tool_call_records)：
            - reply_text: 最后一条 AIMessage 的文本内容；
            - tool_call_records: [{"tool","args","result"}, ...]。

        Raises:
            RuntimeError: LLM 初始化或调用失败（含中文说明，API 层转 502）。
        """
        # ---- 1. 历史裁剪：按最大上下文长度从最早轮次开始丢弃 ----
        max_context = int(settings.get("max_context_length", 4096))
        trimmed = trim_history(list(history_messages), max_context)

        # ---- 2. 构造模型与工具 ----
        model_id = settings.get("model", "deepseek")
        provider = ModelFactory.get_provider(model_id)
        api_key = self.config_manager.get_decrypted_api_key()
        if not api_key:
            # 防御性兜底：正常情况下 API 层已提前校验并返回 400
            raise RuntimeError("请先在设置中配置 Deepseek API Key")
        llm = provider.get_llm(api_key, settings)

        tools = ToolRegistry.build_all_tools(
            workspace_root,
            self.config_manager,
            workspace_id=workspace_id,
            permission_manager=self.permission_manager,
        )

        # ---- 3. 系统提示词：注入当前工作区绝对路径 ----
        system_prompt = SYSTEM_PROMPT_TEMPLATE.format(workspace_path=str(workspace_root))

        # ---- 4. 创建 Agent（LangChain 1.x 预装配运行时）----
        agent = create_agent(llm, tools=tools, system_prompt=system_prompt)

        # ---- 5. 组装输入消息：裁剪后的历史 + 本轮用户消息 ----
        input_messages: list[dict[str, str]] = []
        for msg in trimmed:
            role = msg.get("role")
            content = msg.get("content") or ""
            # 历史里只回放纯文本对话；工具调用过程不重放（避免 token 浪费与格式干扰）
            if role in ("user", "assistant") and content:
                input_messages.append({"role": role, "content": content})
        input_messages.append({"role": "user", "content": user_message})

        # ---- 6. 调用 Agent ----
        logger.info("Agent 开始执行（模型=%s，历史 %d 条，工具 %d 个）",
                    model_id, len(input_messages) - 1, len(tools))
        try:
            result = agent.invoke({"messages": input_messages})
        except RuntimeError:
            # provider 内部已翻译过的中文错误，直接上抛
            raise
        except Exception as exc:  # noqa: BLE001 —— 厂商 SDK 异常类型不可枚举
            # 翻译成中文说明：key 无效（401）、网络错误、超时等都在此统一处理
            label = getattr(provider, "error_label", "LLM API")
            logger.error("Agent 调用失败：%s", exc)
            raise RuntimeError(f"{label} 调用失败：{exc}") from exc

        # ---- 7. 从消息轨迹提取回复与工具调用记录 ----
        reply_text, tool_call_records = self._extract_from_result(result)

        logger.info("Agent 执行完成（回复 %d 字符，工具调用 %d 次）",
                    len(reply_text), len(tool_call_records))
        return reply_text, tool_call_records

    # ------------------------------------------------------------------

    @staticmethod
    def _extract_from_result(result: dict[str, Any]) -> tuple[str, list[dict[str, Any]]]:
        """从 agent.invoke 的结果中提取最终回复与工具调用记录。

        消息轨迹结构（LangChain 消息对象列表）：
        - HumanMessage: 用户输入；
        - AIMessage: 模型输出；.tool_calls 是工具调用请求列表
          [{name, args, id}, ...]，.content 是文本内容；
        - ToolMessage: 工具执行结果；.tool_call_id 关联到某个调用请求，.content 是结果字符串。

        Args:
            result: agent.invoke 的返回 dict（含 "messages" 键）。

        Returns:
            (最后一条 AIMessage 的文本, 工具调用记录列表)。
        """
        messages = result.get("messages", [])

        # ---- 最终回复：最后一条 AIMessage 的 content ----
        reply_text = ""
        for msg in reversed(messages):
            if isinstance(msg, AIMessage):
                content = msg.content
                # content 可能是 str 或多模态分块列表，统一转字符串
                if isinstance(content, list):
                    content = "".join(
                        block.get("text", "") for block in content if isinstance(block, dict)
                    )
                reply_text = (content or "").strip()
                break
        if not reply_text:
            # 极端情况：模型只调了工具没说话（正常 create_agent 会补总结轮）
            reply_text = "（本轮操作已完成，未返回文本说明）"

        # ---- 工具调用记录：AIMessage.tool_calls 与 ToolMessage 按 id 配对 ----
        tool_call_records: list[dict[str, Any]] = []
        pending: dict[str, dict[str, Any]] = {}  # tool_call_id -> 记录（等待结果回填）
        for msg in messages:
            if isinstance(msg, AIMessage):
                for tc in (msg.tool_calls or []):
                    record = {
                        "tool": tc.get("name", "unknown"),
                        # args 已是 dict；防御性拷贝，避免可变共享
                        "args": dict(tc.get("args") or {}),
                        "result": "",
                    }
                    tool_call_records.append(record)
                    pending[tc.get("id", "")] = record
            elif isinstance(msg, ToolMessage):
                record = pending.get(msg.tool_call_id)
                if record is not None:
                    # 工具结果统一转字符串并截断，防止超长内容撑爆持久化文件
                    record["result"] = truncate_output(str(msg.content))

        return reply_text, tool_call_records
