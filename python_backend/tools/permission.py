"""
权限管理器（PermissionManager）。

设计意图：
- 默认安全模型是「文件操作只能在工作区内、命令只能用白名单」。本模块在
  不放弃该默认模型的前提下，为两类"越界"操作增加**用户实时授权**通道：
  1. 访问工作区之外的路径（file_access）；
  2. 执行安全白名单之外的终端命令（command）。
- 授权动作分四档（与前端对话框一一对应）：
  * allow_once    —— 仅本次调用放行，不记忆；
  * allow_session —— 本工作区本次对话内同类目标放行（进程内存，清空对话/重启即失效）；
  * allow_always  —— 持久化到 permissions.json，之后同类目标直接放行；
  * deny          —— 拒绝本次调用。
- 线程模型：工具调用运行在 Agent 工作线程里，HTTP 请求（/api/permissions/*）
  运行在 uvicorn 线程池里。request() 通过 threading.Event 阻塞等待用户在
  前端弹窗中作答；respond() 在另一个线程置位 event 唤醒它。等待期间不持有锁，
  避免死锁。
- 匹配粒度：
  * 文件：记录"目录规则"。文件取父目录，目录取其自身；判断时看目标是否
    位于已授权目录之下（前缀匹配），避免同一目录下每个文件都弹一次窗。
  * 命令：记录完整命令字符串，必须完全一致才放行（不扩大授权范围）。
- 超时：等待超过 PERMISSION_TIMEOUT_SECONDS 视为拒绝，防止前端异常退出后
  工作线程永久挂起。
"""

from __future__ import annotations

import json
import logging
import threading
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal

logger = logging.getLogger(__name__)

# 权限请求类型
PermissionType = Literal["file_access", "command"]

# 用户决策
PermissionDecision = Literal["allow_once", "allow_session", "allow_always", "deny"]

# 等待用户授权的超时时间（秒）。超时按拒绝处理。
PERMISSION_TIMEOUT_SECONDS = 300


def _now_iso() -> str:
    """当前时间的 ISO8601 UTC 字符串。"""
    return datetime.now(timezone.utc).isoformat()


@dataclass
class _PendingRequest:
    """一条等待用户决策的权限请求（仅存在于内存）。"""

    id: str
    workspace_id: str
    type: str
    target: str
    detail: str
    risk: str
    created_at: str
    # 用户决策的同步原语：respond() 写入 decision 并 set()，request() 等待
    event: threading.Event = field(default_factory=threading.Event, repr=False)
    decision: str | None = None

    def to_dict(self) -> dict[str, Any]:
        """转换为 API 响应结构（不含 event 等内部字段）。"""
        return {
            "id": self.id,
            "workspace_id": self.workspace_id,
            "type": self.type,
            "target": self.target,
            "detail": self.detail,
            "risk": self.risk,
            "created_at": self.created_at,
        }


