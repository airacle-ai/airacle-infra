#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/appliance-lib.sh
source "$SCRIPT_DIR/appliance-lib.sh"

[ -d "$AIRACLE_APPLIANCES_ROOT" ] || exit 0

find "$AIRACLE_APPLIANCES_ROOT" -maxdepth 2 -name compose.yml -print \
  | sed "s#^$AIRACLE_APPLIANCES_ROOT/##; s#/compose.yml\$##" \
  | sort
