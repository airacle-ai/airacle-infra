#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  omnara-cleanup-offline.sh
#  列出 Omnara 后端的所有机器，可选删除所有 OFFLINE 的
#
#  用法：
#    ./omnara-cleanup-offline.sh           # 仅列出，不删
#    ./omnara-cleanup-offline.sh --yes     # 直接删除所有 OFFLINE 的
#    ./omnara-cleanup-offline.sh --dry-run # 显示将要删除什么但不执行
#
#  PAT 来源（按顺序找，第一个有的就用）：
#    1. $OMNARA_PAT 环境变量
#    2. ~/.omnara/creds.json 的 .pat 字段（宿主机本地登录过）
#    3. 任意运行中 airacle-* 容器里的 /root/.omnara/creds.json
# ─────────────────────────────────────────────────────────────

set -euo pipefail

API_BASE="https://api.omnara.com/api/v1"

mode="list"
case "${1:-}" in
  --yes|-y)        mode="delete" ;;
  --dry-run|-n)    mode="dry-run" ;;
  --help|-h)       sed -n '2,17p' "$0"; exit 0 ;;
  "")              mode="list" ;;
  *) echo "Unknown arg: $1 (try --help)" >&2; exit 2 ;;
esac

# ── 找 PAT ──
get_pat() {
  if [ -n "${OMNARA_PAT:-}" ]; then
    echo "$OMNARA_PAT"; return
  fi
  if [ -f "$HOME/.omnara/creds.json" ]; then
    python3 -c "import json; print(json.load(open('$HOME/.omnara/creds.json'))['pat'])" 2>/dev/null && return
  fi
  # 从任意 airacle-* 容器里捞
  for ct in $(docker ps --format '{{.Names}}' 2>/dev/null | grep -E '^airacle' || true); do
    pat=$(docker exec "$ct" cat /root/.omnara/creds.json 2>/dev/null \
            | python3 -c "import json,sys; print(json.load(sys.stdin)['pat'])" 2>/dev/null) || continue
    if [ -n "$pat" ]; then
      echo "$pat"; return
    fi
  done
  echo "ERROR: 找不到 Omnara PAT。设 OMNARA_PAT 或在宿主机/容器里登录后重试。" >&2
  exit 1
}

PAT=$(get_pat)

# ── 列出 ──
list_json=$(curl -sSf -H "Authorization: Bearer $PAT" "$API_BASE/machines")

python3 - <<PY
import json, sys
d = json.loads("""$list_json""")
print(f"{'STATUS':<10} {'NAME':<28} ID")
print("-"*70)
for m in d["machines"]:
    print(f"{m['status']:<10} {m['name']:<28} {m['id']}")
PY

# 抽出 OFFLINE 的 (id, name) 列表
mapfile -t offline < <(
  python3 -c "
import json
d = json.loads('''$list_json''')
for m in d['machines']:
    if m['status'] != 'ONLINE':
        print(f\"{m['id']}\t{m['name']}\")
"
)

echo
n=${#offline[@]}
if [ "$n" -eq 0 ]; then
  echo "✓ 没有 OFFLINE 机器，无需清理。"
  exit 0
fi

echo "找到 $n 台 OFFLINE 机器:"
printf '  - %s\n' "${offline[@]##*$'\t'}"

if [ "$mode" = "list" ]; then
  echo
  echo "（仅列出。加 --yes 实际删除，--dry-run 看不执行的删除计划）"
  exit 0
fi

if [ "$mode" = "dry-run" ]; then
  echo
  echo "── DRY RUN：以下 DELETE 请求会被发出（实际未执行）──"
  for line in "${offline[@]}"; do
    id="${line%%$'\t'*}"; name="${line##*$'\t'}"
    echo "  DELETE $API_BASE/machines/$id   # $name"
  done
  exit 0
fi

# ── 实际删除 ──
echo
echo "── 开始删除 ──"
fail=0
for line in "${offline[@]}"; do
  id="${line%%$'\t'*}"; name="${line##*$'\t'}"
  code=$(curl -sS -X DELETE -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $PAT" "$API_BASE/machines/$id")
  if [ "$code" = "204" ]; then
    echo "  ✓ $name (HTTP $code)"
  else
    echo "  ✗ $name (HTTP $code)"
    fail=$((fail+1))
  fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "✓ 全部 $n 台删除成功。"
else
  echo "⚠ $fail/$n 台删除失败（见上方 HTTP code）。"
  exit 1
fi
