"""
Deepseek 模型提供方。

设计意图：
- 封装 langchain_deepseek.ChatDeepSeek 的构造细节（API Key、模型名、温度），
  对上层暴露统一的 get_llm 接口。
- SDK 初始化异常在此翻译为带中文说明的 RuntimeError，
  让 /api/chat/send 能以 502 + 中文信息返回给用户。
"""

from __future__ import annotations

import logging
from typing import Any

from langchain_core.language_models.chat_models import BaseChatModel
from langchain_deepseek import ChatDeepSeek

from models.base_model import BaseModelProvider

logger = logging.getLogger(__name__)


class DeepseekProvider(BaseModelProvider):
    """Deepseek 聊天模型提供方（当前应用的默认模型）。"""

    model_id = "deepseek"
    model_name = "Deepseek (deepseek-chat)"
    description = "深度求索 Deepseek 聊天模型（deepseek-chat），性价比高，支持工具调用"
    # API 报错时拼入中文错误信息的标签（如 "Deepseek API 调用失败：..."）
    error_label = "Deepseek API"

    def get_llm(self, api_key: str, settings: dict[str, Any]) -> BaseChatModel:
        """构造 ChatDeepSeek 实例。

        Args:
            api_key: Deepseek API Key 明文。
            settings: 应用设置字典（取 temperature 控制随机性）。

        Returns:
            ChatDeepSeek 实例，可直接传给 langchain.agents.create_agent。

        Raises:
            RuntimeError: ChatDeepSeek 构造失败时抛出（含中文说明）。
        """
        # 从设置中读取温度；缺失时回退到 0.7（与默认设置一致）
        temperature = float(settings.get("temperature", 0.7))
        try:
            llm: BaseChatModel = ChatDeepSeek(
                api_key=api_key,
                model="deepseek-chat",  # Deepseek 通用对话模型，支持 function calling
                temperature=temperature,
            )
            logger.debug("ChatDeepSeek 实例构造完成（temperature=%.2f）", temperature)
            return llm
        except Exception as exc:  # noqa: BLE001 —— SDK 可能抛出各种配置异常
            # 统一翻译成中文错误，方便上层直接透传给用户
            raise RuntimeError(f"Deepseek 模型初始化失败：{exc}") from exc
