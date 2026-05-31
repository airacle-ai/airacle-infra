#!/usr/bin/env bash
set -euo pipefail

AIRACLE_APPLIANCES_ROOT="${AIRACLE_APPLIANCES_ROOT:-/srv/airacle/appliances}"

die() {
  echo "error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    die "missing docker compose or docker-compose"
  fi
}

appliance_dir() {
  local name="${1:?appliance name required}"
  echo "$AIRACLE_APPLIANCES_ROOT/$name"
}

require_appliance() {
  local name="${1:?appliance name required}"
  local dir
  dir="$(appliance_dir "$name")"
  [ -d "$dir" ] || die "appliance not found: $dir"
  [ -f "$dir/compose.yml" ] || die "missing compose.yml in $dir"
  [ -f "$dir/appliance.env" ] || die "missing appliance.env in $dir"
  echo "$dir"
}

usage_name() {
  local script="$1"
  echo "usage: $script <appliance-name>" >&2
}
