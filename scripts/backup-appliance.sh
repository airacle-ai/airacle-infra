#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/appliance-lib.sh
source "$SCRIPT_DIR/appliance-lib.sh"

AIRACLE_BACKUP_ROOT="${AIRACLE_BACKUP_ROOT:-/srv/airacle/backups}"

[ "$#" -eq 1 ] || { usage_name "$0"; exit 1; }

name="$1"
dir="$(require_appliance "$name")"
timestamp="$(date +%Y%m%d-%H%M%S)"
archive="$AIRACLE_BACKUP_ROOT/$name-$timestamp.tar.gz"

mkdir -p "$AIRACLE_BACKUP_ROOT"
tar -C "$(dirname "$dir")" -czf "$archive" "$(basename "$dir")"

echo "backup written: $archive"
