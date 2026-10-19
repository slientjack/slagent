"""
配置管理模块（ConfigManager）。

设计意图：
- 集中管理应用的所有持久化数据：settings.json（应用设置）、workspaces.json（工作区列表）、
  .secret_key（Fernet 加密密钥）、conversations/（各工作区对话历史）、logs/（日志文件）。
- 数据目录按操作系统惯例解析（macOS: ~/Library/Application Support/AIAgentApp，
  Windows: %APPDATA%/AIAgentApp，其他: ~/.local/share/AIAgentApp），
  并支持环境变量 AGENT_DATA_DIR 覆盖，方便开发与测试。
- API Key 属于敏感信息，使用 cryptography.fernet 对称加密后落盘（字段名 api_key_encrypted），
  绝不以明文形式存储；密钥文件首次自动生成，权限 0600。
- 安全命令白名单（终端工具允许执行的命令）默认值也定义在此处，
  用户可通过数据目录下的 safe_commands.json 覆盖默认白名单。
- 日志同时输出到控制台和 logs/app.log（RotatingFileHandler，5MB×3）。
"""

from __future__ import annotations

import json
import logging
import os
import sys
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any

from cryptography.fernet import Fernet, InvalidToken

# ---------------------------------------------------------------------------
# 默认设置与常量
# ---------------------------------------------------------------------------

# 默认模型标识（对应 ModelFactory 注册表中的 key）
DEFAULT_MODEL = "deepseek"
# 默认温度参数（控制生成随机性）
DEFAULT_TEMPERATURE = 0.7
# 默认最大上下文长度（发送给 LLM 前按此裁剪历史消息）
DEFAULT_MAX_CONTEXT_LENGTH = 4096
# 允许设置的最大上下文长度取值集合（前端下拉框选项与此保持一致）
ALLOWED_CONTEXT_LENGTHS = {2048, 4096, 8192, 16384}
# 温度合法范围
TEMPERATURE_MIN = 0.0
TEMPERATURE_MAX = 2.0

# 终端工具默认安全命令白名单：仅允许只读浏览类 + 常见开发命令。
# 用户可在数据目录放置 safe_commands.json（JSON 数组）覆盖此默认值。
DEFAULT_SAFE_COMMANDS = [
    "ls", "cat", "pwd", "echo", "grep", "find", "head", "tail",
    "wc", "sort", "uniq", "diff", "mkdir", "touch", "git",
    "python3", "node", "npm",
]

# 日志格式：时间 - 级别 - 模块名 - 消息
_LOG_FORMAT = "%(asctime)s - %(levelname)s - [%(name)s] %(message)s"


def _default_data_dir() -> Path:
    """按操作系统惯例解析默认数据目录。

    - macOS:   ~/Library/Application Support/AIAgentApp
    - Windows: %APPDATA%/AIAgentApp
    - 其他:    ~/.local/share/AIAgentApp
    """
    app_name = "AIAgentApp"
    if sys.platform == "darwin":  # macOS
        base = Path.home() / "Library" / "Application Support"
    elif sys.platform == "win32":  # Windows
        base = Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    else:  # Linux 及其他类 Unix 系统，遵循 XDG 惯例
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return base / app_name


