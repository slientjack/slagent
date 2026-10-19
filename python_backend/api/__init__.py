"""
API 路由包。

设计意图：
- create_app() 是应用工厂：统一装配 ConfigManager、AgentExecutor、
  各领域路由与健康检查端点，server.py 只负责把这个 app 跑起来。
- 路由模块通过 build_router(...) 工厂函数接收依赖（ConfigManager /
  AgentExecutor），依赖显式注入、便于测试，也避免模块间隐式全局状态。
"""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from agent.agent_executor import AgentExecutor
from api import chat_routes, settings_routes, workspace_routes
from config import ConfigManager


def create_app() -> FastAPI:
    """创建并装配 FastAPI 应用实例。

    Returns:
        配置好全部路由与中间件的 FastAPI 应用。
    """
    # ---- 全局单例依赖：配置管理器 与 Agent 执行器 ----
    config_manager = ConfigManager()
    agent_executor = AgentExecutor(config_manager)

    app = FastAPI(
        title="本地 AI Agent 后端服务",
        description="为 AI Agent 桌面应用提供工作区管理、对话、设置等 HTTP 接口",
        version="1.0.0",
    )

    # CORS：桌面端本体不走浏览器（无 CORS 概念），此处放宽以便前端
    # 以 WebView / Web 调试模式访问；服务只绑定 127.0.0.1，风险可控。
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # ---- 健康检查（启动协议之外的探活端点）----
    @app.get("/health", tags=["system"])
    def health_check() -> dict[str, str]:
        """健康检查端点：服务存活探测。"""
        return {"status": "ok"}

    # ---- 领域路由：工作区 / 设置 / 对话 ----
    app.include_router(workspace_routes.build_router(config_manager))
    app.include_router(settings_routes.build_router(config_manager))
    app.include_router(chat_routes.build_router(config_manager, agent_executor))

    return app
