#!/usr/bin/env python3
"""Format Berg's two clocks without changing process or system timezone."""

import argparse
from datetime import datetime, timezone
import json
import locale
import math
from pathlib import Path
import sys
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

WARSAW = "Europe/Warsaw"
LOCATION_MAX_AGE = 3600


def valid_timezone(value):
    if not isinstance(value, str) or not value or value.startswith(("posix/", "right/")):
        return False
    try:
        ZoneInfo(value)
    except (ValueError, ZoneInfoNotFoundError):
        return False
    return True


def valid_location(value):
    if not isinstance(value, dict):
        return False
    updated = value.get("updated_at")
    return (
        valid_timezone(value.get("timezone"))
        and isinstance(updated, (int, float))
        and not isinstance(updated, bool)
        and math.isfinite(updated)
        and updated >= 0
        and value.get("source") in ("ipapi.co", "ip-api.com")
    )


def clock_fields(instant, zone):
    local = instant.astimezone(ZoneInfo(zone))
    return {
        "timezone": zone,
        "year": local.year,
        "month": local.month,
        "day": local.day,
        "isoDate": local.strftime("%Y-%m-%d"),
        "shortDate": local.strftime("%d.%m"),
        "barDate": local.strftime("%a %-d %b"),
        "time": local.strftime("%H:%M"),
        "fullDate": local.strftime("%A, %-d %B %Y"),
        "full": local.strftime("%A, %-d %B · %H:%M"),
        "compact": local.strftime("%d.%m %H:%M"),
    }


def format_clock(epoch, zone):
    instant = datetime.fromtimestamp(epoch, timezone.utc)
    return {
        "epoch": epoch,
        "local": clock_fields(instant, zone),
        "warsaw": clock_fields(instant, WARSAW),
    }


def snapshot(epoch, location_path, fallback=None):
    try:
        candidate = json.loads(Path(location_path).read_text())
    except (OSError, ValueError):
        candidate = None

    # A damaged cache must not displace the last successfully read location.
    candidate_ok = valid_location(candidate) and candidate["updated_at"] <= epoch
    previous_ok = valid_location(fallback)
    location = candidate if candidate_ok else fallback if previous_ok else None
    zone = location["timezone"] if location else WARSAW
    result = format_clock(epoch, zone)
    result["location"] = location
    result["locationStatus"] = (
        "unavailable" if location is None else
        "fresh" if candidate_ok and 0 <= epoch - location["updated_at"] < LOCATION_MAX_AGE else
        "stale"
    )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate-timezone")
    parser.add_argument("--epoch", type=float)
    parser.add_argument("--timezone")
    parser.add_argument("--location-cache", type=Path)
    parser.add_argument("--fallback-location", default="null")
    args = parser.parse_args()
    if args.validate_timezone is not None:
        return 0 if valid_timezone(args.validate_timezone) else 1
    if args.epoch is None or not math.isfinite(args.epoch):
        parser.error("a finite --epoch is required")
    if args.timezone is None and args.location_cache is None:
        parser.error("--timezone or --location-cache is required")
    try:
        locale.setlocale(locale.LC_TIME, "")
        result = (format_clock(args.epoch, args.timezone) if args.timezone else
                  snapshot(args.epoch, args.location_cache, json.loads(args.fallback_location)))
        print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    except (OSError, ValueError, OverflowError, ZoneInfoNotFoundError) as error:
        print(f"Clock formatting failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
