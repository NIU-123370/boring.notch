#!/usr/bin/env python3
"""Install only Boring Notch's hooks, preserving existing Claude settings."""
import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import sys
import tempfile
import time

EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
          "PostToolUse", "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SessionEnd"]


def install(root):
    root.mkdir(parents=True, exist_ok=True)
    settings = root / "settings.json"
    before = settings.read_bytes() if settings.exists() else None
    config = json.loads(before) if before else {}
    hooks = config.setdefault("hooks", {})
    target = root / "hooks" / "boring_notch_status.py"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(Path(__file__).with_name("claude_hook.py"), target)
    target.chmod(0o700)
    command = shlex.quote(sys.executable) + " " + shlex.quote(str(target.resolve()))
    for event in EVENTS:
        groups = hooks.setdefault(event, [])
        # Idempotent update of this installer-owned entry only.
        groups[:] = [g for g in groups if g.get("_boring_notch") is not True]
        # Avoid unknown settings fields: identify our exact script filename.
        for group in groups:
            group["hooks"] = [h for h in group.get("hooks", [])
                              if str(target.resolve()) not in h.get("command", "")]
        groups[:] = [g for g in groups if g.get("hooks")]
        entry = {"hooks": [{"type": "command", "command": command, "timeout": 3}]}
        if event in ("PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure"):
            entry["matcher"] = "*"
        if event == "Notification":
            entry["matcher"] = "permission_prompt"
        groups.append(entry)
    encoded = (json.dumps(config, indent=2, ensure_ascii=False) + "\n").encode()
    if before == encoded:
        print("Claude hooks already configured")
    else:
        if before is not None:
            backup = root / ("settings.before-boring-notch-" + str(time.time_ns()) + ".json")
            backup.write_bytes(before)
            backup.chmod(0o600)
        fd, name = tempfile.mkstemp(prefix=".settings-", dir=root)
        with os.fdopen(fd, "wb") as stream:
            stream.write(encoded)
        # Do not overwrite a concurrent settings change.
        current = settings.read_bytes() if settings.exists() else None
        if current != before:
            os.unlink(name)
            raise RuntimeError("Claude settings changed during installation; retry")
        os.replace(name, settings)
        print("Claude status hooks installed; existing settings preserved")
    events = root / "boring-notch-events"
    events.mkdir(exist_ok=True, mode=0o700)
    (events / "installed").write_text("1\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--claude-home", type=Path, default=Path.home() / ".claude")
    args = parser.parse_args()
    install(args.claude_home)
