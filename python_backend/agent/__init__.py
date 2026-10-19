"""
Agent 模块。

设计意图：
- prompt_templates：中文系统提示词模板，向 LLM 说明角色、工作区路径、
  工具使用时机与限制，是控制 Agent 行为的核心。
- agent_executor：AgentExecutor 封装 LangChain create_agent 的调用细节，
  包括历史消息裁剪、工具调用记录提取、异常翻译。
"""

from agent.agent_executor import AgentExecutor

__all__ = ["AgentExecutor"]
