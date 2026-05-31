#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/appliance-lib.sh
source "$SCRIPT_DIR/appliance-lib.sh"

[ "$#" -ge 1 ] || { usage_name "$0"; exit 1; }

name="$1"
shift || true
dir="$(require_appliance "$name")"
compose="$(compose_cmd)"

cd "$dir"
$compose --env-file appliance.env -f compose.yml up -d "$@"
