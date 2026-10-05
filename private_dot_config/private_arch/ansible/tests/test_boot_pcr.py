"""Regression tests for key reuse, PCR metadata, recovery immutability and scope."""

import base64
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from jinja2 import Environment, StrictUndefined
import yaml

ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'roles/boot/files' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


check = load('boot-pcr-check')
recovery = load('boot-pcr-recovery')


class PCRTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.key = key
        cls.private = key.private_bytes(serialization.Encoding.PEM,
                                       serialization.PrivateFormat.PKCS8,
                                       serialization.NoEncryption())
        cls.public = key.public_key().public_bytes(serialization.Encoding.PEM,
                                                   serialization.PublicFormat.SubjectPublicKeyInfo)
        cls.other_public = rsa.generate_private_key(public_exponent=65537, key_size=2048).public_key().public_bytes(
            serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.priv = self.root / 'private.pem'
        self.pub = self.root / 'public.pem'

    def sections(self):
        entry = {'pcrs': [11], 'ref': 'initrd',
                 'pkfp': hashlib.sha256(self.key.public_key().public_bytes(
                     serialization.Encoding.DER, serialization.PublicFormat.PKCS1)).hexdigest(),
                 'pol': 'ab' * 32, 'sig': base64.b64encode(self.key.sign(
                     bytes.fromhex('ab' * 32) + hashlib.sha256(b'initrd').digest(),
                     padding.PKCS1v15(), hashes.SHA256())).decode()}
        return {'.pcrpkey': {'text': self.public.decode()},
                '.pcrsig': {'text': json.dumps({'sha256': [entry]})}}

    def test_absent_pair_can_be_created(self):
        self.assertEqual(check.check_pair(self.priv, self.pub), {'exists': False})

    def test_valid_pair_is_reused_without_changes(self):
        self.priv.write_bytes(self.private)
        self.pub.write_bytes(self.public)
        before = (self.priv.stat().st_mtime_ns, self.pub.stat().st_mtime_ns)
        self.assertTrue(check.check_pair(self.priv, self.pub)['exists'])
        self.assertEqual(before, (self.priv.stat().st_mtime_ns, self.pub.stat().st_mtime_ns))

    def test_incomplete_pairs_fail(self):
        for private_exists in (True, False):
            with self.subTest(private_exists=private_exists):
                path = self.priv if private_exists else self.pub
                path.write_bytes(self.private if private_exists else self.public)
                with self.assertRaisesRegex(ValueError, 'Incomplete'):
                    check.check_pair(self.priv, self.pub)
                path.unlink()

    def test_mismatched_pair_fails_without_replacement(self):
        self.priv.write_bytes(self.private)
        self.pub.write_bytes(self.other_public)
        with self.assertRaisesRegex(ValueError, 'do not match'):
            check.check_pair(self.priv, self.pub)
        self.assertEqual(self.pub.read_bytes(), self.other_public)

    def test_key_symlinks_fail(self):
        self.priv.symlink_to(self.root / 'missing')
        with self.assertRaisesRegex(ValueError, 'symlinks'):
            check.check_pair(self.priv, self.pub)

    def test_complete_metadata_passes(self):
        self.assertTrue(check.check_sections(self.sections(), self.public)['valid'])

    def test_missing_sections_request_rebuild(self):
        for section in ('.pcrpkey', '.pcrsig'):
            sections = self.sections()
            del sections[section]
            self.assertFalse(check.check_sections(sections, self.public)['valid'])

    def test_wrong_key_requests_rebuild(self):
        self.assertFalse(check.check_sections(self.sections(), self.other_public)['valid'])

    def test_wrong_policy_reference_bank_pcr_or_fingerprint_requests_rebuild(self):
        for field, wrong in [('ref', None), ('pcrs', [7]), ('pkfp', '00' * 32)]:
            sections = self.sections()
            data = json.loads(sections['.pcrsig']['text'])
            data['sha256'][0][field] = wrong
            sections['.pcrsig']['text'] = json.dumps(data)
            self.assertFalse(check.check_sections(sections, self.public)['valid'])
        sections['.pcrsig']['text'] = json.dumps({'sha1': data['sha256']})
        self.assertFalse(check.check_sections(sections, self.public)['valid'])

    def test_malformed_metadata_stops_instead_of_requesting_rebuild(self):
        sections = self.sections()
        sections['.pcrsig']['text'] = '{broken'
        with self.assertRaises(json.JSONDecodeError):
            check.check_sections(sections, self.public)

    def test_invalid_signature_stops(self):
        sections = self.sections()
        data = json.loads(sections['.pcrsig']['text'])
        data['sha256'][0]['pol'] = 'cd' * 32
        sections['.pcrsig']['text'] = json.dumps(data)
        with self.assertRaises(InvalidSignature):
            check.check_sections(sections, self.public)

    def test_absent_uki_requests_rebuild(self):
        self.assertFalse(check.check_uki(self.root / 'missing.efi', self.pub)['valid'])

    def test_ukify_failure_is_not_hidden(self):
        self.pub.write_bytes(self.public)
        image = self.root / 'image.efi'
        image.write_bytes(b'invalid')
        with patch.object(check.subprocess, 'check_output', side_effect=RuntimeError('ukify failed')):
            with self.assertRaisesRegex(RuntimeError, 'ukify failed'):
                check.check_uki(str(image), str(self.pub))

    def test_snapshot_is_immutable_and_tracks_absence(self):
        original = self.root / 'original.efi'
        original.write_bytes(b'signed-working-image')
        optional = self.root / 'uki.conf'
        backup = self.root / 'backup'
        manifest, changed = recovery.snapshot([original, optional], optional, backup)
        self.assertTrue(changed)
        self.assertIsNone(manifest[str(optional)])
        original.write_bytes(b'new-image')
        optional.write_text('new-config')
        again, changed = recovery.snapshot([original, optional], optional, backup)
        self.assertFalse(changed)
        self.assertEqual(again, manifest)
        saved = backup / 'files' / str(original).lstrip('/')
        self.assertEqual(saved.read_bytes(), b'signed-working-image')
        saved.write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            recovery.snapshot([original, optional], optional, backup)

    def test_rescue_copy_is_idempotent_and_refuses_collision(self):
        original, target = self.root / 'old', self.root / 'rescue'
        original.write_bytes(b'old')
        expected = recovery.digest(original)
        self.assertTrue(recovery.copy_once(original, target, expected))
        self.assertFalse(recovery.copy_once(original, target, expected))
        target.write_bytes(b'unrelated')
        with self.assertRaisesRegex(ValueError, 'differs'):
            recovery.copy_once(original, target, expected)
        self.assertEqual(target.read_bytes(), b'unrelated')

    def test_unsigned_sbctl_result_fails_even_with_exit_zero(self):
        with patch.object(recovery.subprocess, 'check_output', return_value='[{"file_name":"/image","is_signed":0}]'):
            with self.assertRaisesRegex(ValueError, 'signature verification failed'):
                recovery.verify_signed('/image')

    def test_scoped_package_declaration(self):
        all_vars = yaml.safe_load((ROOT / 'group_vars/all.yml').read_text())
        host_vars = yaml.safe_load((ROOT / 'host_vars/zygalski.yml').read_text())
        self.assertFalse(all_vars['arch_uki_pcr_signing_enabled'])
        self.assertTrue(host_vars['arch_uki_pcr_signing_enabled'])
        task = yaml.safe_load((ROOT / 'roles/packages/tasks/main.yml').read_text())[0]
        env = Environment(undefined=StrictUndefined)
        env.filters['bool'] = bool
        expression = task['ansible.builtin.set_fact']['packages_pacman_effective']
        for boot, pcr, expected in [(True, True, True), (True, False, False), (False, True, False), (False, False, False)]:
            resolved = list(env.compile_expression(expression.strip()[2:-2].strip())(arch_pacman_packages=['linux'],
                arch_host_pacman_packages_extra=[], arch_boot_enabled=boot,
                arch_uki_pcr_signing_enabled=pcr, arch_aur_packages=[], arch_host_aur_packages_extra=[]))
            self.assertEqual('systemd-ukify' in resolved, expected)
        resolved = list(env.compile_expression(expression.strip()[2:-2].strip())(
            arch_pacman_packages=['linux'], arch_host_pacman_packages_extra=[],
            arch_boot_enabled=True, arch_uki_pcr_signing_enabled=True,
            arch_aur_packages=['example'], arch_host_aur_packages_extra=[]))
        self.assertIn('python-pexpect', resolved)
        self.assertIn('systemd-ukify', resolved)

    def test_rebuild_triggers_include_pcr_changes(self):
        tasks = yaml.safe_load((ROOT / 'roles/boot/tasks/pcr-prepare.yml').read_text())
        expression = tasks[-1]['ansible.builtin.set_fact']['boot_pcr_regenerate']
        env = Environment(undefined=StrictUndefined)
        env.filters['from_json'] = json.loads
        base = dict(boot_pcr_tool_install={'changed': False}, boot_pcr_config={'changed': False},
                    boot_pcr_key_generation={'changed': False}, boot_pcr_tool={'stat': {'exists': True}},
                    boot_pcr_existing={'results': [{'stdout': '{"valid":true}'}] * 2})
        self.assertEqual(env.from_string(expression).render(**base), 'False')
        for name in ('boot_pcr_tool_install', 'boot_pcr_config', 'boot_pcr_key_generation'):
            values = copy.deepcopy(base)
            values[name]['changed'] = True
            self.assertEqual(env.from_string(expression).render(**values), 'True')
        values = copy.deepcopy(base)
        values['boot_pcr_existing']['results'][0] = {'stdout': '{"valid":false}'}
        self.assertEqual(env.from_string(expression).render(**values), 'True')

        # First check-mode run: ukify and key generation do not exist yet.
        values = copy.deepcopy(base)
        del values['boot_pcr_key_generation']
        del values['boot_pcr_existing']
        values['boot_pcr_tool']['stat']['exists'] = False
        self.assertEqual(env.from_string(expression).render(**values), 'True')


if __name__ == '__main__':
    unittest.main()
