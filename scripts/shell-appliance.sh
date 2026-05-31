#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/appliance-lib.sh
source "$SCRIPT_DIR/appliance-lib.sh"

usage() {
  echo "usage: $0 <appliance-name> [service]" >&2
  echo "example: $0 acme-marketing agent" >&2
}

[ "$#" -ge 1 ] || { usage; exit 1; }

name="$1"
service="${2:-agent}"
dir="$(require_appliance "$name")"
compose="$(compose_cmd)"

cd "$dir"
$compose --env-file appliance.env -f compose.yml exec "$service" bash
