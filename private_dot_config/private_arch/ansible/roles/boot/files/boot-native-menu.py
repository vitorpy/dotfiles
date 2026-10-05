#!/usr/bin/env python3
"""Retire only known UKI aliases after read-only boot checks; retain both UKIs."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess

ESP = Path('/boot')
EFIVARS = Path('/sys/firmware/efi/efivars')
GUID = '4a67b082-0a4c-41cf-b6c7-440b29bb8c4f'
NORMAL = 'arch-linux.efi'
FALLBACK = 'arch-linux-fallback.efi'
ALIASES = {'arch.conf': NORMAL, 'arch-fallback.conf': FALLBACK,
           'arch-pre-pcr.conf': NORMAL, 'arch-linux-pre-pcr.efi': NORMAL}
WRAPPERS = {'arch.conf': NORMAL, 'arch-fallback.conf': FALLBACK,
            'arch-pre-pcr.conf': 'arch-linux-pre-pcr.efi'}


def run(*args):
    return subprocess.check_output(args, text=True, env={**os.environ, 'LC_ALL': 'C',
                                                        'SYSTEMD_COLORS': '0'}).strip()


def entries():
    return set(re.findall(r'^\s*id:\s*(\S+)\s*$', run('bootctl', 'list', '--no-pager'), re.M))


def efi_value(name):
    path = EFIVARS / f'{name}-{GUID}'
    if not path.exists():
        return ''
    return path.read_bytes()[4:].decode('utf-16-le').rstrip('\0')


def loader_config(text):
    lines = [line for line in text.splitlines() if not re.match(r'^\s*default\s+', line)]
    return f'default {NORMAL}\n' + '\n'.join(lines) + '\n'


def validate_wrapper(path, image):
    # Only delete the plain efi/title wrappers produced by this role.
    if path.is_symlink():
        raise ValueError(f'Refusing symlink: {path}')
    if not path.exists():
        return
    directives = [line.split(None, 1) for line in path.read_text().splitlines()
                  if line.strip() and not line.lstrip().startswith('#')]
    if (any(len(row) != 2 or row[0] not in ('title', 'efi') for row in directives)
            or [row[1] for row in directives if row[0] == 'efi'] != [f'/EFI/Linux/{image}']):
        raise ValueError(f'Customized loader entry needs review: {path}')


def cleanup(uuid, check=False):
    if run('findmnt', '--noheadings', '--output', 'UUID', '--mountpoint', str(ESP)) != uuid:
        raise ValueError('Unexpected mounted ESP UUID')
    if Path(run('bootctl', '--print-stub-path')).name != NORMAL:
        raise ValueError('Boot the managed normal UKI before retiring recovery entries')
    for service in ('systemd-pcrphase-initrd.service', 'systemd-pcrproduct.service'):
        state = dict(line.split('=', 1) for line in run('systemctl', 'show', service,
                     '-p', 'Result', '-p', 'ExecMainStatus', '-p', 'ExecMainStartTimestampMonotonic').splitlines())
        if (state.get('Result') != 'success' or state.get('ExecMainStatus') != '0'
                or int(state.get('ExecMainStartTimestampMonotonic', '0')) <= 0):
            raise ValueError(f'Current boot lacks successful PCR measurements: {service}')
    for image in (NORMAL, FALLBACK):
        path = ESP / 'EFI/Linux' / image
        if path.is_symlink() or not path.is_file() or not path.stat().st_size:
            raise ValueError(f'Missing or invalid retained UKI: {path}')
        if run('bootctl', 'kernel-identify', str(path)) != 'uki':
            raise ValueError(f'Not a UKI: {path}')
        report = json.loads(run('sbctl', 'verify', '--json', str(path)))
        if not any(row.get('file_name') == str(path) and row.get('is_signed') == 1 for row in report):
            raise ValueError(f'Invalid Secure Boot signature: {path}')
    if not {NORMAL, FALLBACK} <= entries():
        raise ValueError('Both native UKI entries must be discoverable before cleanup')
    for name, image in WRAPPERS.items():
        validate_wrapper(ESP / 'loader/entries' / name, image)
    retire = [ESP / 'loader/entries' / name for name in WRAPPERS]
    retire.append(ESP / 'EFI/Linux/arch-linux-pre-pcr.efi')
    for path in retire:
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise ValueError(f'Refusing unexpected removal target: {path}')
    loader = ESP / 'loader/loader.conf'
    if loader.is_symlink():
        raise ValueError('Refusing symlink loader.conf')
    original = loader.read_text()
    desired = loader_config(original)
    selections = [('LoaderEntryDefault', 'set-default', NORMAL)]
    for variable, command in (('LoaderEntryOneShot', 'set-oneshot'), ('LoaderEntrySysFail', 'set-sysfail')):
        current = efi_value(variable)
        if current in ALIASES:
            selections.append((variable, command, ALIASES[current]))
        elif current and current not in {NORMAL, FALLBACK, 'auto-reboot-to-firmware-setup'}:
            raise ValueError(f'Review custom {variable} selection before cleanup: {current}')
    changes = [(variable, command, value) for variable, command, value in selections
               if efi_value(variable) != value]
    removals = [path for path in retire if path.exists()]
    changed = bool(changes or removals or desired != original)
    if not check:
        # Set and verify a valid persistent selection before removing any aliases.
        for variable, command, value in changes:
            run('bootctl', command, value)
            if efi_value(variable) != value:
                raise ValueError(f'EFI selection did not persist: {variable}')
        if desired != original:
            temporary = loader.with_name('loader.conf.native-menu.tmp')
            with temporary.open('x') as stream:
                stream.write(desired)
                stream.flush()
                os.fsync(stream.fileno())
            temporary.replace(loader)
        for path in removals:
            path.unlink()
        remaining = entries()
        if not {NORMAL, FALLBACK} <= remaining or set(ALIASES) & remaining:
            raise ValueError('Boot menu post-validation failed')
        if efi_value('LoaderEntryDefault') != NORMAL or loader.read_text() != desired:
            raise ValueError('Native default post-validation failed')
    return {'changed': changed, 'check': check, 'retired': [str(p) for p in removals],
            'default': NORMAL, 'retained': [NORMAL, FALLBACK],
            'recovery_archive': '/var/lib/arch-boot/pre-pcr'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--esp-uuid', required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run through the privileged Ansible boot-menu recipe')
    print(json.dumps(cleanup(args.esp_uuid, args.check)))


if __name__ == '__main__':
    main()
