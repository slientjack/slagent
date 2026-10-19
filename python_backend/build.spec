# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller 打包配置。

设计意图：
- onedir 模式（onedir=True）：把整个应用打成一个目录而非单文件。
  对 langchain / uvicorn 这类动态导入较多的库更稳定（单文件模式
  常因隐式导入缺失在运行时崩溃），启动也更快。
- hiddenimports：PyInstaller 静态分析发现不了的动态导入在此补齐：
  * langchain.agents —— create_agent 入口（子模块动态加载）；
  * langchain_deepseek —— 模型 Provider 的厂商 SDK；
  * uvicorn.logging / uvicorn.loops.auto / uvicorn.protocols ——
    uvicorn 按配置字符串动态 import 的插件体系。
- 打包命令（在本目录执行）：
    pyinstaller build.spec
  产物位于 dist/ai_agent_backend/（macOS/Linux）或 dist\\ai_agent_backend\\（Windows）。
  注意：可执行文件名必须是 ai_agent_backend —— 前端 ProcessManager
  按这个名字探测打包后的后端。
"""

from PyInstaller.utils.hooks import collect_submodules

a = Analysis(
    ["main.py"],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=[
        # Agent 框架核心入口与其子模块（动态加载）
        "langchain.agents",
        *collect_submodules("langchain.agents"),
        # Deepseek 模型 SDK
        "langchain_deepseek",
        # uvicorn 的动态插件体系：日志、事件循环、协议实现
        "uvicorn.logging",
        "uvicorn.loops.auto",
        "uvicorn.loops.asyncio",
        "uvicorn.protocols.http.auto",
        "uvicorn.protocols.http.h11_impl",
        "uvicorn.protocols.websockets.auto",
        "uvicorn.lifespan.on",
        # 加密库底层实现
        "cryptography.fernet",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,   # onedir 模式：二进制留在目录里，不打进单文件
    name="ai_agent_backend",  # 可执行文件名（前端 ProcessManager 按此名探测，勿改）
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,               # 关闭压缩，避免 macOS 签名/公证问题
    console=True,            # 必须保留控制台：stdout 用于 AGENT_SERVER_READY 启动协议
    disable_windowed_traceback=False,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    name="ai_agent_backend",  # 产物目录名：dist/ai_agent_backend/
)
