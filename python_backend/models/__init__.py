"""
模型提供方（Provider）抽象层。

设计意图：
- 通过抽象基类 BaseModelProvider 统一不同 LLM 厂商的接入方式，
  上层（AgentExecutor）只依赖抽象接口，不感知具体厂商 SDK。
- ModelFactory 维护「模型 id -> Provider 实例」注册表，
  未来接入 OpenAI / Claude / Ollama 等只需新增 Provider 类并在工厂注册，
  无需改动 Agent 与 API 层代码（开闭原则）。
"""

from models.base_model import BaseModelProvider
from models.deepseek_model import DeepseekProvider
from models.model_factory import ModelFactory

__all__ = ["BaseModelProvider", "DeepseekProvider", "ModelFactory"]
