#!/usr/bin/env bash
# =============================================================================
# omnara-add-workspaces.sh
# 批量将本地目录注册为 Omnara Workspace
#
# 用法:
#   ./omnara-add-workspaces.sh <目录1> [目录2] [目录3] ...
#   ./omnara-add-workspaces.sh /workspace          # 将 /workspace 所有子目录注册
#   ./omnara-add-workspaces.sh /workspace/Jack /workspace/Kevin
#
# =============================================================================

set -euo pipefail

OMNARA_DIR="${HOME}/.omnara"
OMNARA_API="https://api.omnara.com"

# ---- 颜色输出 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---- 读取配置 ----
read_config() {
    # PAT Token
    CREDS_FILE="${OMNARA_DIR}/creds.json"
    if [[ ! -f "$CREDS_FILE" ]]; then
        error "未找到认证文件: $CREDS_FILE"
        error "请先运行 'omnara auth login' 登录"
        exit 1
    fi
    PAT=$(python3 -c "import json; d=json.load(open('${CREDS_FILE}')); print(d.get('pat') or d.get('token') or d.get('access_token') or list(d.values())[0])")

    # Daemon 信息
    DAEMON_STATE="${OMNARA_DIR}/daemon-state.json"
    if [[ ! -f "$DAEMON_STATE" ]]; then
        error "Daemon 未运行，请先执行: omnara daemon start"
        exit 1
    fi
    DAEMON_PORT=$(python3 -c "import json; print(json.load(open('${DAEMON_STATE}'))['port'])")
    DAEMON_TOKEN=$(python3 -c "import json; print(json.load(open('${DAEMON_STATE}'))['token'])")

    # Machine ID
    DAEMON_JSON="${OMNARA_DIR}/daemon.json"
    MACHINE_ID=$(python3 -c "import json; d=json.load(open('${DAEMON_JSON}')); print(list(d['machines'].values())[0])")

    info "Daemon 端口: $DAEMON_PORT"
    info "Machine ID: $MACHINE_ID"
}

# ---- 确保 git 系统配置允许任意目录 ----
setup_git_safe_dirs() {
    if ! git config --system safe.directory '*' 2>/dev/null; then
        warn "无法设置 git system safe.directory，尝试其他方式..."
    fi
}

# ---- 初始化 Git 仓库 ----
init_git_repo() {
    local dir="$1"
    local name
    name=$(basename "$dir")

    if [[ -d "${dir}/.git" ]]; then
        info "${name}: 已是 Git 仓库，跳过初始化"
        return 0
    fi

    info "${name}: 初始化 Git 仓库..."
    git init "$dir" -q
    echo "# ${name} Workspace" > "${dir}/README.md"
    git -C "$dir" add README.md
    git -C "$dir" \
        -c user.email="omnara-setup@local" \
        -c user.name="Omnara Setup" \
        commit -q -m "init: initialize ${name} workspace"
    success "${name}: Git 仓库初始化完成"
}

# ---- 向 Daemon 注册目录 ----
register_with_daemon() {
    local dir="$1"
    local name
    name=$(basename "$dir")

    local response
    response=$(curl -s -X POST \
        -H "Authorization: Bearer ${DAEMON_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"path\": \"${dir}\"}" \
        "http://localhost:${DAEMON_PORT}/directories" 2>&1)

    if echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'id' in d or 'directory' in d else 1)" 2>/dev/null; then
        success "${name}: 已注册到 Daemon"
    else
        # 可能已经存在，不报错
        warn "${name}: Daemon 注册响应: ${response}"
    fi
}

# ---- 调用 Omnara 后端 API 创建 Workspace ----
create_workspace() {
    local dir="$1"
    local name
    name=$(basename "$dir")

    local response
    response=$(curl -s -X POST "${OMNARA_API}/api/v1/workspaces/ensure" \
        -H "Authorization: Bearer ${PAT}" \
        -H "Content-Type: application/json" \
        -d "{\"machine_id\": \"${MACHINE_ID}\", \"local_path\": \"${dir}\"}" 2>&1)

    local workspace_id
    workspace_id=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "")

    if [[ -n "$workspace_id" ]]; then
        success "${name}: Workspace 创建成功 → ID: ${workspace_id}"
        echo "$workspace_id"
    else
        error "${name}: 创建失败，响应: ${response}"
        echo ""
    fi
}

# ---- 解析目录参数 ----
resolve_directories() {
    local args=("$@")
    local dirs=()

    for arg in "${args[@]}"; do
        if [[ ! -d "$arg" ]]; then
            error "目录不存在: $arg"
            continue
        fi

        # 检查该目录下是否有子目录；如果有子目录则展开，否则直接使用该目录
        local subdirs=()
        while IFS= read -r -d '' d; do
            subdirs+=("$d")
        done < <(find "$arg" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

        if [[ ${#subdirs[@]} -gt 0 ]]; then
            # 有子目录：询问用户是要展开还是直接注册父目录
            echo ""
            warn "检测到 '$arg' 包含子目录:"
            for sd in "${subdirs[@]}"; do
                echo "    $(basename "$sd")"
            done
            echo -n "  → 注册所有子目录作为独立 workspace? [Y/n] "
            read -r answer
            if [[ "${answer,,}" != "n" ]]; then
                dirs+=("${subdirs[@]}")
            else
                dirs+=("$arg")
            fi
        else
            dirs+=("$arg")
        fi
    done

    echo "${dirs[@]}"
}

# ---- 主流程 ----
main() {
    echo ""
    echo "============================================"
    echo "  Omnara Workspace 批量配置脚本"
    echo "============================================"
    echo ""

    if [[ $# -eq 0 ]]; then
        echo "用法: $0 <目录1> [目录2] ..."
        echo "示例: $0 /workspace"
        echo "示例: $0 /workspace/Jack /workspace/Kevin"
        exit 1
    fi

    # 读取配置
    read_config

    # 修复 git 权限
    setup_git_safe_dirs

    # 解析目录列表
    local -a target_dirs
    # shellcheck disable=SC2207
    IFS=' ' read -r -a target_dirs <<< "$(resolve_directories "$@")"

    if [[ ${#target_dirs[@]} -eq 0 ]]; then
        error "没有有效的目录可处理"
        exit 1
    fi

    echo ""
    info "待处理目录 (${#target_dirs[@]} 个):"
    for d in "${target_dirs[@]}"; do
        echo "    $d"
    done
    echo ""

    # 逐个处理
    local success_count=0
    local fail_count=0
    declare -A results

    for dir in "${target_dirs[@]}"; do
        echo "--------------------------------------------"
        echo "处理: $dir"

        # Step 1: 初始化 Git
        init_git_repo "$dir"

        # Step 2: 注册到 Daemon
        register_with_daemon "$dir"

        # Step 3: 创建 Workspace
        local ws_id
        ws_id=$(create_workspace "$dir")

        if [[ -n "$ws_id" ]]; then
            results["$dir"]="$ws_id"
            ((success_count++))
        else
            ((fail_count++))
        fi

        echo ""
    done

    # 汇总输出
    echo "============================================"
    echo "  完成！结果汇总"
    echo "============================================"
    printf "  %-35s %s\n" "目录" "Workspace ID"
    printf "  %-35s %s\n" "---" "---"
    for dir in "${!results[@]}"; do
        printf "  %-35s %s\n" "$(basename "$dir")" "${results[$dir]}"
    done
    echo ""
    echo "  成功: ${success_count} 个  失败: ${fail_count} 个"
    echo ""
    echo "  请刷新 Omnara 客户端查看新 Workspace ✓"
    echo "============================================"
    echo ""
}

main "$@"
