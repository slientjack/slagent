"""
工作区（workspace）相关的 Pydantic 模型。

设计意图：
- 定义 /api/workspaces CRUD 的请求与响应结构。
- WorkspaceData 是工作区的标准表示：id（uuid4）、名称、本地路径、创建时间。
- StatusResponse 是通用状态响应（{"status":"ok"}），多个端点复用。
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class WorkspaceData(BaseModel):
    """工作区数据（一个本地目录的登记信息）。"""

    # 工作区唯一标识（uuid4）
    id: str
    # 工作区显示名称（用户起的名字）
    name: str
    # 工作区对应的本地目录绝对路径
    path: str
    # 创建时间（ISO8601 UTC）
    createdAt: str


class WorkspaceCreateRequest(BaseModel):
    """POST /api/workspaces 请求体。"""

    # 名称非空校验在路由层做（strip 后非空），以便返回 400 中文错误
    name: str
    # 本地目录路径（后端校验必须存在且是目录）
    path: str


class WorkspaceResponse(BaseModel):
    """单个工作区响应。"""

    workspace: WorkspaceData


class WorkspacesListResponse(BaseModel):
    """工作区列表响应。"""

    workspaces: list[WorkspaceData] = Field(default_factory=list)


class StatusResponse(BaseModel):
    """通用操作成功状态响应。"""

    status: str = "ok"
