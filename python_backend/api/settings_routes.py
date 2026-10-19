"""
设置路由（/api/settings）。

设计意图：
- GET：返回当前设置 + 可用模型列表。安全要点：绝不回传 API Key
  （明文或密文都不返回），只返回 api_key_configured 布尔标志。
- PUT：部分更新。api_key 传明文进来，经 Fernet 加密后以
  api_key_encrypted 字段落盘；temperature / max_context_length / model
  均按业务规则校验（400 + 中文错误信息）。
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, HTTPException

from config import ConfigManager
from models.model_factory import ModelFactory
from schemas.settings_schema import (
    AvailableModel,
    SettingsData,
    SettingsResponse,
    SettingsUpdateRequest,
    validate_update_request,
)
from schemas.workspace_schema import StatusResponse

logger = logging.getLogger(__name__)


def build_router(config_manager: ConfigManager) -> APIRouter:
    """构建设置路由。

    Args:
        config_manager: 配置管理器（settings.json 读写、API Key 加解密）。

    Returns:
        挂载了 GET/PUT 端点的 APIRouter。
    """
    router = APIRouter(prefix="/api/settings", tags=["settings"])

    @router.get("", response_model=SettingsResponse)
    def get_settings() -> SettingsResponse:
        """获取应用设置与可用模型列表（不包含 API Key 任何形式）。"""
        settings = config_manager.load_settings()
        # api_key_configured 是派生只读标志：密文存在即视为已配置
        api_key_configured = bool(settings.get("api_key_encrypted"))
        data = SettingsData(
            model=settings.get("model", "deepseek"),
            temperature=float(settings.get("temperature", 0.7)),
            max_context_length=int(settings.get("max_context_length", 4096)),
            api_key_configured=api_key_configured,
        )
        # 可用模型列表来自 ModelFactory 注册表（单一事实来源）
        models = [
            AvailableModel(id=m["id"], name=m["name"])
            for m in ModelFactory.available_models()
        ]
        return SettingsResponse(settings=data, available_models=models)

    @router.put("", response_model=StatusResponse)
    def update_settings(request: SettingsUpdateRequest) -> StatusResponse:
        """部分更新应用设置（未传的字段保持不变）。

        校验失败返回 400 + 中文错误信息；成功返回 {"status":"ok"}。
        """
        # ---- 业务规则校验（model / temperature / max_context_length）----
        error = validate_update_request(request)
        if error:
            raise HTTPException(status_code=400, detail=error)

        settings = config_manager.load_settings()

        # ---- API Key：明文进、密文存 ----
        if request.api_key is not None and request.api_key.strip():
            settings["api_key_encrypted"] = config_manager.encrypt_api_key(request.api_key.strip())
            logger.info("API Key 已更新（加密存储）")

        # ---- 其余字段：仅更新显式传入的部分 ----
        if request.model is not None:
            settings["model"] = request.model
        if request.temperature is not None:
            settings["temperature"] = request.temperature
        if request.max_context_length is not None:
            settings["max_context_length"] = request.max_context_length

        config_manager.save_settings(settings)
        logger.info(
            "设置已更新：model=%s temperature=%s max_context_length=%s",
            settings.get("model"), settings.get("temperature"), settings.get("max_context_length"),
        )
        return StatusResponse()

    return router
