"""
模型工厂。

设计意图：
- 维护「模型 id -> Provider 实例」注册表，是模型接入的唯一登记点。
- 上层（AgentExecutor、/api/settings）通过 ModelFactory.get_provider(model_id)
  获取 Provider，完全解耦具体厂商 SDK。
- 扩展方式：实现新的 BaseModelProvider 子类，然后在本模块的 _REGISTRY
  中加一行注册即可。未来接入 OpenAI / Claude / Ollama 时：
      from models.openai_model import OpenAIProvider
      _REGISTRY["openai"] = OpenAIProvider()
"""

from __future__ import annotations

from typing import Any

from models.base_model import BaseModelProvider
from models.deepseek_model import DeepseekProvider

# 注册表：模型 id -> Provider 实例。
# Provider 无状态，实例可安全复用（线程安全）。
_REGISTRY: dict[str, BaseModelProvider] = {
    "deepseek": DeepseekProvider(),
}


class ModelFactory:
    """模型提供方工厂：按模型 id 查找已注册的 Provider。"""

    @staticmethod
    def get_provider(model_id: str) -> BaseModelProvider:
        """按模型 id 获取 Provider 实例。

        Args:
            model_id: 模型标识（如 "deepseek"），来自应用设置。

        Returns:
            对应的 BaseModelProvider 实例。

        Raises:
            ValueError: 模型 id 未注册时抛出（中文错误信息）。
        """
        provider = _REGISTRY.get(model_id)
        if provider is None:
            # 正常不应发生（settings 校验已限制取值），此为防御性兜底
            raise ValueError(f"未找到模型提供方：{model_id}")
        return provider

    @staticmethod
    def available_models() -> list[dict[str, Any]]:
        """列出所有已注册模型的元信息。

        Returns:
            [{"id","name","description"}, ...]，供 /api/settings 返回给前端。
        """
        return [provider.get_meta() for provider in _REGISTRY.values()]

    @staticmethod
    def available_model_ids() -> list[str]:
        """列出所有已注册模型的 id（用于设置校验）。"""
        return list(_REGISTRY.keys())
