#!/usr/bin/env python3
"""Destructive-boundary regression tests; never opens a physical block device."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import sys
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
[wifi]
ssid=dummy
mac-address=AA:BB:CC:DD:EE:FF
[wifi-security]
key-mgmt=wpa-psk
psk=dummy-not-a-real-secret
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

    def test_completed_resume_does_nothing(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory); (state/'complete').touch()
            with patch.object(installer, 'STATE', state), patch.object(installer, 'require_fedora'), patch.object(installer, 'run') as run:
                installer.provision(); run.assert_not_called()

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
