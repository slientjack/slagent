"""
应用入口。

用法：
    python main.py               # 随机端口（默认，供前端以子进程拉起）
    python main.py --port 8766   # 固定端口（本地开发调试用）
    python main.py --host 0.0.0.0 --port 8766  # 自定义监听地址（调试用）

设计意图：
- 仅负责命令行参数解析，真正的启动逻辑在 server.run_server 中，
  保持入口精简、便于测试与打包（PyInstaller 以此文件为入口）。
"""

from __future__ import annotations

import argparse
import logging

from server import run_server


def main() -> None:
    """解析命令行参数并启动 HTTP 服务。"""
    parser = argparse.ArgumentParser(description="本地 AI Agent 桌面应用 - Python 后端服务")
    # --port：固定端口便于调试；默认 0 表示随机端口（前端启动协议要求）
    parser.add_argument(
        "--port",
        type=int,
        default=0,
        help="监听端口（默认 0 = 随机端口，由前端通过 AGENT_SERVER_READY 行发现）",
    )
    # --host：默认仅绑定回环地址，避免局域网暴露
    parser.add_argument(
        "--host",
        type=str,
        default="127.0.0.1",
        help="监听地址（默认 127.0.0.1，仅本机访问）",
    )
    args = parser.parse_args()

    logger = logging.getLogger(__name__)
    logger.info("正在启动服务：host=%s port=%s", args.host, args.port if args.port else "随机")

    try:
        run_server(host=args.host, port=args.port)
    except KeyboardInterrupt:
        # Ctrl+C 优雅退出，不打堆栈
        logger.info("收到中断信号，服务已退出")


if __name__ == "__main__":
    main()
