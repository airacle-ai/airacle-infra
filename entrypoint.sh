#!/bin/bash
# ─────────────────────────────────────────────
#  airacle-dev 容器启动入口
#
#  作用：
#  1. Bootstrap Omnara 二进制到 bind-mount 目录
#     （让自动更新机制正常工作，不卡死在旧版）
#  2. 容器启动/重启时自动恢复 Omnara daemon
#  3. 后台 watchdog 每 60 秒检查，崩了自动重启
#
#  设计原则：
#  - /opt/omnara/omnara      = 镜像内 bootstrap 版（只用于首次初始化）
#  - ~/.omnara/bin/omnara    = 工作版（bind mount 持久化，自动更新落在这里）
#  - /usr/local/bin/omnara   = symlink 始终指向工作版
# ─────────────────────────────────────────────

OMNARA_WORK=/root/.omnara/bin/omnara
OMNARA_BOOT=/opt/omnara/omnara

# ── Step 1: 确保工作目录里有最新二进制 ──────────
if [ ! -f "$OMNARA_WORK" ]; then
    echo "[airacle-dev] First boot: bootstrapping Omnara from image..."
    mkdir -p /root/.omnara/bin
    cp "$OMNARA_BOOT" "$OMNARA_WORK"
    chmod +x "$OMNARA_WORK"
fi

# ── Step 2: symlink 始终指向工作版（自动更新后也有效）─
ln -sf "$OMNARA_WORK" /usr/local/bin/omnara

OMNARA_VER=$("$OMNARA_WORK" --version 2>/dev/null || echo "unknown")
echo "[airacle-dev] Omnara version: $OMNARA_VER"

# ── Step 3: 起 daemon（如已登录）────────────────
start_omnara_daemon() {
    "$OMNARA_WORK" daemon start --no-wait 2>&1 | sed 's/^/[airacle-dev] /' || true
}

if [ -f /root/.omnara/creds.json ]; then
    echo "[airacle-dev] Logged into Omnara. Starting daemon..."
    start_omnara_daemon

    # ── Step 4: watchdog 每 60 秒保活 ───────────
    (
        while true; do
            sleep 60
            if ! "$OMNARA_WORK" daemon status >/dev/null 2>&1; then
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
