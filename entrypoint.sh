#!/bin/bash
# ─────────────────────────────────────────────
#  airacle-dev 容器启动入口
#
#  设计原则：
#  - /opt/omnara/omnara      = 镜像内 bootstrap 版（首次初始化用）
#  - ~/.omnara/bin/omnara    = 工作版（bind mount 持久化，自动更新落在这里）
#  - /usr/local/bin/omnara   = symlink 始终指向工作版
#
#  ⚠️  watchdog 只调 `daemon start`，绝不调 `omnara --claude-code`
#      `omnara --claude-code` 每次都创建新 session，会耗尽账号上限
#      session 应由用户主动开启，不自动创建
# ─────────────────────────────────────────────

OMNARA_WORK=/root/.omnara/bin/omnara
OMNARA_BOOT=/opt/omnara/omnara

# ── Step 1: 首次启动 bootstrap ───────────────
if [ ! -f "$OMNARA_WORK" ]; then
    echo "[airacle] First boot: bootstrapping Omnara binary..."
    mkdir -p /root/.omnara/bin
    cp "$OMNARA_BOOT" "$OMNARA_WORK"
    chmod +x "$OMNARA_WORK"
fi

# ── Step 2: symlink 始终指向工作版 ────────────
ln -sf "$OMNARA_WORK" /usr/local/bin/omnara

# ── Step 2.5: 把 bootstrap 版本同步到工作版 ────
# 防御性深度防护：万一哪天 PATH 顺序又把 /opt/omnara 放回前面，
# 或者有人直接调 /opt/omnara/omnara，至少不会再触发自更新循环。
# 详见 docs/08-lessons-learned.md 坑 8。
if [ -f "$OMNARA_WORK" ] && [ -f "$OMNARA_BOOT" ]; then
    if ! cmp -s "$OMNARA_WORK" "$OMNARA_BOOT"; then
        echo "[airacle] Syncing /opt/omnara/* with working version (avoid stale boot binary)..."
        cp -f /root/.omnara/bin/omnara         /opt/omnara/omnara         2>/dev/null || true
        cp -f /root/.omnara/bin/omnara-claude  /opt/omnara/omnara-claude  2>/dev/null || true
        cp -f /root/.omnara/bin/omnara-codex   /opt/omnara/omnara-codex   2>/dev/null || true
    fi
fi

OMNARA_VER=$("$OMNARA_WORK" --version 2>/dev/null | grep -v Updating | tail -1 || echo "unknown")
echo "[airacle] Omnara: $OMNARA_VER"

# ── Step 3: 仅起 daemon，不创建 session ───────
# daemon start = 机器在 dashboard 可见
# omnara --claude-code = 创建新 session（用户手动触发）
start_daemon() {
    "$OMNARA_WORK" daemon start --no-wait 2>&1 | grep -v "^$" | sed 's/^/[airacle] /' || true
}

if [ -f /root/.omnara/creds.json ]; then
    echo "[airacle] Starting Omnara daemon (no session created)..."
    start_daemon

    # ── Step 4: watchdog 每 120 秒检查一次 ──────
    # 间隔拉长到 2 分钟，减少对 Omnara 服务器的压力
    (
        while true; do
            sleep 120
            if ! "$OMNARA_WORK" daemon status >/dev/null 2>&1; then
                echo "[airacle] 🔄 Daemon down, restarting (no session)..."
                start_daemon
            fi
        done
    ) &
    echo "[airacle] ✅ Watchdog started (interval: 120s, PID $!)"
else
    echo "[airacle] ℹ️  Not logged into Omnara. Run: omnara auth login"
fi

# ── 执行容器的实际 CMD ────────────────────────
exec "$@"
