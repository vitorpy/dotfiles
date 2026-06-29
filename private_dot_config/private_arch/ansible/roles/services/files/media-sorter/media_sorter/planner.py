from __future__ import annotations

import errno
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .utils import log


@dataclass(frozen=True)
class LinkOperation:
    source: Path
    dest: Path
    kind: str
    required: bool = True
    reason: str | None = None


@dataclass
class SortPlan:
    label_kind: str
    label_title: str
    torrent_name: str
    operations: list[LinkOperation] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def add(self, source: Path, dest: Path, kind: str, required: bool = True, reason: str | None = None) -> None:
        self.operations.append(LinkOperation(source=source, dest=dest, kind=kind, required=required, reason=reason))


@dataclass
class PreflightResult:
    ok: bool
    reasons: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    skipped_optional: set[int] = field(default_factory=set)


def path_dict(path: Path) -> str:
    return str(path)


def operation_to_record(operation: LinkOperation, skipped: bool = False) -> dict[str, Any]:
    return {
        "source": path_dict(operation.source),
        "dest": path_dict(operation.dest),
        "kind": operation.kind,
        "required": operation.required,
        "reason": operation.reason,
        "skipped": skipped,
    }


def plan_to_record(plan: SortPlan, preflight: PreflightResult | None = None) -> dict[str, Any]:
    skipped = preflight.skipped_optional if preflight else set()
    return {
        "label_kind": plan.label_kind,
        "label_title": plan.label_title,
        "torrent_name": plan.torrent_name,
        "errors": plan.errors,
        "warnings": plan.warnings,
        "operations": [operation_to_record(operation, index in skipped) for index, operation in enumerate(plan.operations)],
    }


def preflight_to_record(preflight: PreflightResult) -> dict[str, Any]:
    return {
        "ok": preflight.ok,
        "reasons": preflight.reasons,
        "warnings": preflight.warnings,
        "skipped_optional": sorted(preflight.skipped_optional),
    }


def first_existing_parent(path: Path) -> Path | None:
    current = path if path.exists() else path.parent
    while True:
        if current.exists():
            return current
        if current.parent == current:
            return None
        current = current.parent


def is_under(path: Path, root: Path) -> bool:
    try:
        path.resolve(strict=False).relative_to(root.resolve(strict=False))
        return True
    except ValueError:
        return False


def preflight_plan(plan: SortPlan, allowed_roots: list[Path]) -> PreflightResult:
    result = PreflightResult(ok=True, reasons=list(plan.errors), warnings=list(plan.warnings))
    seen_destinations: dict[Path, int] = {}
    root_devices: dict[Path, int] = {}

    for root in allowed_roots:
        if root.exists():
            try:
                root_devices[root.resolve(strict=False)] = root.stat().st_dev
            except OSError as exc:
                result.reasons.append(f"cannot stat library root={root}: {exc}")

    for index, operation in enumerate(plan.operations):
        if operation.dest in seen_destinations:
            previous = seen_destinations[operation.dest]
            result.reasons.append(f"duplicate destination in plan dest={operation.dest} previous_index={previous} index={index}")
            continue
        seen_destinations[operation.dest] = index

        matching_roots = [root for root in allowed_roots if is_under(operation.dest, root)]
        if not matching_roots:
            result.reasons.append(f"destination is outside managed library roots dest={operation.dest}")
            continue

        if not operation.source.exists():
            message = f"source missing source={operation.source}"
            if operation.required:
                result.reasons.append(message)
            else:
                result.warnings.append(message)
                result.skipped_optional.add(index)
            continue

        destination_root = matching_roots[0].resolve(strict=False)
        destination_device = root_devices.get(destination_root)
        if destination_device is not None:
            try:
                source_device = operation.source.stat().st_dev
            except OSError as exc:
                result.reasons.append(f"cannot stat source={operation.source}: {exc}")
                continue
            if source_device != destination_device:
                result.reasons.append(f"cross-filesystem hardlink would fail source={operation.source} dest={operation.dest}")
                continue

        if operation.dest.exists():
            try:
                if os.path.samefile(operation.source, operation.dest):
                    continue
            except OSError:
                pass
            message = f"destination conflict source={operation.source} dest={operation.dest}"
            if operation.required:
                result.reasons.append(message)
            else:
                result.warnings.append(message)
                result.skipped_optional.add(index)

    result.ok = not result.reasons
    return result


def apply_plan(plan: SortPlan, preflight: PreflightResult, dry_run: bool = False) -> tuple[bool, list[dict[str, Any]]]:
    ok = True
    owned_links: list[dict[str, Any]] = []
    for index, operation in enumerate(plan.operations):
        if index in preflight.skipped_optional:
            continue

        if operation.dest.exists():
            try:
                if os.path.samefile(operation.source, operation.dest):
                    log("INFO", f"already linked source={operation.source} dest={operation.dest}")
                    owned_links.append(owned_link_record(operation, "already-linked"))
                    continue
            except OSError:
                pass
            log("ERROR" if operation.required else "WARNING", f"destination conflict, skipping source={operation.source} dest={operation.dest}")
            ok = not operation.required and ok
            continue

        if dry_run:
            log("INFO", f"would hardlink source={operation.source} dest={operation.dest}")
            owned_links.append(owned_link_record(operation, "dry-run"))
            continue

        operation.dest.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.link(operation.source, operation.dest)
        except OSError as exc:
            level = "ERROR" if operation.required else "WARNING"
            if exc.errno == errno.EXDEV:
                log(level, f"cross-filesystem hardlink failed, not copying source={operation.source} dest={operation.dest}")
            else:
                log(level, f"hardlink failed errno={exc.errno} source={operation.source} dest={operation.dest}: {exc}")
            ok = not operation.required and ok
            continue

        log("INFO", f"hardlinked source={operation.source} dest={operation.dest}")
        owned_links.append(owned_link_record(operation, "created"))
    return ok, owned_links


def stat_record(path: Path) -> dict[str, Any] | None:
    try:
        stat = path.stat()
    except OSError:
        return None
    return {"device": stat.st_dev, "inode": stat.st_ino, "size": stat.st_size}


def owned_link_record(operation: LinkOperation, status: str) -> dict[str, Any]:
    return {
        "source": path_dict(operation.source),
        "dest": path_dict(operation.dest),
        "kind": operation.kind,
        "required": operation.required,
        "status": status,
        "source_stat": stat_record(operation.source),
        "dest_stat": stat_record(operation.dest),
    }
