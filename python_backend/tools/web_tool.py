"""
HTTP 网络请求工具。

设计意图：
- 让 Agent 能访问 Web 资源（查询 API、拉取文档等）。
- 安全限制：
  1. 仅允许 http/https 协议（ftp://、file:// 等一律拒绝）；
  2. 仅允许 GET / POST / PUT / DELETE / PATCH 五种常见方法；
  3. 超时 30 秒，避免 LLM 反复调用慢接口拖垮请求。
- 返回状态码 + Content-Type + body（截断约 10KB），结构化呈现给 LLM。
- body 为 dict 时自动按 JSON 发送（Content-Type: application/json）。
"""

from __future__ import annotations

from typing import Any, Callable

import httpx
from langchain_core.tools import tool

from tools.base_tool import truncate_output

# HTTP 请求超时（秒）
HTTP_TIMEOUT_SECONDS = 30
# 允许的 HTTP 方法（大写比较）
ALLOWED_METHODS = {"GET", "POST", "PUT", "DELETE", "PATCH"}


def build_web_tool() -> Callable:
    """构建 HTTP 请求 LangChain 工具（无工作区依赖，全局通用）。

    Returns:
        http_request 工具。
    """

    @tool
    def http_request(
        url: str,
        method: str = "GET",
        body: Any = None,
        headers: dict[str, str] | None = None,
    ) -> str:
        """发起 HTTP 请求并返回响应（仅支持 http/https，超时 30 秒）。

        参数：
            url: 完整的目标 URL，必须以 http:// 或 https:// 开头。
            method: HTTP 方法，可选 GET / POST / PUT / DELETE / PATCH，默认 GET。
            body: 请求体（可选）。传 dict 时自动按 JSON 发送；传字符串时按原文发送。
            headers: 自定义请求头（可选），如 {"Authorization": "Bearer xxx"}。

        返回：
            HTTP 状态码、Content-Type 与响应正文（超长截断到约 10KB）。
        """
        # ---- 协议白名单校验：只放行 http/https ----
        stripped = url.strip()
        if not (stripped.startswith("http://") or stripped.startswith("https://")):
            return f"❌ 错误：仅支持 http/https 协议的 URL，已拒绝：{url}"

        # ---- 方法白名单校验 ----
        method_upper = (method or "GET").strip().upper()
        if method_upper not in ALLOWED_METHODS:
            allowed = "、".join(sorted(ALLOWED_METHODS))
            return f"❌ 错误：不支持的 HTTP 方法 “{method}”。允许的方法：{allowed}"

        # ---- 组装请求参数 ----
        request_headers = dict(headers) if headers else {}
        json_body: Any = None      # 走 httpx 的 json= 参数
        raw_body: str | None = None  # 走 httpx 的 content= 参数
        if body is not None:
            if isinstance(body, dict):
                # dict 自动按 JSON 发送（Content-Type 由 httpx 自动设置）
                json_body = body
            elif isinstance(body, str):
                raw_body = body
            else:
                # list / number 等其他 JSON 可序列化类型，统一走 JSON 通道
                json_body = body

        try:
            with httpx.Client(timeout=HTTP_TIMEOUT_SECONDS, follow_redirects=True) as client:
                response = client.request(
                    method_upper,
                    stripped,
                    headers=request_headers or None,
                    json=json_body,
                    content=raw_body,
                )
        except httpx.TimeoutException:
            return f"❌ 错误：请求超时（>{HTTP_TIMEOUT_SECONDS} 秒）：{url}"
        except httpx.ConnectError as exc:
            return f"❌ 错误：无法连接到目标主机：{exc}"
        except httpx.HTTPError as exc:
            return f"❌ 错误：HTTP 请求失败：{exc}"

        content_type = response.headers.get("content-type", "未知")
        # 响应体截断到约 10KB，防止超大响应撑爆上下文
        text = truncate_output(response.text)
        return (
            f"HTTP {response.status_code}\n"
            f"Content-Type: {content_type}\n"
            f"--- 响应正文 ---\n{text}"
        )

    return http_request
