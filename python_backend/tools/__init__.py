"""
工具包（文件 / 终端 / 网络三类工具）。

设计意图：
- 所有工具都是 LangChain @tool 装饰的函数，docstring 用中文写成 ——
  这些文档会作为工具描述发给 LLM，是 Agent 正确使用工具的关键输入。
- 安全第一：
  * 文件工具通过 _safe_path 把所有相对路径限制在工作区根目录内（防路径穿越）；
  * 终端工具采用「白名单命令 + 危险参数黑名单」双重拦截，shell=False 执行；
  * 网络工具只允许 http/https 协议与常见 HTTP 方法。
- 工具返回值统一为字符串：成功 "✅ ..."、失败 "❌ 错误：..."，便于 LLM 理解结果。
"""

from tools.tool_registry import ToolRegistry

__all__ = ["ToolRegistry"]
