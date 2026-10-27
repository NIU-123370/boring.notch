import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / 'scripts/agent-status/install_claude_hooks.py'
HOOK = ROOT / 'scripts/agent-status/claude_hook.py'

class HookTests(unittest.TestCase):
    def test_install_and_events(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            original = {'enabledPlugins': {'keep': True}, 'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'echo keep'}]}]}}
            (root / 'settings.json').write_text(json.dumps(original))
            for _ in range(2):
                subprocess.run([sys.executable, str(INSTALLER), '--claude-home', temp], check=True, capture_output=True)
            settings = json.loads((root / 'settings.json').read_text())
            self.assertEqual(settings['enabledPlugins'], original['enabledPlugins'])
            self.assertEqual(len(settings['hooks']['Stop']), 2)
            self.assertEqual(settings['hooks']['Stop'][0], original['hooks']['Stop'][0])
            hook = root / 'hooks/boring_notch_status.py'
            for kind, expected in [('UserPromptSubmit', 'running'), ('PermissionRequest', 'waiting'), ('PostToolUse', 'running'), ('Stop', 'completed'), ('StopFailure', 'failed'), ('SessionEnd', 'idle')]:
                event = {'session_id': '../unsafe/name', 'hook_event_name': kind, 'cwd': '/tmp/project', 'prompt': 'SECRET', 'tool_input': {'command': 'SECRET'}}
                output = subprocess.run([sys.executable, str(hook)], input=json.dumps(event), capture_output=True, text=True, check=True)
                self.assertEqual(output.stdout, '', 'hook must never return permission decisions')
                files = list((root / 'boring-notch-events').glob('*.json'))
                self.assertEqual(len(files), 1)
                self.assertNotIn('SECRET', files[0].read_text())
                self.assertEqual(json.loads(files[0].read_text())['state'], expected)
            output = subprocess.run([sys.executable, str(hook)], input='bad json', capture_output=True, text=True)
            self.assertEqual(output.returncode, 0, 'malformed hook input must not block Claude')

if __name__ == '__main__':
    unittest.main()
