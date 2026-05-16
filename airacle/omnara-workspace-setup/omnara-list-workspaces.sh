#!/usr/bin/env bash
# =============================================================================
# omnara-list-workspaces.sh
# 查看当前机器上所有已注册的 Omnara Workspace
#
# 用法:
#   ./omnara-list-workspaces.sh
#
# =============================================================================

set -euo pipefail

OMNARA_DIR="${HOME}/.omnara"
OMNARA_API="https://api.omnara.com"

# ---- 颜色输出 ----
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC}  $*"; }

# ---- 读取配置 ----
PAT=$(python3 -c "import json; d=json.load(open('${OMNARA_DIR}/creds.json')); print(d.get('pat') or d.get('token') or list(d.values())[0])")
DAEMON_STATE="${OMNARA_DIR}/daemon-state.json"
DAEMON_PORT=$(python3 -c "import json; print(json.load(open('${DAEMON_STATE}'))['port'])")
DAEMON_TOKEN=$(python3 -c "import json; print(json.load(open('${DAEMON_STATE}'))['token'])")
MACHINE_ID=$(python3 -c "import json; d=json.load(open('${OMNARA_DIR}/daemon.json')); print(list(d['machines'].values())[0])")

echo ""
echo "============================================"
echo "  Omnara Workspace 状态查看"
echo "============================================"
echo ""

# ---- Daemon 本地目录 ----
echo -e "${GREEN}【本地 Daemon 已注册目录】${NC}"
curl -s \
    -H "Authorization: Bearer ${DAEMON_TOKEN}" \
    "http://localhost:${DAEMON_PORT}/directories" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
dirs = data.get('directories', [])
print(f'  共 {len(dirs)} 个目录:')
for d in dirs:
    print(f\"  {'✓':2} {d['path']:<40} id: {d['id']}\")
"

echo ""

# ---- Omnara 后端 Workspace ----
echo -e "${GREEN}【Omnara 后端 Workspace 列表】${NC}"
curl -s "${OMNARA_API}/api/v1/workspaces" \
    -H "Authorization: Bearer ${PAT}" \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
# 支持列表或带 items 的分页格式
workspaces = data if isinstance(data, list) else data.get('items', data.get('workspaces', []))
machine_id = '${MACHINE_ID}'
print(f'  共 {len(workspaces)} 个 workspace:')
for ws in workspaces:
    ws_id = ws.get('id', 'N/A')
    # 找到当前机器对应的 local_path
    paths = ws.get('user_machine_paths', [])
    local_path = next((p['local_path'] for p in paths if p.get('user_machine_id') == machine_id), '(其他机器)')
    sync = ws.get('workspace_config', {}).get('sync', {}).get('enabled', False)
    sync_str = '同步开启' if sync else '同步关闭'
    print(f\"  {'✓':2} {local_path:<40} {sync_str}  id: {ws_id}\")
" 2>/dev/null || echo "  (获取失败，请检查网络或 PAT Token)"

echo ""
echo "============================================"
echo ""
