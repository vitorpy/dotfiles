from __future__ import annotations

import errno
import os
from pathlib import Path

from .utils import log


def link_file(source: Path, dest: Path, dry_run: bool, required: bool = True) -> bool:
    level = "ERROR" if required else "WARNING"
    if not source.exists():
        log("WARNING", f"source missing, skipping source={source}")
        return True

    if dest.exists():
        try:
            if os.path.samefile(source, dest):
                log("INFO", f"already linked source={source} dest={dest}")
                return True
        except OSError:
            pass
        log("WARNING", f"destination conflict, skipping source={source} dest={dest}")
        return True

    if dry_run:
        log("INFO", f"would hardlink source={source} dest={dest}")
        return True

    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(source, dest)
    except OSError as exc:
        if exc.errno == errno.EXDEV:
            log(level, f"cross-filesystem hardlink failed, not copying source={source} dest={dest}")
        else:
            log(level, f"hardlink failed errno={exc.errno} source={source} dest={dest}: {exc}")
        return not required

    log("INFO", f"hardlinked source={source} dest={dest}")
    return True
