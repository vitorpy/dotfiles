#!/usr/bin/env python3
"""Compare selected locally restored files with their originals, without printing contents."""
import argparse
import hashlib
import os
from pathlib import Path
import stat

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('restore_root', type=Path)
parser.add_argument('paths', nargs='+', type=Path)
args = parser.parse_args()

def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

for original in args.paths:
    if not original.is_absolute():
        parser.error('Original paths must be absolute')
    restored = args.restore_root / original.relative_to('/')
    source = original.lstat(); target = restored.lstat()
    if stat.S_IFMT(source.st_mode) != stat.S_IFMT(target.st_mode):
        raise SystemExit('Restored file type differs')
    if stat.S_IMODE(source.st_mode) != stat.S_IMODE(target.st_mode):
        raise SystemExit('Restored permissions differ')
    if source.st_uid != target.st_uid or source.st_gid != target.st_gid:
        raise SystemExit('Restored ownership differs')
    if stat.S_ISLNK(source.st_mode):
        if os.readlink(original) != os.readlink(restored):
            raise SystemExit('Restored symlink differs')
    elif stat.S_ISREG(source.st_mode) and digest(original) != digest(restored):
        raise SystemExit('Restored content differs')
    for attr in os.listxattr(original, follow_symlinks=False):
        if attr.startswith('user.') and os.getxattr(original, attr, follow_symlinks=False) != os.getxattr(restored, attr, follow_symlinks=False):
            raise SystemExit('Restored user extended attribute differs')
print(f'Verified content, permissions, ownership, links, and user xattrs for {len(args.paths)} restored paths')
