#!/usr/bin/env python3
"""Exercise the real wrapper with fake external commands; no desktop memory load."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'private_dot_local/bin/executable_codex'


class WrapperTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.capture = self.root / 'capture.json'
        self.env = dict(os.environ, CAPTURE=str(self.capture), SENTINEL='preserved')
        self.cgroup = self.root / 'cgroup'
        self.cgroup.write_text('0::/user.slice/app.slice/terminal.scope\n')
        self.manager = self.script('manager', '''#!/bin/sh
printf '%s\\n' LoadState=loaded MemoryAccounting=yes MemoryHigh=3221225472 MemoryMax=4294967296 MemorySwapMax=1073741824
''')
        self.runner = self.script('runner', '''#!/usr/bin/python3
import os, sys
expected = ['--user', '--scope', '--quiet', '--collect', '--slice=app-codex.slice', '--expand-environment=no', '--']
assert sys.argv[1:8] == expected, sys.argv
os.execv(sys.argv[8], sys.argv[8:])
''')
        self.binary = self.script('binary', '''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
Path(os.environ['CAPTURE']).write_text(json.dumps({'args':sys.argv[1:], 'cwd':os.getcwd(), 'env':os.environ['SENTINEL']}))
sys.stdout.write(sys.stdin.read())
sys.stderr.write('child stderr\\n')
sys.exit(int(os.environ.get('CHILD_EXIT', '0')))
''')
        source = SOURCE.read_text()
        for old, new in [('/proc/self/cgroup', self.cgroup), ('/usr/bin/systemctl', self.manager),
                         ('/usr/bin/systemd-run', self.runner), ('/usr/bin/codex', self.binary)]:
            source = source.replace(old, str(new))
        self.wrapper = self.script('wrapper', source)

    def script(self, name, contents):
        path = self.root / name
        path.write_text(contents)
        path.chmod(0o755)
        return path

    def run_wrapper(self, args=()):
        return subprocess.run([str(self.wrapper), *args], cwd=self.root, env=self.env,
                              input='piped input\n', text=True, capture_output=True, timeout=10)

    def test_arguments_and_execution_context(self):
        args = ['exec', '--model', 'example', '', 'two words', '$HOME', '$(false)',
                '"quoted"', "it's literal", '*', '--', 'line\nbreak']
        result = self.run_wrapper(args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.capture.read_text()),
                         {'args': args, 'cwd': str(self.root), 'env': 'preserved'})
        self.assertEqual(result.stdout, 'piped input\n')
        self.assertEqual(result.stderr, 'child stderr\n')

    def test_exit_status(self):
        self.env['CHILD_EXIT'] = '37'
        self.assertEqual(self.run_wrapper().returncode, 37)

    def test_nested_invocation_needs_no_manager(self):
        self.manager.write_text('#!/bin/sh\nexit 99\n')
        for suffix in ['', '/run-example.scope', '/run-example.scope/sandbox']:
            self.cgroup.write_text('0::/user.slice/app.slice/app-codex.slice' + suffix + '\n')
            self.assertEqual(self.run_wrapper(['--version']).returncode, 0)

    def test_unavailable_manager_fails_closed(self):
        self.manager.write_text('#!/bin/sh\nexit 99\n')
        result = self.run_wrapper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('cannot reach the user manager', result.stderr)
        self.assertFalse(self.capture.exists())

    def test_missing_or_wrong_limits_fail_closed(self):
        original = self.manager.read_text()
        for field in ['LoadState=loaded', 'MemoryAccounting=yes', 'MemoryHigh=3221225472',
                      'MemoryMax=4294967296', 'MemorySwapMax=1073741824']:
            self.manager.write_text(original.replace(field, field.split('=')[0] + '=infinity'))
            result = self.run_wrapper()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('lacks the expected', result.stderr)
            self.assertFalse(self.capture.exists())

    def test_similar_slice_name_does_not_bypass_check(self):
        self.cgroup.write_text('0::/app-codex.slice-other/run.scope\n')
        self.manager.write_text('#!/bin/sh\nexit 99\n')
        self.assertNotEqual(self.run_wrapper().returncode, 0)


if __name__ == '__main__':
    unittest.main()
