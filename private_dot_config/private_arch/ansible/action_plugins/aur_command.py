"""Forward Ansible's become credential to nested sudo without a password file.

Only used by the trusted packages role, with no_log and a fixed SUDO_PROMPT.
PKGBUILDs continue to run as the normal build user, not as root.
"""
from ansible.plugins.action import ActionBase
from ansible.errors import AnsibleActionFail


class ActionModule(ActionBase):
    TRANSFERS_FILES = False

    def run(self, tmp=None, task_vars=None):
        result = super().run(tmp, task_vars)
        args = dict(self._task.args)
        if set(args) - {'command', 'chdir'} or not args.get('command'):
            raise AnsibleActionFail('aur_command requires command and optional chdir only')
        if not self._task.no_log:
            raise AnsibleActionFail('aur_command must be invoked with no_log: true')
        if self._task.check_mode:
            result.update(skipped=True, changed=False, msg='AUR builds are skipped in check mode')
            return result

        # CLI -K credentials are not ordinary inventory variables. Ask the
        # configured become plugin, which also handles inventory/vault values.
        password = self.get_become_option('become_pass') or self._play_context.become_pass
        try:
            if password:
                args.update(
                    responses={r'\[arch-ansible-aur-sudo\] password:': password},
                    echo=False,
                    timeout=None,
                )
                result.update(self._execute_module(
                    module_name='ansible.builtin.expect', module_args=args,
                    task_vars=task_vars,
                ))
            else:
                # Passwordless sudo remains supported without inventing a secret.
                args['_raw_params'] = args.pop('command')
                result.update(self._execute_module(
                    module_name='ansible.builtin.command', module_args=args,
                    task_vars=task_vars,
                ))
        finally:
            # Ansible normally removes its remote module files; retain that
            # lifecycle explicitly for this custom action, even on failure.
            self._remove_tmp_path(self._connection._shell.tmpdir)
        result['_ansible_no_log'] = True
        return result
