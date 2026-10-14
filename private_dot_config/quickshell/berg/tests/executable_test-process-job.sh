#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
cp "$script_dir/../ProcessJob.qml" "$fixture/ProcessJob.qml"
cp "$script_dir/runtime/process-job.qml" "$fixture/shell.qml"
timeout 15 qs -p "$fixture"
