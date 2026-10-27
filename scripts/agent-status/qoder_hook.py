#!/usr/bin/env python3
"""One-way Qoder status hook. Never returns an approval decision."""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import time


def status_for(event):
    kind = event.get("hook_event_name")
    tool = str(event.get("tool_name", ""))[:48]
    if kind == "SessionStart":
        return "idle", "会话已连接"
    if kind == "UserPromptSubmit":
        return "running", "正在处理任务"
    if kind == "PreToolUse":
        if tool in ("AskUserQuestion", "ExitPlanMode"):
            return "waiting", "等待你回答或确认计划"
        return "running", "执行工具：" + tool
    if kind == "PermissionRequest":
        return "waiting", "等待权限确认"
    if kind in ("PostToolUse", "PostToolUseFailure"):
        return "running", "继续处理任务" if kind == "PostToolUse" else "工具失败，Agent 正在处理"
    if kind == "Notification" and event.get("notification_type") == "permission_prompt":
        return "waiting", "等待权限确认"
    if kind == "Stop":
        return "completed", "本轮回复已结束"
    if kind == "SessionEnd":
        return "idle", "会话已关闭"
    return None


def main():
    event = json.loads(sys.stdin.buffer.read(1024 * 1024))
    session_id = event.get("session_id")
    state = status_for(event)
    if not isinstance(session_id, str) or not session_id or len(session_id) > 200 or not state:
        return
    root = Path(__file__).resolve().parent.parent / "boring-notch-events"
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    record = {"version": 1, "session_id": session_id, "state": state[0],
              "detail": state[1], "project": Path(event.get("cwd", "")).name[:160],
              "timestamp": time.time()}
    target = root / (hashlib.sha256(session_id.encode()).hexdigest() + ".json")
    descriptor, temp = tempfile.mkstemp(prefix=".event-", dir=root)
    try:
        with os.fdopen(descriptor, "w") as stream:
            json.dump(record, stream, ensure_ascii=False)
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    for old in root.glob("*.json"):
        try:
            if time.time() - old.stat().st_mtime > 7 * 86400:
                old.unlink()
        except OSError:
            pass


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
