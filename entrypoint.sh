#!/bin/bash
# ─────────────────────────────────────────────
#  airacle-dev 容器启动入口
#
#  作用：
#  1. 容器启动/重启时自动恢复 Omnara daemon
#  2. 后台 watchdog 每 30 秒检查，崩了自动重启
#     这样 dashboard 上的机器永远在线
# ─────────────────────────────────────────────

start_omnara_daemon() {
    omnara daemon start --no-wait 2>&1 | sed 's/^/[airacle-dev] /' || true
}

# ── 初次启动 ──────────────────────────────────
if [ -f /root/.omnara/creds.json ]; then
    echo "[airacle-dev] Logged into Omnara. Starting daemon..."
    start_omnara_daemon

    # ── 后台 watchdog：每 30 秒保活 ─────────────
    (
        while true; do
            sleep 30
            if ! omnara daemon status >/dev/null 2>&1; then
                echo "[airacle-dev] 🔄 Omnara daemon down, restarting..."
                start_omnara_daemon
            fi
        done
    ) &

    echo "[airacle-dev] ✅ Omnara watchdog started (PID $!)"
else
    echo "[airacle-dev] ℹ️  Not logged into Omnara. Run 'omnara auth login' to enable dashboard."
fi

# ── 执行容器的实际 CMD（默认 /bin/bash）─────────
exec "$@"
