"""
设置（settings）相关的 Pydantic 模型。

设计意图：
- 定义 /api/settings GET/PUT 的请求与响应结构。
- 安全要点：SettingsData 只含 api_key_configured（bool）只读标志，
  API Key 明文与密文都不回传给前端；更新时通过 SettingsUpdateRequest
  的可选字段实现"部分更新"。
"""

from __future__ import annotations

from pydantic import BaseModel, Field

from config import ALLOWED_CONTEXT_LENGTHS, TEMPERATURE_MAX, TEMPERATURE_MIN
from models.model_factory import ModelFactory

__all__ = [
    "AvailableModel",
    "SettingsData",
    "SettingsResponse",
    "SettingsUpdateRequest",
    "validate_update_request",
]


class AvailableModel(BaseModel):
    """一个可选模型（前端下拉框选项）。"""

    id: str
    name: str


class SettingsData(BaseModel):
    """应用设置（GET /api/settings 返回；不含 API Key 明文/密文）。"""

    # 当前模型标识（如 "deepseek"）
    model: str
    # 温度（0.0~2.0）
    temperature: float
    # 最大上下文长度（token）
    max_context_length: int
    # 是否已配置 API Key（只读派生标志，避免泄露密钥）
    api_key_configured: bool = False


class SettingsResponse(BaseModel):
    """GET /api/settings 响应：设置 + 可用模型列表。"""

    settings: SettingsData
    available_models: list[AvailableModel] = Field(default_factory=list)


class SettingsUpdateRequest(BaseModel):
    """PUT /api/settings 请求体：所有字段可选，支持部分更新。

    数值范围校验在路由层手动完成（validate_update_request），
    以便按契约返回 400 + 中文错误信息，而不是 Pydantic 默认的 422。
    """

    # API Key 明文（后端加密后落盘；None 表示不更新）
    api_key: str | None = None
    # 模型标识（必须已在 ModelFactory 注册）
    model: str | None = None
    # 温度（0.0~2.0）
    temperature: float | None = None
    # 最大上下文长度（只允许 {2048,4096,8192,16384}）
    max_context_length: int | None = None


def validate_update_request(request: SettingsUpdateRequest) -> str | None:
    """对更新请求做业务规则校验（返回 400 中文错误用）。

    校验规则：
    - model 必须已在 ModelFactory 注册；
    - max_context_length 只允许 2048/4096/8192/16384；
    - temperature 必须在 0.0 ~ 2.0 之间。

    Args:
        request: 设置更新请求。

    Returns:
        校验通过返回 None；否则返回中文错误信息（路由层转 400）。
    """
    if request.model is not None and request.model not in ModelFactory.available_model_ids():
        available = "、".join(ModelFactory.available_model_ids())
        return f"不支持的模型：{request.model}（可选：{available}）"
    if request.max_context_length is not None and request.max_context_length not in ALLOWED_CONTEXT_LENGTHS:
        allowed = "、".join(str(x) for x in sorted(ALLOWED_CONTEXT_LENGTHS))
        return f"max_context_length 只允许取值：{allowed}"
    if request.temperature is not None and not (TEMPERATURE_MIN <= request.temperature <= TEMPERATURE_MAX):
        return f"temperature 必须在 {TEMPERATURE_MIN} ~ {TEMPERATURE_MAX} 之间"
    return None
