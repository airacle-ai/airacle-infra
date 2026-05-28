# 06 — 登录流程（Claude Code + Omnara）

**这是新机器开通必看的一份**——两个工具的登录方式都有坑，文档化在这避免反复踩。

---

## Claude Code 登录

### ✅ 正确方式（账号登录 / OAuth）

```bash
docker exec -it airacle-dev claude          # 直接进 claude
# 第一次进会弹出 "How would you like to authenticate?"
# 选 "Use Claude account" → 浏览器授权
```

或显式触发：
```bash
docker exec -it airacle-dev claude auth login --claudeai
```

**两条都能用，但实际经验：直接 `claude` 进去走默认流更稳。**

### ❌ 容易踩坑的方式

`claude auth login` 默认有时会走 Anthropic Console（API Key）流程，
会让你输入 key 而不是浏览器登录。如果你只有 Claude Pro 订阅没 Console API key，
就会卡住。

### ❌ 更隐蔽的坑：`.env` 里留着 `ANTHROPIC_API_KEY` 占位符

即使你 OAuth 登录成功了，只要 `.env` 里有 `ANTHROPIC_API_KEY=sk-ant-xxxxxxxx`（占位符），
Claude 启动就会优先用这个假 key → 报 `Invalid API key`。

**正解**：`.env` 里把 `ANTHROPIC_API_KEY=` 留空（注意 `=` 后面什么都不写）。
详见 [08-lessons-learned.md 坑 11](./08-lessons-learned.md)。

### 登录成功的证据

```bash
docker exec airacle-dev claude auth status
# 应输出: { "loggedIn": true, "authMethod": "oauth", ... }

# 宿主机持久化目录有内容
ls projects/airacle-dev/.claude/
# 应有: auth.json, settings.json, projects/, ...
```

---

## Omnara 登录

### ✅ 标准登录流程

```bash
docker exec -it airacle-dev omnara auth login
```

会输出：
```
Open this link if it did not open automatically:
  https://www.omnara.com/cli-auth?session=<...>&state=<...>

Input fallback code if automatic login doesn't complete:
```

在浏览器打开链接 → 用 Omnara 账号登录 → 授权 → 拿到 fallback code → 粘回终端。

### ⚠️ 关键陷阱：登录 ≠ 出现在 Dashboard

`omnara auth login` 只是**存凭证**。要让机器在 Dashboard 中可见，
**必须启动 daemon**：

```bash
docker exec airacle-dev omnara daemon start
```

**好消息**：本仓库的 Dockerfile 里已经写了 entrypoint，
容器启动时如果检测到 `~/.omnara/creds.json` 就**自动启动 daemon**。
你只需要登录一次，之后重启/重建容器都是开机即上线。

### 登录成功的证据

```bash
docker exec airacle-dev omnara auth status     # → Authentication: PAT stored
docker exec airacle-dev omnara daemon status   # → 显示 daemon PID
```

宿主机持久化目录：
```bash
ls projects/airacle-dev/.omnara/
# 应有: creds.json, recent-sessions.json
```

打开 https://omnara.com 或手机 App，机器名（容器 hostname）应出现在下拉列表。

---

## 自动化登录的 trick：tmux 保 session

某些登录流（特别是 Omnara 的 fallback code 输入）需要**交互式 shell 在浏览器期间持续运行**。
如果你 SSH 断了或终端关了，进程就死了，得重头来。

### 推荐做法：在 SSH 主机上开 tmux 跑这些命令

```bash
ssh slowpc-linux
tmux new -s airacle-login        # 开个 tmux session

# 在 tmux 里跑登录
docker exec -it airacle-dev omnara auth login
# 此时拿到 URL，浏览器去授权

# 即使关掉 SSH 客户端，tmux session 仍在跑
# 想回来:
ssh slowpc-linux
tmux attach -t airacle-login     # 恢复 session，进程还在等输入
```

### Claude Code 长期会话也建议用 tmux

如果你想让 Claude Code 在容器里跑很久（比如让它独立完成长任务），
不要在普通 SSH 里跑 `claude`，因为 SSH 一断 claude 就死了。

正确做法：
```bash
# 容器里也可以装 tmux（镜像已经装好了）
docker exec -it airacle-dev tmux new -s claude-work
# 在 tmux 里跑 claude
claude

# 之后随时 ssh 进来 attach
docker exec -it airacle-dev tmux attach -t claude-work
```

