#!/usr/bin/env python3
"""Destructive-boundary regression tests; never opens a physical block device."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import sys
import shutil
import tarfile
import io
import unittest
from unittest.mock import patch

import common

def load_managed(name):
    root = Path(__file__).resolve().parent
    path = root / (name + '.py')
    if not path.exists():
        path = root / ('executable_' + name + '.py')
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


installer = load_managed('installer')
migration = load_managed('migration')

WIFI = """[connection]
id=dummy
uuid=11111111-1111-1111-1111-111111111111
type=wifi
interface-name=wlan0
permissions=user:vitorpy:;
[wifi]
ssid=dummy
mac-address=AA:BB:CC:DD:EE:FF
[wifi-security]
key-mgmt=wpa-psk
psk=dummy-not-a-real-secret
psk-flags=1
[ipv4]
method=auto
[ipv6]
method=auto
"""


class SafetyTests(unittest.TestCase):
    def manifest(self):
        return dict(schema=1, user='vitorpy', uid=1000, target=common.TARGET, usb=common.USB,
                    source_snapshot='a'*64, usb_snapshot='b'*64, payload_sha256='c'*64,
                    partition_fingerprint='d'*64, independent_recovery_confirmed=True)

    def disk(self):
        return dict(common.TARGET, type='disk', name='/dev/nvme0n1', tran='nvme', children=[])

    def test_disk_identity_requires_all_fields(self):
        self.assertEqual(common.match_disk([self.disk()], common.TARGET)['name'], '/dev/nvme0n1')
        for key, bad in [('serial','decoy'), ('model','decoy'), ('size',1234), ('tran','usb')]:
            disk = self.disk(); disk[key] = bad
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                common.match_disk([disk], common.TARGET)

    def test_duplicate_disk_is_rejected(self):
        with self.assertRaises(RuntimeError):
            common.match_disk([self.disk(), self.disk()], common.TARGET)

    def test_partition_changes_reject_accidental_reinstallation(self):
        disk = self.disk(); original = common.partition_fingerprint(disk)
        disk['children'] = [dict(size=1000, uuid='fedora-new', partuuid='new')]
        self.assertNotEqual(original, common.partition_fingerprint(disk))

    def test_manifest_must_pin_backup_and_confirm_recovery(self):
        common.validate_manifest(self.manifest())
        for key, bad in [('source_snapshot','latest'), ('usb_snapshot','abc123'), ('uid',1001),
                         ('schema',2), ('target',{}), ('independent_recovery_confirmed',False)]:
            manifest = self.manifest(); manifest[key] = bad
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                common.validate_manifest(manifest)

    def test_wifi_keeps_secret_and_ip_settings_without_interface_binding(self):
        profile, uuid = common.prepare_wifi(WIFI)
        self.assertNotIn('interface-name', profile)
        self.assertNotIn('mac-address=', profile)
        self.assertNotIn('permissions=', profile)
        self.assertIn('psk-flags=0', profile)
        self.assertIn('psk=dummy-not-a-real-secret', profile)
        self.assertIn('method=auto', profile)
        self.assertIn('autoconnect=true', profile)

    def test_missing_or_enterprise_wifi_fails_closed(self):
        for text in [WIFI.replace('psk=dummy-not-a-real-secret',''), WIFI.replace('wpa-psk','wpa-eap')]:
            with self.assertRaises(RuntimeError): common.prepare_wifi(text)

    def test_wrong_bundle_and_corrupt_payload_never_generate_partitioning(self):
        with tempfile.TemporaryDirectory() as directory:
            ram = Path(directory)
            with patch.object(installer, 'RAM', ram), patch.object(installer, 'require_fedora'), \
                 patch.object(installer.Path, 'read_text', return_value='inst.ks=cdrom:test'), \
                 patch.object(installer.Path, 'is_dir', return_value=True), patch.object(installer, 'run'), \
                 patch.object(installer, 'media_mount', return_value=ram), \
                 patch.object(installer, 'unlock', side_effect=RuntimeError('invalid')):
                with self.assertRaises(RuntimeError): installer.pre(ram)
            self.assertFalse((ram/'confirmed.ks').exists())

    def test_resume_has_no_partitioning_path(self):
        with patch.object(installer, 'STATE', Path('/definitely-missing-migration-state')), \
             patch.object(installer, 'require_fedora'), patch.object(installer, 'pre') as pre:
            with self.assertRaises(RuntimeError): installer.provision()
            pre.assert_not_called()

    def test_each_failed_precondition_leaves_partitioning_unwritten(self):
        for failure in ('wifi', 'repository', 'disk', 'layout', 'confirmation'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as directory:
                ram = Path(directory)
                with patch.object(installer, 'RAM', ram), patch.object(installer, 'require_fedora'), \
                     patch.object(installer.Path, 'read_text', return_value='inst.ks=cdrom:test'), \
                     patch.object(installer.Path, 'is_dir', return_value=True), patch.object(installer, 'run'), \
                     patch.object(installer, 'media_mount', return_value=ram), \
                     patch.object(installer, 'unlock', return_value=(self.manifest(), {})), \
                     patch.object(installer, 'wifi_connect', side_effect=RuntimeError('wifi') if failure=='wifi' else None), \
                     patch.object(installer, 'verify_repository', side_effect=RuntimeError('repo') if failure=='repository' else None), \
                     patch.object(installer, 'disk_inventory', return_value=[]), \
                     patch.object(installer, 'match_disk', side_effect=RuntimeError('disk') if failure=='disk' else None, return_value=self.disk()), \
                     patch.object(installer, 'partition_fingerprint', return_value='e'*64 if failure=='layout' else 'd'*64), \
                     patch('builtins.input', return_value='wrong serial'):
                    with self.assertRaises(RuntimeError): installer.pre(ram)
                self.assertFalse((ram/'confirmed.ks').exists())

    def test_home_merge_retry_does_not_reactivate_arch_services(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); staging=root/'stage'; target=root/'target'; payload=root/'payload'
            source=staging/common.HOME.lstrip('/'); source.mkdir(parents=True)
            units=source/'.config/systemd/user/graphical-session.target.wants'; units.mkdir(parents=True)
            (units/'rclone.service').symlink_to('../rclone.service')
            (source/'.config/systemd/user/rclone.service').write_text('arch-only')
            payload.mkdir(); target.mkdir()
            with tarfile.open(payload/'home-public.tar','w') as archive:
                member=tarfile.TarInfo('.config/systemd/user/quickshell-berg.service')
                member.size=6; member.mode=0o644
                archive.addfile(member,io.BytesIO(b'public'))
            def copy_home(args):
                shutil.copytree(source,target/common.HOME.lstrip('/'),dirs_exist_ok=True,symlinks=True)
            with patch.object(installer,'run',side_effect=lambda args: copy_home(args) if args[0]=='rsync' else None), patch.object(installer.os,'chown') as chown:
                for _ in range(2):
                    installer.merge_home(staging,target,payload)
                    home=target/common.HOME.lstrip('/')
                    self.assertFalse((home/'.config/systemd/user/graphical-session.target.wants').exists())
                    self.assertEqual((home/'.config/systemd/user/quickshell-berg.service').read_text(),'public')
                    self.assertTrue((home/'.local/state/fedora-migration/arch-session-reference/.config/systemd/user/rclone.service').exists())
                    self.assertIn(((home/'.config/systemd/user',1000,1000),), [(c.args,) for c in chown.call_args_list])

    def test_completed_resume_does_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory); (state/'complete').touch()
            with patch.object(installer, 'STATE', state), patch.object(installer, 'require_fedora'), patch.object(installer, 'run') as run:
                installer.provision(); run.assert_not_called()

    def test_native_profiles_move_to_flatpak_without_overwriting_prior_flatpak_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); original=root/'original'; home=root/'home'
            native=original/'.config/Bitwarden'; native.mkdir(parents=True)
            (native/'data.json').write_text('dummy encrypted account data')
            (native/'SingletonLock').symlink_to('old-host-123')
            native_discord=original/'.config/discord'; native_discord.mkdir(parents=True)
            (native_discord/'settings.json').write_text('old-native')
            old_flatpak=original/'.var/app/com.discordapp.Discord/config/discord'; old_flatpak.mkdir(parents=True)
            (old_flatpak/'settings.json').write_text('prior-flatpak')
            shutil.copytree(original,home,symlinks=True)
            with patch.object(installer.os,'chown'):
                installer.migrate_flatpak_profiles(original,home)
                restored=home/'.var/app/com.bitwarden.desktop/config/Bitwarden'
                self.assertEqual((restored/'data.json').read_text(),'dummy encrypted account data')
                self.assertFalse((restored/'SingletonLock').is_symlink())
                (restored/'data.json').write_text('partial retry')
                installer.migrate_flatpak_profiles(original,home)
                self.assertEqual((restored/'data.json').read_text(),'dummy encrypted account data')
                self.assertEqual((home/'.var/app/com.discordapp.Discord/config/discord/settings.json').read_text(),'prior-flatpak')
                self.assertEqual((native/'data.json').read_text(),'dummy encrypted account data')

    def test_private_outputs_are_not_world_readable(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'secret'
            common.write_private(path, 'dummy')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            path.unlink(); path.symlink_to(Path(directory)/'other')
            with self.assertRaises(OSError): common.write_private(path, 'dummy')

    def test_corrupted_public_payload_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root/'controller').write_text('public')
            migration.hashes(root); common.check_files(root)
            (root/'controller').write_text('corrupt')
            with self.assertRaises(RuntimeError): common.check_files(root)


if __name__ == '__main__':
    unittest.main()