class ConfigManager:
    """应用配置与持久化数据管理器。

    职责：
    1. 解析并初始化数据目录（含子目录 conversations/、logs/）；
    2. settings.json 的读取与写入（带内存缓存，避免频繁磁盘 IO）；
    3. API Key 的 Fernet 加解密（密钥文件 .secret_key 首次自动生成）；
    4. 安全命令白名单的读取（safe_commands.json 存在则覆盖默认值）；
    5. 日志系统初始化（控制台 + RotatingFileHandler）。
    """

    def __init__(self, data_dir: str | Path | None = None) -> None:
        """初始化配置管理器。

        Args:
            data_dir: 数据目录路径。为 None 时依次尝试环境变量 AGENT_DATA_DIR、
                      系统默认目录。构造时会确保目录结构存在。
        """
        # 环境变量 AGENT_DATA_DIR 优先级最高（开发/测试用）
        env_dir = os.environ.get("AGENT_DATA_DIR")
        root = Path(data_dir) if data_dir else (Path(env_dir) if env_dir else _default_data_dir())

        self.data_dir = root
        self.settings_file = root / "settings.json"          # 应用设置文件
        self.workspaces_file = root / "workspaces.json"      # 工作区列表文件
        self.secret_key_file = root / ".secret_key"          # Fernet 密钥文件
        self.conversations_dir = root / "conversations"      # 各工作区对话历史目录
        self.logs_dir = root / "logs"                        # 日志目录
        self.safe_commands_file = root / "safe_commands.json"  # 用户自定义命令白名单

        # 确保目录结构存在（parents=True：连同父目录一起创建）
        self.conversations_dir.mkdir(parents=True, exist_ok=True)
        self.logs_dir.mkdir(parents=True, exist_ok=True)

        # 初始化日志（只需执行一次）
        self._setup_logging()

        # 设置缓存：首次访问时从磁盘加载
        self._settings_cache: dict[str, Any] | None = None

    # ------------------------------------------------------------------
    # 日志初始化
    # ------------------------------------------------------------------

    def _setup_logging(self) -> None:
        """初始化全局日志：控制台 + rotating 文件（5MB × 3 个备份）。

        幂等设计：重复调用不会重复添加 handler。
        """
        logger = logging.getLogger()  # 获取根 logger，使所有模块日志统一输出
        if getattr(logger, "_agent_app_configured", False):
            return  # 已初始化，跳过

        logger.setLevel(logging.INFO)
        formatter = logging.Formatter(_LOG_FORMAT)

        # 控制台输出（stderr，避免污染 stdout —— stdout 用于 READY 协议）
        console_handler = logging.StreamHandler()
        console_handler.setFormatter(formatter)
        logger.addHandler(console_handler)

        # 文件输出：单个文件最大 5MB，保留 3 个历史备份
        file_handler = RotatingFileHandler(
            self.logs_dir / "app.log",
            maxBytes=5 * 1024 * 1024,
            backupCount=3,
            encoding="utf-8",
        )
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)

        # 降低 uvicorn/httpx 的日志级别，减少噪音
        logging.getLogger("uvicorn").setLevel(logging.WARNING)
        logging.getLogger("httpx").setLevel(logging.WARNING)

        # 标记已初始化（挂在 logger 实例上，实现幂等）
        logger._agent_app_configured = True  # type: ignore[attr-defined]

        logger.info("数据目录初始化完成：%s", self.data_dir)

    # ------------------------------------------------------------------
    # Fernet 密钥与 API Key 加解密
    # ------------------------------------------------------------------

    def _get_fernet(self) -> Fernet:
        """获取 Fernet 实例；密钥文件不存在时自动生成（权限 0600）。

        Returns:
            Fernet 实例，用于 api_key 的加解密。
        """
        if not self.secret_key_file.exists():
            # 首次运行：生成新的 Fernet 密钥并写入文件
            key = Fernet.generate_key()
            self.secret_key_file.write_bytes(key)
            # 设置文件权限为 0600（仅所有者可读写）；Windows 无此概念，忽略失败
            try:
                os.chmod(self.secret_key_file, 0o600)
            except OSError:
                pass
            logging.getLogger(__name__).info("已生成新的加密密钥文件：%s", self.secret_key_file)
        key = self.secret_key_file.read_bytes().strip()
        return Fernet(key)

    def encrypt_api_key(self, plain_key: str) -> str:
        """加密 API Key 明文，返回可安全落盘的密文字符串。

        Args:
            plain_key: API Key 明文。

        Returns:
            Fernet 加密后的密文（utf-8 字符串）。
        """
        fernet = self._get_fernet()
        return fernet.encrypt(plain_key.encode("utf-8")).decode("utf-8")

    def decrypt_api_key(self, encrypted_key: str) -> str:
        """解密 API Key 密文，返回明文。

        Args:
            encrypted_key: settings.json 中存储的 api_key_encrypted 字段值。

        Returns:
            API Key 明文。

        Raises:
            ValueError: 密钥文件变更或密文损坏导致解密失败时抛出。
        """
        fernet = self._get_fernet()
        try:
            return fernet.decrypt(encrypted_key.encode("utf-8")).decode("utf-8")
        except InvalidToken as exc:
            # 典型场景：用户手动更换了 .secret_key 文件，旧密文无法解密
            raise ValueError("API Key 解密失败：加密密钥文件可能已变更，请重新配置 API Key") from exc

    # ------------------------------------------------------------------
    # settings.json 读写
    # ------------------------------------------------------------------

    def _default_settings(self) -> dict[str, Any]:
        """返回默认设置字典（首次运行或文件损坏时使用）。"""
        return {
            "model": DEFAULT_MODEL,
            "temperature": DEFAULT_TEMPERATURE,
            "max_context_length": DEFAULT_MAX_CONTEXT_LENGTH,
            # api_key_encrypted 存 Fernet 密文；None 表示尚未配置
            "api_key_encrypted": None,
        }

    def load_settings(self) -> dict[str, Any]:
        """加载应用设置（带内存缓存）。

        Returns:
            设置字典，含 model / temperature / max_context_length / api_key_encrypted。
        """
        if self._settings_cache is not None:
            return self._settings_cache

        settings = self._default_settings()
        if self.settings_file.exists():
            try:
                raw = json.loads(self.settings_file.read_text(encoding="utf-8"))
                if isinstance(raw, dict):
                    # 只接受已知字段，忽略无关内容
                    for key in ("model", "temperature", "max_context_length", "api_key_encrypted"):
                        if key in raw:
                            settings[key] = raw[key]
            except (json.JSONDecodeError, OSError) as exc:
                # 文件损坏时回退默认值，不让应用崩溃
                logging.getLogger(__name__).warning("settings.json 读取失败，使用默认设置：%s", exc)

        self._settings_cache = settings
        return settings

    def save_settings(self, settings: dict[str, Any]) -> None:
        """将设置字典持久化到 settings.json（同时更新内存缓存）。

        Args:
            settings: 完整设置字典。
        """
        self.settings_file.write_text(
            json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        self._settings_cache = settings

    def get_decrypted_api_key(self) -> str | None:
        """取出已配置的 API Key 明文（供调用 LLM 时使用）。

        Returns:
            API Key 明文；未配置或解密失败时返回 None。
        """
        settings = self.load_settings()
        encrypted = settings.get("api_key_encrypted")
        if not encrypted:
            return None
        try:
            return self.decrypt_api_key(encrypted)
        except ValueError:
            # 解密失败（密钥文件变更等）视同未配置，由上层引导用户重新设置
            return None

    # ------------------------------------------------------------------
    # 安全命令白名单
    # ------------------------------------------------------------------

    def get_safe_commands(self) -> list[str]:
        """获取终端工具允许执行的命令白名单。

        优先读取数据目录下的 safe_commands.json（用户自定义覆盖），
        不存在或格式非法时使用 DEFAULT_SAFE_COMMANDS 默认白名单。

        Returns:
            允许执行的命令名列表（小写）。
        """
        if self.safe_commands_file.exists():
            try:
                raw = json.loads(self.safe_commands_file.read_text(encoding="utf-8"))
                if isinstance(raw, list) and raw and all(isinstance(x, str) for x in raw):
                    # 统一转小写，便于后续不区分大小写匹配
                    return [x.strip().lower() for x in raw if x.strip()]
                logging.getLogger(__name__).warning(
                    "safe_commands.json 格式非法（应为非空字符串数组），使用默认白名单"
                )
            except (json.JSONDecodeError, OSError) as exc:
                logging.getLogger(__name__).warning(
                    "safe_commands.json 读取失败，使用默认白名单：%s", exc
                )
        return list(DEFAULT_SAFE_COMMANDS)
