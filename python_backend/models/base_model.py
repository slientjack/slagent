"""
LLM 模型提供方抽象基类。

设计意图：
- 定义所有模型提供方（Deepseek、OpenAI、Claude、Ollama...）必须实现的统一接口：
  get_llm(settings) —— 根据设置构造一个 LangChain 可用的聊天模型实例。
- 同时声明模型元信息（id / name / description），供 /api/settings 的
  available_models 列表展示给前端选择。
- 上层代码（AgentExecutor）只依赖本抽象，新增厂商时零改动（策略模式 + 工厂模式）。
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from langchain_core.language_models.chat_models import BaseChatModel


class BaseModelProvider(ABC):
    """模型提供方抽象基类。

    子类需要：
    1. 实现 get_llm()，返回配置好的 BaseChatModel 实例；
    2. 声明类属性 model_id / model_name / description，提供模型元信息。
    """

    # 模型唯一标识（注册进 ModelFactory 的 key，如 "deepseek"）
    model_id: str = ""
    # 展示名称（前端下拉框显示，如 "Deepseek (deepseek-chat)"）
    model_name: str = ""
    # 模型能力简述（前端可作提示文案）
    description: str = ""
    # API 报错时的错误前缀（如 "Deepseek API"），用于拼出用户可读的中文错误
    error_label: str = "LLM API"

    @abstractmethod
    def get_llm(self, api_key: str, settings: dict[str, Any]) -> BaseChatModel:
        """根据应用设置构造聊天模型实例。

        Args:
            api_key: 已解密的 API Key 明文（由 ConfigManager 提供）。
            settings: 应用设置字典，至少含 temperature / max_context_length。

        Returns:
            配置好的 LangChain 聊天模型（BaseChatModel）实例。

        Raises:
            RuntimeError: 厂商 SDK 初始化失败时抛出（由子类翻译为中文错误）。
        """

    def get_meta(self) -> dict[str, str]:
        """返回模型元信息字典（id / name / description）。

        供 /api/settings 的 available_models 字段使用。
        """
        return {
            "id": self.model_id,
            "name": self.model_name,
            "description": self.description,
        }