class PermissionManager:
    """越界操作的实时授权管理器。

    保存三类状态：
    - _pending：当前等待用户作答的请求（内存）；
    - _session_rules：本工作区本次对话的放行规则（内存）；
    - _always_rules：持久化放行规则（permissions.json）。
    """

    def __init__(self, data_dir: str | Path) -> None:
        """初始化权限管理器并从磁盘加载"自动允许"规则。

        Args:
            data_dir: 应用数据目录（permissions.json 位于该目录下）。
        """
        self._rules_file = Path(data_dir) / "permissions.json"
        # 保护 _pending / _session_rules / _always_rules 的并发访问
        self._lock = threading.Lock()

        self._pending: dict[str, _PendingRequest] = {}
        # workspace_id -> {"file_access": set(), "command": set()}
        self._session_rules: dict[str, dict[str, set[str]]] = {}
        # 持久化规则（全局生效，不区分工作区）
        self._always_rules: dict[str, set[str]] = {
            "file_access": set(),
            "command": set(),
        }

        self._load_rules()

    # ------------------------------------------------------------------
    # 规则持久化
    # ------------------------------------------------------------------

    def _load_rules(self) -> None:
        """从 permissions.json 加载"自动允许"规则；文件不存在或损坏时忽略。"""
        if not self._rules_file.exists():
            return
        try:
            data = json.loads(self._rules_file.read_text(encoding="utf-8"))
            rules = data.get("rules", []) if isinstance(data, dict) else []
            for rule in rules:
                if not isinstance(rule, dict):
                    continue
                ptype = rule.get("type")
                target = rule.get("target")
                if ptype in self._always_rules and isinstance(target, str) and target:
                    self._always_rules[ptype].add(target)
            logger.info(
                "已加载自动允许规则：文件 %d 条，命令 %d 条",
                len(self._always_rules["file_access"]),
                len(self._always_rules["command"]),
            )
        except (json.JSONDecodeError, OSError) as exc:
            logger.warning("permissions.json 读取失败，忽略已有规则：%s", exc)

    def _save_rules(self) -> None:
        """把自动允许规则原子地写回 permissions.json（调用方需持有锁）。"""
        rules = []
        for ptype, targets in self._always_rules.items():
            for target in sorted(targets):
                rules.append({"type": ptype, "target": target})
        payload = {"rules": rules, "updatedAt": _now_iso()}
        try:
            self._rules_file.write_text(
                json.dumps(payload, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        except OSError as exc:
            # 落盘失败不影响本次授权生效（仅内存记住）
            logger.error("permissions.json 写入失败：%s", exc)

    # ------------------------------------------------------------------
    # 规则匹配与记忆
    # ------------------------------------------------------------------

    @staticmethod
    def _normalize_file_target(target: str) -> str:
        """把文件目标解析为绝对路径（符号链接、../ 等统一展开）。"""
        try:
            return str(Path(target).expanduser().resolve())
        except OSError:
            return str(Path(target).absolute())

    @staticmethod
    def _file_rule_for(target: str) -> str:
        """计算文件目标对应的规则目录。

        文件 → 其父目录（允许同目录下其它文件，减少重复弹窗）；
        目录 → 其自身。
        """
        path = Path(target)
        try:
            if path.is_dir():
                return str(path.resolve())
            return str(path.resolve().parent)
        except OSError:
            return str(path.absolute().parent)

    def _is_allowed_by(self, ptype: str, target: str, rules: set[str]) -> bool:
        """判断目标是否命中一组放行规则。"""
        if not rules:
            return False
        if ptype == "command":
            # 命令必须完全一致，避免"允许 ls"被扩大解释为允许任意参数
            return target in rules
        # 文件：目标等于规则目录或位于其下
        target_path = Path(target)
        for rule in rules:
            rule_path = Path(rule)
            if target_path == rule_path:
                return True
            try:
                if target_path.is_relative_to(rule_path):
                    return True
            except (ValueError, OSError):
                continue
        return False

    def is_allowed(self, workspace_id: str, ptype: str, target: str) -> bool:
        """检查目标是否已被放行（会话规则或持久化规则）。

        Args:
            workspace_id: 工作区 id（会话规则按工作区隔离）。
            ptype: "file_access" 或 "command"。
            target: 归一化后的目标（文件为绝对路径，命令为完整命令字符串）。

        Returns:
            True 表示无需询问用户、可直接放行。
        """
        # 与 request() 保持一致的归一化，避免调用方传入未解析路径导致误判
        normalized = (
            self._normalize_file_target(target) if ptype == "file_access" else target.strip()
        )
        with self._lock:
            session = self._session_rules.get(workspace_id, {}).get(ptype, set())
            if self._is_allowed_by(ptype, normalized, session):
                return True
            always = self._always_rules.get(ptype, set())
            return self._is_allowed_by(ptype, normalized, always)

    def _remember_session(self, workspace_id: str, ptype: str, target: str) -> None:
        """记住"本轮对话允许"规则（内存，进程退出即失效）。"""
        with self._lock:
            bucket = self._session_rules.setdefault(
                workspace_id, {"file_access": set(), "command": set()}
            )
            bucket[ptype].add(target)

    def _remember_always(self, ptype: str, target: str) -> None:
        """记住"自动允许"规则并持久化。"""
        with self._lock:
            self._always_rules[ptype].add(target)
            self._save_rules()
        logger.info("已添加自动允许规则：[%s] %s", ptype, target)

    def clear_session(self, workspace_id: str) -> None:
        """清空指定工作区的会话级授权（清空对话、删除工作区时调用）。"""
        with self._lock:
            self._session_rules.pop(workspace_id, None)

    # ------------------------------------------------------------------
    # 请求 / 响应
    # ------------------------------------------------------------------

    def request(
        self,
        workspace_id: str,
        ptype: PermissionType,
        target: str,
        detail: str = "",
        risk: str = "normal",
    ) -> bool:
        """发起一次权限请求并阻塞等待用户决策。

        该方法由工具在 Agent 工作线程中调用；前端通过轮询
        /api/permissions/pending 发现请求并弹窗，用户选择后调用
        /api/permissions/respond 唤醒本方法。

        Args:
            workspace_id: 工作区 id。
            ptype: 请求类型（file_access / command）。
            target: 请求目标（文件绝对路径或完整命令）。
            detail: 给用户看的说明文本。
            risk: "normal" 或 "high"（高风险会在前端突出显示）。

        Returns:
            True 表示允许执行；False 表示拒绝或超时。
        """
        # 文件目标统一归一化；命令去掉首尾空白
        normalized = (
            self._normalize_file_target(target) if ptype == "file_access" else target.strip()
        )

        # 已授权（会话或持久化）则直接放行，不打扰用户
        if self.is_allowed(workspace_id, ptype, normalized):
            return True

        req = _PendingRequest(
            id=str(uuid.uuid4()),
            workspace_id=workspace_id,
            type=ptype,
            target=normalized,
            detail=detail,
            risk=risk,
            created_at=_now_iso(),
        )
        with self._lock:
            self._pending[req.id] = req

        logger.info(
            "等待用户授权：[%s] %s（工作区 %s）", ptype, normalized, workspace_id
        )

        # 阻塞等待：respond() 会设置 decision 并 set() 事件
        req.event.wait(PERMISSION_TIMEOUT_SECONDS)

        with self._lock:
            self._pending.pop(req.id, None)
            decision = req.decision

        if decision is None:
            logger.warning("授权请求超时（%d 秒），按拒绝处理：[%s] %s",
                           PERMISSION_TIMEOUT_SECONDS, ptype, normalized)
            return False

        if decision == "deny":
            logger.info("用户拒绝授权：[%s] %s", ptype, normalized)
            return False

        # 记忆授权范围
        rule_target = self._file_rule_for(normalized) if ptype == "file_access" else normalized
        if decision == "allow_session":
            self._remember_session(workspace_id, ptype, rule_target)
        elif decision == "allow_always":
            self._remember_always(ptype, rule_target)

        logger.info("用户允许授权：[%s] %s（决策=%s）", ptype, normalized, decision)
        return True

    def get_pending(self, workspace_id: str | None = None) -> list[dict[str, Any]]:
        """返回当前等待用户决策的请求列表（可按工作区过滤）。

        Args:
            workspace_id: 为 None 时返回全部；否则只返回该工作区的请求。

        Returns:
            请求字典列表（按创建时间排序）。
        """
        with self._lock:
            requests = [
                req.to_dict()
                for req in self._pending.values()
                if workspace_id is None or req.workspace_id == workspace_id
            ]
        requests.sort(key=lambda item: item["created_at"])
        return requests

    def respond(self, request_id: str, decision: PermissionDecision) -> bool:
        """提交用户对某条权限请求的决策，唤醒等待中的工具线程。

        Args:
            request_id: 请求 id（来自 pending 接口）。
            decision: allow_once / allow_session / allow_always / deny。

        Returns:
            True 表示请求存在且已被处理；False 表示请求不存在或已处理。
        """
        with self._lock:
            req = self._pending.get(request_id)
            if req is None or req.event.is_set():
                return False
            req.decision = decision
            req.event.set()
        return True
