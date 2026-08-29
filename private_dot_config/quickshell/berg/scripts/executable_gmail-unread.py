#!/usr/bin/env python3
"""Fetch Gmail unread label counts without reading message metadata or content."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
from typing import Any, Callable
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


GMAIL_SCOPE = "https://www.googleapis.com/auth/gmail.labels"
GMAIL_API = "https://gmail.googleapis.com/gmail/v1/users/me"
COUNT_FIELDS = frozenset({"threadsUnread", "messagesUnread"})


class GmailUnreadError(RuntimeError):
    """A user-actionable configuration, authentication, or API failure."""


def default_config_path() -> Path:
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "gmail-unread" / "config.json"


def expand_path(value: Any, field: str) -> Path:
    if not isinstance(value, str) or not value.strip():
        raise GmailUnreadError(f"{field} must be a non-empty path")
    return Path(os.path.expandvars(value)).expanduser()


def require_private_file(path: Path, field: str) -> None:
    try:
        metadata = path.stat()
    except OSError as exc:
        raise GmailUnreadError(f"cannot read {field} {path}: {exc.strerror or exc}") from exc
    if not stat.S_ISREG(metadata.st_mode):
        raise GmailUnreadError(f"{field} is not a regular file: {path}")
    if metadata.st_mode & 0o077:
        raise GmailUnreadError(f"{field} must not be accessible by group or others: chmod 600 {path}")


def parse_label(raw: Any, account_name: str) -> dict[str, str]:
    if isinstance(raw, str):
        label_id = raw.strip()
        label_name = label_id
    elif isinstance(raw, dict):
        label_id = raw.get("id", "")
        label_name = raw.get("name", label_id)
        if not isinstance(label_id, str) or not isinstance(label_name, str):
            raise GmailUnreadError(f"labels for {account_name} require string id and name values")
        label_id = label_id.strip()
        label_name = label_name.strip()
    else:
        raise GmailUnreadError(f"labels for {account_name} must be strings or objects")

    if not label_id or not label_name:
        raise GmailUnreadError(f"labels for {account_name} require non-empty id and name values")
    return {"id": label_id, "name": label_name}


def load_config(path: Path, require_caches: bool = True) -> dict[str, Any] | None:
    if not path.exists():
        return None
    require_private_file(path, "configuration")

    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise GmailUnreadError(f"cannot parse configuration {path}: {exc}") from exc
    if not isinstance(raw, dict):
        raise GmailUnreadError("configuration must be a JSON object")

    count_field = raw.get("countField", "threadsUnread")
    if count_field not in COUNT_FIELDS:
        raise GmailUnreadError("countField must be threadsUnread or messagesUnread")

    oauth2l = expand_path(raw.get("oauth2l", "/usr/bin/oauth2l"), "oauth2l")
    if not oauth2l.is_file() or not os.access(oauth2l, os.X_OK):
        raise GmailUnreadError(f"oauth2l is not executable: {oauth2l}")

    default_credentials = raw.get("credentials")
    raw_accounts = raw.get("accounts")
    if not isinstance(raw_accounts, list) or not raw_accounts:
        raise GmailUnreadError("accounts must be a non-empty array")

    accounts: list[dict[str, Any]] = []
    names: set[str] = set()
    cache_paths: set[Path] = set()
    for index, raw_account in enumerate(raw_accounts):
        if not isinstance(raw_account, dict):
            raise GmailUnreadError(f"accounts[{index}] must be an object")

        name = raw_account.get("name", "")
        if not isinstance(name, str) or not name.strip():
            raise GmailUnreadError(f"accounts[{index}].name must be a non-empty string")
        name = name.strip()
        if name in names:
            raise GmailUnreadError(f"account name is duplicated: {name}")
        names.add(name)

        credentials = expand_path(
            raw_account.get("credentials", default_credentials),
            f"credentials for {name}",
        )
        require_private_file(credentials, f"credentials for {name}")

        cache = expand_path(raw_account.get("cache"), f"cache for {name}")
        normalized_cache = cache.resolve(strict=False)
        if normalized_cache in cache_paths:
            raise GmailUnreadError(f"OAuth cache is shared by multiple accounts: {cache}")
        cache_paths.add(normalized_cache)
        if require_caches:
            require_private_file(cache, f"OAuth cache for {name}")

        raw_labels = raw_account.get("labels")
        if not isinstance(raw_labels, list) or not raw_labels:
            raise GmailUnreadError(f"labels for {name} must be a non-empty array")
        labels = [parse_label(label, name) for label in raw_labels]
        label_ids = [label["id"] for label in labels]
        if len(label_ids) != len(set(label_ids)):
            raise GmailUnreadError(f"label IDs for {name} must be unique")

        accounts.append(
            {
                "name": name,
                "credentials": credentials,
                "cache": cache,
                "labels": labels,
            }
        )

    return {
        "countField": count_field,
        "oauth2l": oauth2l,
        "accounts": accounts,
    }


def fetch_access_token(oauth2l: Path, account: dict[str, Any]) -> str:
    command = [
        str(oauth2l),
        "fetch",
        "--credentials",
        str(account["credentials"]),
        "--cache",
        str(account["cache"]),
        "--scope",
        GMAIL_SCOPE,
        "--refresh",
    ]
    try:
        result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise GmailUnreadError(f"OAuth failed for {account['name']}: {exc}") from exc
    token = result.stdout.strip()
    if result.returncode != 0 or not token:
        detail = result.stderr.strip() or f"oauth2l exited with status {result.returncode}"
        raise GmailUnreadError(f"OAuth failed for {account['name']}: {detail}")
    return token


def api_json(token: str, url: str) -> dict[str, Any]:
    request = Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urlopen(request, timeout=10) as response:
            value = json.load(response)
    except HTTPError as exc:
        raise GmailUnreadError(f"Gmail API returned HTTP {exc.code} {exc.reason}") from exc
    except (URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
        raise GmailUnreadError(f"Gmail API request failed: {exc}") from exc
    if not isinstance(value, dict):
        raise GmailUnreadError("Gmail API returned a non-object response")
    return value


def fetch_label_count(token: str, label_id: str, count_field: str) -> int:
    encoded_id = quote(label_id, safe="")
    value = api_json(token, f"{GMAIL_API}/labels/{encoded_id}?fields={count_field}")
    count = value.get(count_field, 0)
    if not isinstance(count, int) or isinstance(count, bool) or count < 0:
        raise GmailUnreadError(f"Gmail API returned an invalid {count_field} value for {label_id}")
    return count


def collect_counts(
    config: dict[str, Any],
    token_fetcher: Callable[[Path, dict[str, Any]], str] = fetch_access_token,
    label_fetcher: Callable[[str, str, str], int] = fetch_label_count,
) -> dict[str, Any]:
    account_results: list[dict[str, Any]] = []
    total = 0
    for account in config["accounts"]:
        token = token_fetcher(config["oauth2l"], account)
        label_results = []
        account_total = 0
        for label in account["labels"]:
            unread = label_fetcher(token, label["id"], config["countField"])
            label_results.append({"id": label["id"], "name": label["name"], "unread": unread})
            account_total += unread
        account_results.append(
            {"name": account["name"], "total": account_total, "labels": label_results}
        )
        total += account_total

    return {
        "configured": True,
        "countField": config["countField"],
        "total": total,
        "accounts": account_results,
    }


def authorize(config: dict[str, Any], account_name: str) -> None:
    account = next((item for item in config["accounts"] if item["name"] == account_name), None)
    if account is None:
        available = ", ".join(item["name"] for item in config["accounts"])
        raise GmailUnreadError(f"unknown account {account_name!r}; configured accounts: {available}")

    cache_parent = account["cache"].parent
    cache_parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    cache_parent.chmod(0o700)
    if account["cache"].exists():
        require_private_file(account["cache"], f"OAuth cache for {account_name}")
    fetch_access_token(config["oauth2l"], account)
    account["cache"].chmod(0o600)
    require_private_file(account["cache"], f"OAuth cache for {account_name}")
    print(f"Authorized {account_name}; token cache: {account['cache']}")


def list_labels(config: dict[str, Any], account_name: str) -> None:
    account = next((item for item in config["accounts"] if item["name"] == account_name), None)
    if account is None:
        available = ", ".join(item["name"] for item in config["accounts"])
        raise GmailUnreadError(f"unknown account {account_name!r}; configured accounts: {available}")
    require_private_file(account["cache"], f"OAuth cache for {account_name}")
    token = fetch_access_token(config["oauth2l"], account)
    value = api_json(token, f"{GMAIL_API}/labels?fields=labels(id,name,type)")
    labels = value.get("labels", [])
    if not isinstance(labels, list):
        raise GmailUnreadError("Gmail API returned an invalid labels list")
    for label in sorted(labels, key=lambda item: str(item.get("name", "")).casefold()):
        print(f"{label.get('id', '')}\t{label.get('name', '')}\t{label.get('type', '')}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=default_config_path())
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status", help="print the aggregate unread status as JSON")
    subparsers.add_parser("validate", help="validate configuration and existing token caches")
    authorize_parser = subparsers.add_parser("authorize", help="run interactive OAuth for one account")
    authorize_parser.add_argument("account")
    labels_parser = subparsers.add_parser("labels", help="list Gmail label IDs for one account")
    labels_parser.add_argument("account")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command in {"authorize", "labels"}:
            config = load_config(args.config, require_caches=False)
        else:
            config = load_config(args.config, require_caches=True)

        if config is None:
            if args.command == "status":
                print(json.dumps({"configured": False}, separators=(",", ":")))
                return 0
            raise GmailUnreadError(f"configuration does not exist: {args.config}")

        if args.command == "status":
            print(json.dumps(collect_counts(config), separators=(",", ":")))
        elif args.command == "validate":
            print(f"Configuration valid: {len(config['accounts'])} account(s)")
        elif args.command == "authorize":
            authorize(config, args.account)
        elif args.command == "labels":
            list_labels(config, args.account)
        return 0
    except GmailUnreadError as exc:
        print(f"gmail-unread: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
