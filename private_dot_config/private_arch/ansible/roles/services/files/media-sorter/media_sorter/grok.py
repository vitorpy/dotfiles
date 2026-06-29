from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_XAI_RESPONSES_URL = "https://api.x.ai/v1/responses"


def grok_fixture_review(fixture_path: str, record: dict[str, Any]) -> dict[str, Any]:
    fixture = json.loads(Path(fixture_path).read_text(encoding="utf-8"))
    key = record.get("download_key") or record.get("torrent", {}).get("name") or "default"
    return fixture.get(str(key)) or fixture.get("default") or {"decision": "approve", "reason": "fixture default approval", "concerns": [], "confidence": 1.0}


def grok_prompt_payload(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "download_key": record.get("download_key"),
        "torrent": record.get("torrent"),
        "match": record.get("match"),
        "reason": record.get("reason"),
        "plan": record.get("plan"),
        "preflight": record.get("preflight"),
    }


def normalize_grok_review(body: dict[str, Any]) -> dict[str, Any]:
    decision = str(body.get("decision") or "").strip().lower()
    reason = str(body.get("reason") or "").strip()
    concerns = body.get("concerns")
    confidence = body.get("confidence")

    if decision not in {"approve", "reject"}:
        raise RuntimeError(f"invalid Grok decision: {decision!r}")
    if not reason:
        raise RuntimeError("Grok review is missing reason")
    if concerns is None:
        concerns = []
    if not isinstance(concerns, list):
        concerns = [str(concerns)]
    try:
        confidence_value = float(confidence)
    except (TypeError, ValueError):
        confidence_value = 0.0

    return {
        "provider": "xai",
        "model": body.get("model"),
        "decision": decision,
        "approved": decision == "approve",
        "reason": reason,
        "concerns": [str(item) for item in concerns],
        "confidence": confidence_value,
    }


def extract_response_text(body: dict[str, Any]) -> str:
    output_text = body.get("output_text")
    if isinstance(output_text, str):
        return output_text

    texts: list[str] = []
    for item in body.get("output") or []:
        if not isinstance(item, dict):
            continue
        for content in item.get("content") or []:
            if isinstance(content, dict) and isinstance(content.get("text"), str):
                texts.append(content["text"])
    return "\n".join(texts).strip()


def review_plan_with_grok(record: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    if args.xai_fixture_json:
        review = normalize_grok_review(grok_fixture_review(args.xai_fixture_json, record))
        review["provider"] = "fixture"
        return review

    api_key = args.xai_api_key or os.environ.get("XAI_API_KEY")
    if not api_key:
        raise RuntimeError("XAI_API_KEY is not set")

    payload = {
        "model": args.xai_model,
        "store": False,
        "input": [
            {
                "role": "system",
                "content": (
                    "You review Jellyfin media sorter hardlink plans. "
                    "Approve only if the metadata match and destination layout look coherent. "
                    "Reject if the plan appears to misclassify media, put episodes in wrong seasons, "
                    "mix unrelated titles, or create suspicious duplicate paths. "
                    "Return only compact JSON with keys: decision, reason, concerns, confidence."
                ),
            },
            {"role": "user", "content": json.dumps(grok_prompt_payload(record), ensure_ascii=False, sort_keys=True)},
        ],
    }
    request = urllib.request.Request(
        args.xai_responses_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=args.xai_timeout) as response:
            response_body = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Grok review request failed: {exc}") from exc

    text = extract_response_text(response_body)
    if not text:
        raise RuntimeError("Grok review response did not contain output_text")
    try:
        review_body = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Grok review returned malformed JSON: {exc}") from exc
    review = normalize_grok_review(review_body)
    review["model"] = args.xai_model
    return review
