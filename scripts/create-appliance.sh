#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/appliance-lib.sh
source "$SCRIPT_DIR/appliance-lib.sh"

usage() {
  echo "usage: $0 <template-name> <appliance-name>" >&2
  echo "example: $0 marketing-employee acme-marketing" >&2
}

[ "$#" -eq 2 ] || { usage; exit 1; }

template_name="$1"
appliance_name="$2"
template_dir="$REPO_ROOT/templates/$template_name"
target_dir="$(appliance_dir "$appliance_name")"

[ -d "$template_dir" ] || die "template not found: $template_dir"
[ ! -e "$target_dir" ] || die "target already exists: $target_dir"

mkdir -p "$AIRACLE_APPLIANCES_ROOT"
cp -R "$template_dir" "$target_dir"

if [ -f "$target_dir/.env.example" ]; then
  cp "$target_dir/.env.example" "$target_dir/appliance.env"
fi

mkdir -p \
  "$target_dir/config/prompts" \
  "$target_dir/config/sop" \
  "$target_dir/data/exports" \
  "$target_dir/data/openclaw" \
  "$target_dir/data/redis" \
  "$target_dir/data/video-cache" \
  "$target_dir/identity/claude" \
  "$target_dir/identity/codex" \
  "$target_dir/identity/omnara" \
  "$target_dir/identity/gh" \
  "$target_dir/workspace/inbox" \
  "$target_dir/workspace/brand-assets" \
  "$target_dir/workspace/projects" \
  "$target_dir/workspace/deliverables" \
  "$target_dir/workspace/content-calendar" \
  "$target_dir/workspace/community/comments" \
  "$target_dir/workspace/community/messages" \
  "$target_dir/workspace/ads/variants"

touch "$target_dir/identity/claude.json"

if command -v perl >/dev/null 2>&1; then
  perl -0pi -e "s/AIRACLE_APPLIANCE_NAME=.*/AIRACLE_APPLIANCE_NAME=$appliance_name/" "$target_dir/appliance.env"
fi

echo "created appliance: $target_dir"
echo "next:"
echo "  edit $target_dir/appliance.env"
echo "  $SCRIPT_DIR/start-appliance.sh $appliance_name"
