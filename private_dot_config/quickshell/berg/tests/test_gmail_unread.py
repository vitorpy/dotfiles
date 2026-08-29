from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys

import pytest


MODULE_PATH = Path(__file__).parents[1] / "scripts" / "gmail-unread.py"
SPEC = importlib.util.spec_from_file_location("gmail_unread", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
gmail_unread = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = gmail_unread
SPEC.loader.exec_module(gmail_unread)


def private_file(path: Path, contents: str) -> Path:
    path.write_text(contents, encoding="utf-8")
    path.chmod(0o600)
    return path


def config_file(tmp_path: Path, *, count_field: str = "threadsUnread") -> Path:
    oauth2l = private_file(tmp_path / "oauth2l", "fake executable")
    oauth2l.chmod(0o700)
    credentials = private_file(tmp_path / "client.json", "{}")
    personal_cache = private_file(tmp_path / "personal.oauth2l", "{}")
    work_cache = private_file(tmp_path / "work.oauth2l", "{}")
    value = {
        "oauth2l": str(oauth2l),
        "credentials": str(credentials),
        "countField": count_field,
        "accounts": [
            {
                "name": "Personal",
                "cache": str(personal_cache),
                "labels": ["INBOX", {"id": "Label_42", "name": "Receipts"}],
            },
            {
                "name": "Work",
                "cache": str(work_cache),
                "labels": [{"id": "INBOX", "name": "Inbox"}],
            },
        ],
    }
    return private_file(tmp_path / "config.json", json.dumps(value))


def test_missing_config_is_disabled(tmp_path: Path) -> None:
    assert gmail_unread.load_config(tmp_path / "missing.json") is None


def test_loads_multiple_accounts_and_labels(tmp_path: Path) -> None:
    config = gmail_unread.load_config(config_file(tmp_path))
    assert config is not None
    assert [account["name"] for account in config["accounts"]] == ["Personal", "Work"]
    assert config["accounts"][0]["labels"] == [
        {"id": "INBOX", "name": "INBOX"},
        {"id": "Label_42", "name": "Receipts"},
    ]


def test_setup_commands_can_load_before_every_cache_exists(tmp_path: Path) -> None:
    path = config_file(tmp_path)
    value = json.loads(path.read_text(encoding="utf-8"))
    Path(value["accounts"][1]["cache"]).unlink()

    config = gmail_unread.load_config(path, require_caches=False)
    assert config is not None
    with pytest.raises(gmail_unread.GmailUnreadError, match="OAuth cache for Work"):
        gmail_unread.load_config(path, require_caches=True)


def test_collects_configured_field_and_aggregates(tmp_path: Path) -> None:
    config = gmail_unread.load_config(config_file(tmp_path, count_field="messagesUnread"))
    assert config is not None
    tokens = {"Personal": "personal-token", "Work": "work-token"}
    counts = {
        ("personal-token", "INBOX"): 5,
        ("personal-token", "Label_42"): 2,
        ("work-token", "INBOX"): 3,
    }

    result = gmail_unread.collect_counts(
        config,
        token_fetcher=lambda oauth2l, account: tokens[account["name"]],
        label_fetcher=lambda token, label, field: counts[(token, label)],
    )

    assert result["countField"] == "messagesUnread"
    assert result["total"] == 10
    assert result["accounts"][0]["total"] == 7
    assert result["accounts"][1]["labels"][0]["unread"] == 3


def test_rejects_shared_account_cache(tmp_path: Path) -> None:
    path = config_file(tmp_path)
    value = json.loads(path.read_text(encoding="utf-8"))
    value["accounts"][1]["cache"] = value["accounts"][0]["cache"]
    path.write_text(json.dumps(value), encoding="utf-8")

    with pytest.raises(gmail_unread.GmailUnreadError, match="shared by multiple accounts"):
        gmail_unread.load_config(path)


def test_rejects_duplicate_label_ids(tmp_path: Path) -> None:
    path = config_file(tmp_path)
    value = json.loads(path.read_text(encoding="utf-8"))
    value["accounts"][0]["labels"].append("INBOX")
    path.write_text(json.dumps(value), encoding="utf-8")

    with pytest.raises(gmail_unread.GmailUnreadError, match="must be unique"):
        gmail_unread.load_config(path)


def test_rejects_permissive_secret_file(tmp_path: Path) -> None:
    path = config_file(tmp_path)
    value = json.loads(path.read_text(encoding="utf-8"))
    Path(value["credentials"]).chmod(0o644)

    with pytest.raises(gmail_unread.GmailUnreadError, match="chmod 600"):
        gmail_unread.load_config(path)


def test_rejects_unknown_count_field(tmp_path: Path) -> None:
    path = config_file(tmp_path, count_field="totalUnread")
    with pytest.raises(gmail_unread.GmailUnreadError, match="countField"):
        gmail_unread.load_config(path)
