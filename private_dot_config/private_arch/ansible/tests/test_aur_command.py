#!/usr/bin/env python3
"""Check credential routing/redaction without invoking real sudo or builds."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

from ansible.errors import AnsibleActionFail
from ansible.plugins.action import ActionBase

spec = importlib.util.spec_from_file_location(
    'aur_command', Path(__file__).resolve().parents[1] / 'action_plugins/aur_command.py')
plugin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugin)


class AurCommandTests(unittest.TestCase):
    def setUp(self):
        self.base = patch.object(ActionBase, 'run', return_value={})
        self.base.start()
        self.addCleanup(self.base.stop)
        self.action = plugin.ActionModule.__new__(plugin.ActionModule)
        self.action._task = SimpleNamespace(
            args={'command': 'yay -S --needed example', 'chdir': '/tmp'},
            no_log=True, check_mode=False)
        self.action._play_context = SimpleNamespace(become_pass='synthetic-password')
        self.action._connection = SimpleNamespace(_shell=SimpleNamespace(tmpdir='/tmp/mock-module'))
        self.action.get_become_option = Mock(return_value=None)
        self.action._execute_module = Mock(return_value={'rc': 0, 'changed': True})
        self.action._remove_tmp_path = Mock()

    def test_cli_password_is_sent_only_as_hidden_response(self):
        result = self.action.run(task_vars={})
        call = self.action._execute_module.call_args.kwargs
        self.assertEqual(call['module_name'], 'ansible.builtin.expect')
        self.assertEqual(call['module_args']['responses'],
                         {r'\[arch-ansible-aur-sudo\] password:': 'synthetic-password'})
        self.assertFalse(call['module_args']['echo'])
        self.assertNotIn('synthetic-password', call['module_args']['command'])
        self.assertTrue(result['_ansible_no_log'])
        self.action._remove_tmp_path.assert_called_once_with('/tmp/mock-module')

    def test_inventory_credential_takes_precedence(self):
        self.action.get_become_option.return_value = 'inventory-password'
        self.action.run(task_vars={})
        responses = self.action._execute_module.call_args.kwargs['module_args']['responses']
        self.assertEqual(list(responses.values()), ['inventory-password'])

    def test_passwordless_path(self):
        self.action._play_context.become_pass = None
        self.action.run(task_vars={})
        call = self.action._execute_module.call_args.kwargs
        self.assertEqual(call['module_name'], 'ansible.builtin.command')
        self.assertNotIn('responses', call['module_args'])

    def test_requires_redaction(self):
        self.action._task.no_log = False
        with self.assertRaises(AnsibleActionFail):
            self.action.run(task_vars={})
        self.action._execute_module.assert_not_called()

    def test_check_mode_cannot_build(self):
        self.action._task.check_mode = True
        self.assertTrue(self.action.run(task_vars={})['skipped'])
        self.action._execute_module.assert_not_called()

    def test_failure_is_preserved_and_cleanup_runs(self):
        self.action._execute_module.return_value = {'rc': 1, 'failed': True}
        result = self.action.run(task_vars={})
        self.assertTrue(result['failed'])
        self.assertEqual(result['rc'], 1)
        self.assertTrue(result['_ansible_no_log'])
        self.action._remove_tmp_path.assert_called_once()


if __name__ == '__main__':
    unittest.main()