这就是 Omnara 自家的"headless mode"想解决的问题，但 tmux 是更通用的方案。

---

## Omnara 启动正确性 Checklist（每次部署都跑一遍）

新机器、镜像 rebuild、compose 改动……任何可能影响 Omnara 的操作之后，
按这个 checklist 跑一遍就能确认整套链路真的通了。

```bash
CT=airacle-dev   # 容器名，按需替换

# ✅ 1. 容器健康
docker ps --filter "name=^${CT}$" --format "{{.Status}}"
#   期望: Up X (healthy)

# ✅ 2. hostname 正确（= Omnara Dashboard 上的机器名）
[ "$(docker exec $CT hostname)" = "$CT" ] && echo OK || echo "FAIL: hostname mismatch"

# ✅ 3. /opt/omnara/omnara 不会触发自更新（核心防护）
docker exec $CT /opt/omnara/omnara --version 2>&1 | head -1
#   期望: 直接打印版本号（如 "0.25.12"）
#   失败: 出现 "Updating Omnara CLI..." → 坑 8 复发，立刻 cp 同步

# ✅ 4. /usr/local/bin/omnara symlink 指向工作版
docker exec $CT readlink -f /usr/local/bin/omnara
#   期望: /root/.omnara/bin/omnara

# ✅ 5. PATH 顺序正确（/usr/local/bin 在 /opt/omnara 之前）
docker exec $CT bash -c 'which omnara'
#   期望: /usr/local/bin/omnara（不是 /opt/omnara/omnara）

# ✅ 6. 登录凭证存在 + 在 volume 里（重建容器不丢）
docker exec $CT ls -la /root/.omnara/creds.json
#   期望: 文件存在
docker volume inspect airacle-${CT}-omnara-config --format '{{.Mountpoint}}' \
  | xargs -I {} docker run --rm -v {}:/d alpine ls /d/creds.json
#   期望: 也能在 volume 里看到（如果用的是 named volume；bind mount 直接 ls 宿主机路径）

# ✅ 7. Daemon 跑得稳（关键：等 90s 看 PID 是否还在）
PID1=$(docker exec $CT /root/.omnara/bin/omnara daemon status 2>/dev/null | awk '/PID/{print $2}')
sleep 90
PID2=$(docker exec $CT /root/.omnara/bin/omnara daemon status 2>/dev/null | awk '/PID/{print $2}')
[ -n "$PID1" ] && [ "$PID1" = "$PID2" ] && echo "OK (PID $PID1 stable)" \
  || echo "FAIL: daemon restarting (PID drift $PID1 -> $PID2)"

# ✅ 8. 后端注册的机器名 = hostname
docker exec $CT bash -c \
  "ls -t /root/.omnara/logs/daemon/ | head -1 | xargs -I {} grep 'Registered machine' /root/.omnara/logs/daemon/{}"
#   期望: Registered machine $CT (UUID) with backend

# ✅ 9. 浏览器确认: 打开 https://omnara.com → 机器列表里 $CT 是绿点
```

**自动化版本**：把上面 9 步写成一个脚本扔在 `scripts/verify-omnara.sh`，
新机器开通 / 每次 rebuild 之后都跑一遍。任何一步 FAIL 就对照 `04-troubleshooting.md` 排查。

---

## 注入式登录（自动化场景）

如果你想完全脚本化登录（比如批量初始化 N 台机器），
Omnara 的 fallback code 输入可以用 FIFO 注入：

```bash
# 1. 在容器内建 FIFO
docker exec airacle-dev bash -c "rm -f /tmp/omnara_in; mkfifo /tmp/omnara_in"

# 2. 后台启动 omnara auth login，stdin 来自 FIFO
docker exec -d airacle-dev bash -c \
  "omnara auth login < /tmp/omnara_in > /tmp/omnara_out 2>&1"

# 3. 从 /tmp/omnara_out 解析出 OAuth URL，让人或脚本完成浏览器授权
docker exec airacle-dev cat /tmp/omnara_out

# 4. 拿到 fallback code 后注入
docker exec airacle-dev bash -c "echo 'YOUR_CODE' > /tmp/omnara_in"

# 5. 验证
docker exec airacle-dev omnara auth status
docker exec airacle-dev rm -f /tmp/omnara_in /tmp/omnara_out
```

**实战中更推荐 tmux**——更简单，调试容易。
