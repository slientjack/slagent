# Python 后端（python_backend/）

本地 AI Agent 桌面应用的 Python 后端服务：以子进程方式被 Flutter 前端拉起，
通过 HTTP API（JSON）提供工作区管理、文件/终端/网络工具、LLM 对话能力。
基于 **FastAPI + LangChain 1.x（create_agent）+ Deepseek**。

## 模块结构

```
python_backend/
├── main.py                 # 入口：argparse（--port/--host），默认随机端口
├── config.py               # ConfigManager：数据目录、settings.json、API Key Fernet 加密、安全命令白名单、日志
├── server.py               # uvicorn 程序化启动、AGENT_SERVER_READY 协议、优雅退出
├── models/                 # LLM 提供方抽象层（策略模式 + 工厂模式）
│   ├── base_model.py       #   抽象基类 BaseModelProvider（get_llm 抽象方法）
│   ├── deepseek_model.py   #   DeepseekProvider：封装 ChatDeepSeek
│   └── model_factory.py    #   ModelFactory：注册表 {"deepseek": DeepseekProvider}
├── tools/                  # Agent 工具层（LangChain @tool）
│   ├── base_tool.py        #   _safe_path 路径安全闸门 + truncate_output 输出截断
│   ├── file_tools.py       #   read/create/edit/delete/rename/list 文件工具
│   ├── terminal_tool.py    #   execute_command：白名单 + 危险参数黑名单、shell=False
│   ├── web_tool.py         #   http_request：仅 http/https、常见方法、30s 超时
│   └── tool_registry.py    #   ToolRegistry.build_all_tools 汇总登记
├── agent/                  # Agent 核心
│   ├── prompt_templates.py #   中文系统提示词（注入工作区路径、工具使用规程）
│   └── agent_executor.py   #   AgentExecutor：历史裁剪、invoke、回复与工具调用提取
├── api/                    # HTTP 路由层
│   ├── __init__.py         #   create_app 应用工厂
│   ├── chat_routes.py      #   /api/chat/history | clear | send
│   ├── workspace_routes.py #   /api/workspaces CRUD
│   └── settings_routes.py  #   /api/settings GET/PUT
├── schemas/                # Pydantic 请求/响应模型
├── requirements.txt        # 依赖清单
├── build.spec              # PyInstaller 打包配置（onedir 模式）
└── README.md               # 本文件
```

## 启动协议

前端以子进程方式启动本服务，通过 stdout 单行握手发现端口：

1. 服务绑定 `127.0.0.1` 随机端口（`--port 0`，默认）；
2. 就绪后向 stdout 打印一行（flush）：`AGENT_SERVER_READY port={实际端口}`；
3. 前端解析该行获得端口后发起 HTTP 请求。

因此 stdout 只允许出现 READY 行（uvicorn 的 access log 已关闭、日志走 stderr/文件）。

## 本地开发

```bash
cd python_backend
pip install -r requirements.txt

# 固定端口调试（推荐）
python main.py --port 8766

# 随机端口（模拟前端拉起方式，观察 READY 行）
python main.py

# 测试用独立数据目录（不污染正式数据）
AGENT_DATA_DIR=/tmp/agent_dev python main.py --port 8766
```

数据目录位置（可用环境变量 `AGENT_DATA_DIR` 覆盖）：

| 系统 | 目录 |
| --- | --- |
| macOS | `~/Library/Application Support/AIAgentApp` |
| Windows | `%APPDATA%/AIAgentApp` |
| 其他 | `~/.local/share/AIAgentApp` |

目录内容：`settings.json`（设置，API Key 以 `api_key_encrypted` 密文存储）、
`workspaces.json`（工作区列表）、`.secret_key`（Fernet 密钥，0600）、
`conversations/{workspace_id}.json`（对话历史）、`logs/app.log`（滚动日志 5MB×3）、
`safe_commands.json`（可选，用户自定义终端命令白名单，存在则覆盖默认）。

## API 一览

所有错误均为 `HTTPException`，`detail` 为中文友好信息；请求/响应均为 JSON。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/health` | 健康检查 → `{"status":"ok"}` |
| GET | `/api/workspaces` | 工作区列表 |
| POST | `/api/workspaces` | 新建工作区（name 非空、path 须为已存在目录） |
| DELETE | `/api/workspaces/{id}` | 删除工作区（联动删除其对话历史） |
| GET | `/api/settings` | 读取设置 + 可用模型（不回传 API Key，仅 `api_key_configured`） |
| PUT | `/api/settings` | 部分更新设置（api_key 明文进、密文存） |
| GET | `/api/chat/history?workspace_id=` | 对话历史（无历史返回空数组） |
| POST | `/api/chat/clear` | 清空指定工作区对话 |
| POST | `/api/chat/send` | 发送消息并执行 Agent，返回回复与工具调用记录 |

`/api/chat/send` 请求体：

```json
{
  "message": "帮我看看这个目录里有什么",
  "workspace_id": "xxx",
  "settings": {"temperature": 0.5, "max_context_length": 8192}
}
```

`settings` 为本次请求的临时覆盖，不持久化。响应：`{"response": "...", "tool_calls": [{"tool","args","result"}]}`。
LLM 调用失败（key 无效、网络错误、超时）返回 502 + 中文说明。

## 打包

```bash
cd python_backend
pyinstaller build.spec
# 产物：dist/ai_agent_backend/（onedir 模式，含可执行文件 ai_agent_backend）
# 注意：可执行文件名 ai_agent_backend 是前端探测约定，勿改
```

console 模式必须保留：stdout 用于 `AGENT_SERVER_READY` 启动协议。
hiddenimports 已补齐 langchain.agents、langchain_deepseek、uvicorn 插件体系等
动态导入。

## 安全机制

1. **API Key 加密存储**：Fernet 对称加密（密钥文件 `.secret_key` 首次自动生成，
   权限 0600）；`settings.json` 只存密文，任何 API 都不回传明文/密文。
2. **文件工具路径围栏**：所有路径经 `_safe_path` 解析，resolve 后必须位于
   工作区根目录内，`../` 越界直接拒绝（PermissionError），防提示注入逃逸。
3. **终端命令双层拦截**：
   - 白名单：首命令必须在安全列表内（默认 ls/cat/git/python3 等，
     用户可用 `safe_commands.json` 覆盖）；
   - 黑名单：危险参数模式拦截（rm -rf、mkfs、dd if=、sudo、shutdown、
     reboot、fork 炸弹等，不区分大小写）；
   - `subprocess.run(shell=False)`：不经 shell 解析，杜绝命令注入；
     cwd 锁定工作区，30 秒超时。
4. **网络工具限制**：仅 http/https 协议、仅 GET/POST/PUT/DELETE/PATCH、
   30 秒超时，响应体截断约 10KB。
5. **上下文保护**：工具输出统一截断（约 10KB，文件读取上限 100KB）；
   对话历史按 token 估算裁剪（CJK 字符≈1 token，其余≈0.25 token/字符，
   至少保留最近 2 条消息）。
6. **服务只绑定 127.0.0.1**：不暴露到局域网。

## 扩展新模型

实现 `BaseModelProvider` 子类并在 `models/model_factory.py` 的注册表中加一行：

```python
_REGISTRY["openai"] = OpenAIProvider()   # 未来接入示例
```

API 层与 Agent 层零改动，`/api/settings` 的 available_models 自动更新。
