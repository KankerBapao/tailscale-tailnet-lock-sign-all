#!/usr/bin/env bash
set -euo pipefail

require() { command -v "$1" >/dev/null || { echo "$1 is required" >&2; exit 1; }; }
require tailscale
require jq || true

dedup() { awk '!seen[$0]++'; }

collect_from_lock_json() {
  tailscale lock status --json 2>/dev/null | jq -r '
    [
      .lockedOut[]?.nodeKey,
      .LockedOut[]?.NodeKey,
      .locked_out[]?.node_key,
      .nodes[]? | select(.lockedOut==true or .locked_out==true) | .nodeKey // .NodeKey
    ]
    | map(select(. != null))
    | .[]
  ' 2>/dev/null || true
}

collect_from_lock_text() {
  tailscale lock status 2>/dev/null \
    | grep -Eo 'nodekey:[0-9a-f]+' \
    | sed 's/[[:space:]]//g' || true
}

node_keys=$(
  { collect_from_lock_json; collect_from_lock_text; } | dedup
)

if [ -z "${node_keys}" ]; then
  echo "No nodes require signing."
  exit 0
fi

echo "Signing nodes..."
echo "${node_keys}" | while IFS= read -r key; do
  [ -z "$key" ] && continue
  echo "→ tailscale lock sign ${key}"
  if ! tailscale lock sign "${key}"; then
    echo "  ! Failed to sign ${key}" >&2
  fi
done

echo
echo "Verification:"
tailscale lock status || true

echo
echo "Still locked out (if any):"
{ collect_from_lock_json; collect_from_lock_text; } | dedup | sed 's/^/ - /' || true

echo "Done."
