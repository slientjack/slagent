"""
服务器启动模块。

设计意图：
- 用 uvicorn 的程序化 API（Config + Server）启动 FastAPI 应用，
  以支持「随机端口绑定」：前端以子进程方式拉起本后端，端口由操作系统分配。
- 启动协议（前端已按此实现，必须严格遵守）：
  1. 服务绑定 127.0.0.1 随机端口（port=0）；
  2. 服务就绪后向 stdout 打印一行（flush=True）：`AGENT_SERVER_READY port={实际端口}`；
  3. 前端解析该行获得端口，随后发起 HTTP 请求。
- 关闭 uvicorn 的 access log 并将 log_level 设为 warning，避免污染 stdout
  （stdout 上只允许出现 READY 行，否则会破坏启动协议）。
- 捕获 SIGINT/SIGTERM 实现优雅退出。
"""

from __future__ import annotations

import asyncio
import signal

import uvicorn

from api import create_app  # noqa: E402  应用工厂在 api 包的 __init__ 中


def run_server(host: str = "127.0.0.1", port: int = 0) -> int:
    """阻塞式启动 HTTP 服务，返回实际绑定的端口号。

    Args:
        host: 监听地址，默认 127.0.0.1（仅本机访问，安全考虑）。
        port: 监听端口；0 表示由操作系统随机分配（生产/默认模式）。
              传固定端口便于本地开发调试。

    Returns:
        实际绑定的端口号（int）。正常情况下本函数会一直阻塞直到收到退出信号。
    """

    async def _serve() -> int:
        """异步入口：启动 uvicorn server 并等待就绪。"""
        # FastAPI 应用实例（路由、CORS 等在 create_app 中装配）
        app = create_app()

        # uvicorn 配置：
        # - port=0 时由 OS 分配随机端口
        # - access_log=False / log_level="warning"：防止 uvicorn 日志写 stdout 污染启动协议
        config = uvicorn.Config(
            app,
            host=host,
            port=port,
            access_log=False,
            log_level="warning",
        )
        server = uvicorn.Server(config)

        # 把 server.serve() 作为 task 并行运行，便于轮询就绪状态
        serve_task = asyncio.create_task(server.serve())
        # 轮询 server.started，直至 TCP 监听就绪
        while not server.started:
            if serve_task.done():
                # 服务启动阶段即失败（如端口被占用），抛出底层异常
                serve_task.result()
            await asyncio.sleep(0.05)

        # 从底层 socket 取出实际绑定的端口（port=0 时的关键步骤）
        actual_port = server.servers[0].sockets[0].getsockname()[1]

        # ★ 启动协议：READY 行必须 flush=True，前端依赖它发现端口
        print(f"AGENT_SERVER_READY port={actual_port}", flush=True)

        # 注册优雅退出信号处理：SIGINT（Ctrl+C）与 SIGTERM（进程终止）。
        # 注意：uvicorn 0.54 的 should_exit 是普通 bool 属性（非 asyncio.Event），
        # 置 True 即触发优雅停机。
        def _request_shutdown() -> None:
            server.should_exit = True

        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            try:
                loop.add_signal_handler(sig, _request_shutdown)
            except NotImplementedError:
                # Windows 的 ProactorEventLoop 不支持 add_signal_handler，忽略
                pass

        # 等待 server 正常退出（收到信号后 should_exit 置位）
        await serve_task
        return actual_port

    return asyncio.run(_serve())
