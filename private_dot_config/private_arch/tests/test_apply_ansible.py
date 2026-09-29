#!/usr/bin/env python3
"""Test launcher authentication and argument handling without running sudo."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        (self.root / 'ansible').mkdir()
        source = Path(__file__).resolve().parents[1] / 'apply-ansible.sh'
        if not source.exists():
            source = source.with_name('executable_apply-ansible.sh')
        self.launcher = self.root / 'apply-ansible.sh'
        shutil.copyfile(source, self.launcher)
        self.capture = self.root / 'capture.json'
        for name, content in {
            'ansible-playbook': '''#!/usr/bin/python3
import json, os, sys
from pathlib import Path
Path(os.environ['CAPTURE']).write_text(json.dumps({'args': sys.argv[1:], 'cwd': os.getcwd()}))
sys.exit(int(os.environ.get('MOCK_EXIT', '0')))
''',
            'sudo': '#!/bin/sh\necho "Unexpected sudo invocation" >&2\nexit 99\n',
        }.items():
            path = self.bin / name
            path.write_text(content)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        CAPTURE=str(self.capture), ARCH_ANSIBLE_ASK_BECOME_PASS='1')

    def invoke(self, *args):
        return subprocess.run(['/bin/bash', str(self.launcher), *args], env=self.env,
                              text=True, capture_output=True, timeout=5)

    def forwarded(self):
        data = json.loads(self.capture.read_text())
        self.assertEqual(data['cwd'], str(self.root / 'ansible'))
        self.assertEqual(data['args'][:3],
                         ['-i', str(self.root / 'ansible/inventory/hosts.yml'), 'site.yml'])
        return data['args'][3:]

    def test_default_prompt_and_exact_arguments(self):
        args = ['--limit', 'rivest', '--tags', 'packages', '-e', 'literal=$HOME two words', '']
        result = self.invoke(*args)
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = ([] if os.geteuid() == 0 else ['--ask-become-pass']) + args
        self.assertEqual(self.forwarded(), expected)

    def test_explicit_credentials(self):
        for args in [('-K',), ('--ask-become-pass',), ('--become-password-file', '/fake/password'),
                     ('--become-password-file=/fake/password',), ('--become-pass-file=/fake/password',)]:
            with self.subTest(args=args):
                self.assertEqual(self.invoke(*args).returncode, 0)
                self.assertEqual(self.forwarded(), list(args))

    def test_inspection_does_not_prompt(self):
        for flag in ['--syntax-check', '--list-hosts', '--list-tasks', '--list-tags', '--help', '-h', '--version']:
            with self.subTest(flag=flag):
                self.assertEqual(self.invoke(flag).returncode, 0)
                self.assertEqual(self.forwarded(), [flag])

    def test_opt_out_and_exit_status(self):
        self.env.update(ARCH_ANSIBLE_ASK_BECOME_PASS='0', MOCK_EXIT='37')
        self.assertEqual(self.invoke('--limit', 'dembe').returncode, 37)
        self.assertEqual(self.forwarded(), ['--limit', 'dembe'])

    def test_invalid_option(self):
        self.env['ARCH_ANSIBLE_ASK_BECOME_PASS'] = 'invalid'
        self.assertEqual(self.invoke().returncode, 2)
        self.assertFalse(self.capture.exists())


if __name__ == '__main__':
    unittest.main()
