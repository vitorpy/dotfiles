"""Exercise cleanup against an isolated ESP, including refusal and repeat runs."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import yaml

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'roles/boot/files' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


menu = load('boot-native-menu')
recovery = load('boot-pcr-recovery')


class NativeMenuTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.esp = self.root / 'boot'
        self.efi = self.root / 'efivars'
        self.efi.mkdir()
        for directory in ('EFI/Linux', 'loader/entries', 'loader/credentials'):
            (self.esp / directory).mkdir(parents=True)
        for image in (menu.NORMAL, menu.FALLBACK, 'arch-linux-pre-pcr.efi'):
            (self.esp / 'EFI/Linux' / image).write_text('signed-uki')
        for name, image in menu.WRAPPERS.items():
            (self.esp / 'loader/entries' / name).write_text(f'title Arch Linux\nefi /EFI/Linux/{image}\n')
        (self.esp / 'loader/loader.conf').write_text('default arch.conf\ntimeout 3\neditor no\n')
        (self.esp / 'loader/credentials/anchor.cred').write_text('keep')
        self.commands = []
        self.signed = True
        self.service_ok = True
        self.running = menu.NORMAL
        self.uuid = 'expected'
        self.set_efi('LoaderEntryDefault', 'arch.conf')
        self.set_efi('LoaderEntryOneShot', 'arch-fallback.conf')
        for name, value in (('ESP', self.esp), ('EFIVARS', self.efi), ('run', self.run_command)):
            replacement = patch.object(menu, name, value)
            replacement.start()
            self.addCleanup(replacement.stop)

    def set_efi(self, name, value):
        (self.efi / f'{name}-{menu.GUID}').write_bytes(b'\x07\0\0\0' + (value + '\0').encode('utf-16-le'))

    def run_command(self, *args):
        self.commands.append(args)
        if args[0] == 'findmnt':
            return self.uuid
        if args == ('bootctl', '--print-stub-path'):
            return '/boot/EFI/Linux/' + self.running
        if args[0] == 'systemctl':
            return 'Result=success\nExecMainStatus=0\nExecMainStartTimestampMonotonic=' + ('123' if self.service_ok else '0')
        if args[:2] == ('bootctl', 'kernel-identify'):
            return 'uki'
        if args[0] == 'sbctl':
            return json.dumps([{'file_name': args[-1], 'is_signed': int(self.signed)}])
        if args[:2] == ('bootctl', 'list'):
            paths = list((self.esp / 'EFI/Linux').glob('*.efi')) + list((self.esp / 'loader/entries').glob('*.conf'))
            return '\n'.join(f'        id: {p.name}' for p in paths)
        if args[:2] in (('bootctl', 'set-default'), ('bootctl', 'set-oneshot'), ('bootctl', 'set-sysfail')):
            self.set_efi({'set-default': 'LoaderEntryDefault', 'set-oneshot': 'LoaderEntryOneShot',
                          'set-sysfail': 'LoaderEntrySysFail'}[args[1]], args[2])
            return ''
        self.fail(f'Unexpected command: {args}')

    def snapshot(self):
        return {str(p.relative_to(self.root)): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}

    def test_check_mode_has_no_mutations(self):
        before = self.snapshot()
        self.assertTrue(menu.cleanup('expected', check=True)['changed'])
        self.assertEqual(before, self.snapshot())
        self.assertFalse(any(args[1].startswith('set-') for args in self.commands if args[0] == 'bootctl'))

    def test_cleanup_preserves_images_credentials_and_is_idempotent(self):
        result = menu.cleanup('expected')
        self.assertEqual(len(result['retired']), 4)
        self.assertEqual(menu.efi_value('LoaderEntryDefault'), menu.NORMAL)
        self.assertEqual(menu.efi_value('LoaderEntryOneShot'), menu.FALLBACK)
        for image in (menu.NORMAL, menu.FALLBACK):
            self.assertEqual((self.esp / 'EFI/Linux' / image).read_text(), 'signed-uki')
        self.assertEqual((self.esp / 'loader/credentials/anchor.cred').read_text(), 'keep')
        self.assertEqual((self.esp / 'loader/loader.conf').read_text(), 'default arch-linux.efi\ntimeout 3\neditor no\n')
        before = self.snapshot()
        self.assertFalse(menu.cleanup('expected')['changed'])
        self.assertEqual(before, self.snapshot())

    def test_invalid_boot_signature_service_or_esp_refuses_without_mutation(self):
        for field, value in (('signed', False), ('service_ok', False), ('running', menu.FALLBACK), ('uuid', 'wrong')):
            with self.subTest(field=field):
                old = getattr(self, field)
                setattr(self, field, value)
                before = self.snapshot()
                with self.assertRaises(ValueError):
                    menu.cleanup('expected')
                self.assertEqual(before, self.snapshot())
                setattr(self, field, old)

    def test_custom_entry_refuses_without_mutation(self):
        (self.esp / 'loader/entries/arch.conf').write_text('title Arch\nefi /EFI/Linux/arch-linux.efi\noptions extra\n')
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'Customized'):
            menu.cleanup('expected')
        self.assertEqual(before, self.snapshot())

    def test_symlink_refuses_without_mutation(self):
        rescue = self.esp / 'EFI/Linux/arch-linux-pre-pcr.efi'
        rescue.unlink()
        rescue.symlink_to(self.esp / 'EFI/Linux' / menu.NORMAL)
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'unexpected removal'):
            menu.cleanup('expected')
        self.assertEqual(before, self.snapshot())

    def test_default_failure_keeps_all_entries(self):
        original = menu.run
        def fail_default(*args):
            if args[:2] == ('bootctl', 'set-default'):
                return ''
            return original(*args)
        before = self.snapshot()
        with patch.object(menu, 'run', fail_default):
            with self.assertRaisesRegex(ValueError, 'did not persist'):
                menu.cleanup('expected')
        self.assertEqual(before, self.snapshot())

    def test_archive_only_does_not_recreate_retired_files(self):
        # Exercise the recovery CLI with all absolute paths mapped into the fixture.
        def mapped(path):
            return self.root / str(path).lstrip('/')
        default = '/boot/EFI/Linux/arch-linux.efi'
        fallback = '/boot/EFI/Linux/arch-linux-fallback.efi'
        paths = [default, fallback, '/etc/mkinitcpio.conf', '/etc/mkinitcpio.d/linux.preset',
                 '/etc/kernel/cmdline', '/etc/kernel/uki.conf', '/etc/fstab', '/boot/loader/loader.conf',
                 '/boot/loader/entries/arch.conf', '/boot/loader/entries/arch-fallback.conf',
                 '/boot/EFI/systemd/systemd-bootx64.efi', '/boot/EFI/BOOT/BOOTX64.EFI']
        for path in map(mapped, paths):
            path.parent.mkdir(parents=True, exist_ok=True)
            if not path.exists():
                path.write_text('original')
        recovery.snapshot(list(map(mapped, paths)), mapped('/etc/kernel/uki.conf'), mapped('/var/lib/arch-boot/pre-pcr'))
        for name in menu.WRAPPERS:
            (self.esp / 'loader/entries' / name).unlink()
        (self.esp / 'EFI/Linux/arch-linux-pre-pcr.efi').unlink()
        before = self.snapshot()
        with patch.object(recovery, 'Path', mapped), patch.object(recovery.os, 'geteuid', return_value=0), \
                patch('sys.argv', ['recovery', '--default', default, '--fallback', fallback, '--kernel', 'linux', '--archive-only']), \
                patch('builtins.print') as output:
            # snapshot's digest uses Path too; keep it reading existing fixture paths.
            with patch.object(recovery, 'digest', lambda p: __import__('hashlib').sha256(Path(p).read_bytes()).hexdigest()):
                recovery.main()
            self.assertFalse(json.loads(output.call_args.args[0])['changed'])
        self.assertEqual(before, self.snapshot())

    def test_scope_and_preflight_order(self):
        self.assertFalse(yaml.safe_load((ROOT / 'group_vars/all.yml').read_text())['arch_boot_native_entries'])
        self.assertTrue(yaml.safe_load((ROOT / 'host_vars/zygalski.yml').read_text())['arch_boot_native_entries'])
        tasks = yaml.safe_load((ROOT / 'roles/boot/tasks/native-menu.yml').read_text())
        scripts = [t['ansible.builtin.script']['cmd'] for t in tasks if 'ansible.builtin.script' in t]
        self.assertIn('--archive-only --check', scripts[0])
        self.assertIn('boot-pcr-check.py', scripts[1])
        self.assertIn('boot-native-menu.py', scripts[2])
        self.assertIn("'--check' if ansible_check_mode", scripts[2])


if __name__ == '__main__':
    unittest.main()
