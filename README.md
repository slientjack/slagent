# slagent — 本地 AI Agent 桌面应用

一款本地运行的 AI Agent 桌面应用：通过自然语言与 AI 对话，AI 可调用文件操作、
终端命令、网络请求等工具在**指定工作区目录**内完成任务。

- **前端**：Flutter 3.35（macOS / Windows 桌面端，GetX 状态管理）
- **后端**：Python + FastAPI + LangChain（ReAct Agent），默认模型 Deepseek
- **通信**：前端以子进程拉起后端，随机端口 + stdout 就绪协议，HTTP(localhost) 通信
- **存储**：本地 JSON（工作区 / 对话历史 / 设置），API Key Fernet 加密落盘

## 核心特性

| 模块 | 说明 |
| ---- | ---- |
| 工作区管理 | 绑定本地目录作为 Agent 操作范围；创建 / 切换 / 删除（右键菜单，二次确认） |
| 对话 | 按工作区独立持久化历史；气泡样式区分用户/AI；AI 回复 Markdown 渲染（代码块高亮+复制、链接点击、表格）；工具调用记录可折叠查看；加载与错误态 |
| Agent 工具 | 文件读写/编辑/删除/重命名/移动/列目录、白名单终端命令、HTTP 请求 |
| 安全 | 默认文件操作限定工作区、终端命令白名单；越界操作弹窗授权（单次 / 本轮 / 自动 / 拒绝）；API Key 加密存储 |
| 设置 | Deepseek API Key（密码框）、模型选择（预留扩展）、温度滑块、上下文长度 |

架构上预留了多模型扩展点（`python_backend/models/` 的 Provider 注册表），
未来接入 OpenAI / Claude / Ollama 只需实现新的 Provider 并注册。

## 目录结构

```
├── lib/                  # Flutter 前端（GetX：workspace / chat / settings 三模块）
├── python_backend/       # Python 后端（FastAPI + LangChain Agent，含详细中文注释）
│   ├── main.py           # 入口（--port 可固定端口调试）
│   ├── agent/            # Agent 执行器 + 中文提示词模板
│   ├── models/           # 模型 Provider 注册表（deepseek 已实现，可扩展）
│   ├── tools/            # 工具集（文件 / 终端 / 网络 + 安全机制）
│   ├── api/              # 路由（chat / workspace / settings）
│   └── schemas/          # Pydantic 请求/响应模型
├── scripts/              # 打包脚本（build_macos.sh / build_windows.ps1）
└── macos/ windows/       # 平台工程（已配置网络权限等 entitlements）
```

## 本地开发

### 1. 准备环境

- Flutter 3.35+（`flutter doctor` 通过目标平台项）
- Python 3.10+（本机 `python3`）+ 依赖安装：

```bash
cd python_backend
pip3 install -r requirements.txt
```

### 2. 运行应用

```bash
flutter run -d macos     # 或 -d windows
```

前端启动时会自动以子进程方式拉起 `python_backend/main.py`
（随机端口，通过 stdout 的 `AGENT_SERVER_READY port=xxxx` 发现服务）。

调试后端也可以固定端口独立运行：

```bash
cd python_backend && python3 main.py --port 8766
# 环境变量 AGENT_BACKEND_CMD 可让前端改用自定义命令启动后端
```

### 3. 测试

```bash
flutter test              # 前端单元测试
flutter analyze           # 静态检查
```

## 使用说明

1. 启动应用后，首次需点击左下角 **设置** 填入 Deepseek API Key
   （[获取地址](https://platform.deepseek.com)）
2. 左侧 **新建工作区**：输入名称并选择一个本地目录
3. 在对话框中用自然语言下达任务，例如：
   - "列出当前目录的文件"
   - "创建 hello.py，写一个打印九九乘法表的程序"
   - "把 README 里的标题改成大写"
4. AI 会自动判断并调用工具，气泡下方可展开查看工具调用详情

## 数据存储位置

| 数据 | 路径 |
| ---- | ---- |
| 工作区列表 | `{数据目录}/workspaces.json` |
| 对话历史 | `{数据目录}/conversations/{workspace_id}.json` |
| 设置（含加密 API Key） | `{数据目录}/settings.json` |
| 终端命令白名单（可选覆盖） | `{数据目录}/safe_commands.json` |
| 自动允许规则 | `{数据目录}/permissions.json` |
| 日志 | `{数据目录}/logs/app.log` |

数据目录：macOS 为 `~/Library/Application Support/AIAgentApp`，
Windows 为 `%APPDATA%\AIAgentApp`；可用环境变量 `AGENT_DATA_DIR` 覆盖。

## 打包发布

```bash
# macOS：产出内嵌后端的 .app 与 .dmg
./scripts/build_macos.sh

# Windows（PowerShell）：产出含后端的 Release 目录
.\scripts\build_windows.ps1
```

后端经 PyInstaller 打成 onedir（`ai_agent_backend`），嵌入应用资源目录，
用户无需安装 Python 运行环境。详见 `python_backend/README.md`。

> 分发提示：macOS 正式对外分发需 Developer ID 签名 + 公证
> （脚本内已注释示例命令）；Windows 可用 Inno Setup 进一步制作安装器。

## API 一览（localhost，端口动态发现）

| 方法 | 路径 | 说明 |
| ---- | ---- | ---- |
| GET | `/health` | 健康检查 |
| GET/POST | `/api/workspaces` | 工作区列表 / 创建 |
| DELETE | `/api/workspaces/{id}` | 删除工作区（连带清对话） |
| GET/PUT | `/api/settings` | 读取 / 部分更新设置 |
| GET | `/api/chat/history?workspace_id=` | 对话历史 |
| POST | `/api/chat/send` | 发送消息（Agent 执行，含工具调用） |
| POST | `/api/chat/clear` | 清空对话 |
| GET | `/api/permissions/pending?workspace_id=` | 待用户决策的越界授权请求 |
| POST | `/api/permissions/respond` | 提交授权决策（allow_once / allow_session / allow_always / deny） |

## 越界操作授权机制

默认情况下 Agent 只能读写工作区目录内的文件，并只能执行安全白名单内的终端命令。
当 Agent 需要访问工作区外路径、执行白名单外命令（或命中 `rm -rf`、`sudo` 等危险
模式的命令）时，不会再直接拒绝，而是：

1. 工具线程阻塞并向权限管理器登记一条请求；
2. 前端在对话请求进行期间每 800ms 轮询 `/api/permissions/pending`，发现请求后
   弹出不可取消的确认框（高风险操作使用红色警示样式）；
3. 用户选择授权范围：
   - **允许单次运行**：仅本次放行，不记忆；
   - **本轮对话允许**：本次对话（当前工作区）内同一目录/同一命令放行，清空对话或重启进程后失效；
   - **自动允许**：写入 `permissions.json`，重启后仍然生效；
   - **不允许**：本次调用失败，Agent 会收到拒绝信息并改用其它方案。
4. 用户 300 秒内未作答视为拒绝，避免工具线程永久挂起。


错误统一返回 `{"detail": "中文错误信息"}`；LLM 调用失败返回 502。

## 安全说明

- 文件工具全部经 `_safe_path` 路径围栏：resolve 后必须位于工作区根目录内
- 终端命令：白名单（可自定义）+ 危险参数黑名单 + `shell=False` + 30s 超时
- API Key：Fernet 对称加密存储，接口永不回传
- 后端仅绑定 `127.0.0.1`，不暴露局域网
