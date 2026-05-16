#!/bin/bash
# ─────────────────────────────────────────────
#  airacle-dev 容器启动入口
#
#  作用：容器启动/重启时自动恢复 Omnara daemon
#       这样 dashboard 上的机器永远在线
# ─────────────────────────────────────────────

# 如果已登录 Omnara（creds.json 存在），自动起 daemon
if [ -f /root/.omnara/creds.json ]; then
    # daemon 可能已在跑（不太可能但保险起见）
    if ! omnara daemon status >/dev/null 2>&1; then
        echo "[airacle-dev] Starting Omnara daemon..."
        omnara daemon start --no-wait 2>&1 | sed 's/^/[airacle-dev] /' || \
            echo "[airacle-dev] ⚠️  Omnara daemon failed to start (non-fatal)"
    else
        echo "[airacle-dev] Omnara daemon already running"
    fi
else
    echo "[airacle-dev] ℹ️  Not logged into Omnara. Run 'omnara auth login' to enable dashboard."
fi

# 执行容器的实际 CMD（默认 /bin/bash）
exec "$@"
