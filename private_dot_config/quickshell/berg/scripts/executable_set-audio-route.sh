#!/usr/bin/env bash

set -euo pipefail

if (( $# != 3 )); then
    printf 'usage: %s sink|source NODE_ID NODE_NAME\n' "${0##*/}" >&2
    exit 64
fi

route_kind=$1
node_id=$2
node_name=$3

case "$route_kind" in
    sink|source) ;;
    *)
        printf 'unsupported audio route kind: %s\n' "$route_kind" >&2
        exit 64
        ;;
esac

case "$node_id" in
    ''|*[!0-9]*)
        printf 'invalid PipeWire node id: %s\n' "$node_id" >&2
        exit 64
        ;;
esac

if [[ -z "$node_name" || "$node_name" == *$'\n'* || "$node_name" == *$'\r'* ]]; then
    printf 'invalid PipeWire node name\n' >&2
    exit 64
fi

timeout_bin=${BERG_AUDIO_TIMEOUT_BIN:-/usr/bin/timeout}
wpctl_bin=${BERG_AUDIO_WPCTL_BIN:-/usr/bin/wpctl}
pactl_bin=${BERG_AUDIO_PACTL_BIN:-/usr/bin/pactl}
jq_bin=${BERG_AUDIO_JQ_BIN:-/usr/bin/jq}

"$timeout_bin" 2 "$wpctl_bin" set-default "$node_id"

if [[ "$route_kind" == sink ]]; then
    "$timeout_bin" 2 "$pactl_bin" set-default-sink "$node_name"
    stream_json=$("$timeout_bin" 2 "$pactl_bin" --format=json list sink-inputs)
    while IFS= read -r stream_id; do
        [[ -n "$stream_id" ]] || continue
        # A stream can disappear between listing and moving; that race does not
        # invalidate the selected default route.
        "$timeout_bin" 2 "$pactl_bin" move-sink-input "$stream_id" "$node_name" || true
    done < <(
        "$jq_bin" -r '
            .[]
            | (.properties["application.name"] // "") as $application
            | select($application | length > 0)
            | select($application | ascii_downcase | test("easyeffects|pulseeffects|jamesdsp") | not)
            | .index
        ' <<<"$stream_json"
    )
else
    "$timeout_bin" 2 "$pactl_bin" set-default-source "$node_name"
    stream_json=$("$timeout_bin" 2 "$pactl_bin" --format=json list source-outputs)
    while IFS= read -r stream_id; do
        [[ -n "$stream_id" ]] || continue
        "$timeout_bin" 2 "$pactl_bin" move-source-output "$stream_id" "$node_name" || true
    done < <(
        "$jq_bin" -r '
            .[]
            | select((.properties["application.name"] // "") | length > 0)
            | .index
        ' <<<"$stream_json"
    )
fi
