# 04 — 故障排查

## Q1: 进容器后 `omnara` 命令找不到

**症状**：`bash: omnara: command not found`

**原因**：可能是镜像没装好，或 `~/.omnara` 被错误挂载遮蔽。

**排查**：
```bash
docker exec airacle-dev which omnara
docker exec airacle-dev ls /opt/omnara/   # 应该有 omnara 二进制
docker exec airacle-dev ls -la /usr/local/bin/omnara   # 应该是 symlink
```

如果 `/opt/omnara` 是空的，说明镜像有问题，rebuild：
```bash
cd docker/airacle-dev && docker-compose build --no-cache
```

## Q2: 重启容器后 Claude 要求重新登录

**症状**：之前登过的 Claude，重启容器后又让登录。

**原因**：`.claude/` 没正确 bind mount。

**排查**：
```bash
# 1. 检查宿主机目录里有没有 auth 相关文件
ls -la docker/airacle/projects/<name>/.claude/

# 2. 进容器看挂载点
docker exec airacle-dev mount | grep claude
```

如果宿主机目录是空的但你之前明明登录过，说明登录时 .claude/ 是写到容器的可写层去了——
确认 docker-compose.yml 里这个项目的 volumes 段有：
```yaml
- ./projects/<name>/.claude:/root/.claude
```

## Q3: 镜像 rebuild 后所有容器都打不开

**症状**：`docker-compose up -d` 失败。

**排查**：
```bash
docker logs airacle-dev      # 看具体错误
docker images airacle-dev    # 确认镜像存在
```

**回滚**：见 03-update-playbook 场景 7。

## Q4: 磁盘空间不够

**先看占用大头**：
```bash
docker system df                    # Docker 总体
du -sh docker/airacle/projects/*    # 各项目数据
du -sh docker/airacle-dev/          # 镜像构建上下文
```

**清理**：
```bash
docker image prune                  # 删悬空镜像
docker builder prune                # 删构建缓存
docker container prune              # 删停止的容器
```

## Q5: 容器健康检查显示 unhealthy

**排查**：
```bash
docker inspect airacle-dev --format='{{json .State.Health}}' | jq
```

健康检查是 `claude --version && codex --version && omnara --version`。
任何一个失败容器就 unhealthy。但容器本身仍然能用，只是状态显示问题。

## Q6: 多个容器同时跑，端口冲突

**症状**：第二个项目启动失败，端口被占用。

**原因**：`network_mode: host`，多个容器抢宿主机同一个端口。

**解法**：
- 在容器里跑服务时手动指定不同端口
- 或在该项目的 compose 里改回 bridge 模式 + 端口映射

## Q7: 在容器里 `git push` 失败

**症状**：`Permission denied (publickey)` 或类似。

**原因**：SSH key 没正确挂载，或 key 在容器里权限不对。

**排查**：
```bash
docker exec airacle-dev ls -la /root/.ssh/
docker exec airacle-dev ssh -T git@github.com
```

如果是权限问题，宿主机上确认 `~/.ssh/` 是 700，私钥是 600。

## Q7.5: Omnara Dashboard 上一堆灰色离线机器，想批量清理

Omnara CLI 没有 `machine delete`，但后端 REST API 支持。
本仓库提供脚本：

```bash
# 仅列出，不删
./scripts/omnara-cleanup-offline.sh

# 看会删什么但不执行
./scripts/omnara-cleanup-offline.sh --dry-run

# 真的删
./scripts/omnara-cleanup-offline.sh --yes
```

PAT 来源（脚本自动找）：环境变量 `$OMNARA_PAT` > `~/.omnara/creds.json` > 任意运行中的 `airacle-*` 容器。

**手动版**（不想用脚本）：
```bash
PAT=$(docker exec airacle-dev cat /root/.omnara/creds.json | jq -r .pat)

# 列出
curl -sS -H "Authorization: Bearer $PAT" https://api.omnara.com/api/v1/machines | jq

# 删除某个机器
curl -X DELETE -H "Authorization: Bearer $PAT" \
  "https://api.omnara.com/api/v1/machines/<machine-uuid>"
# 期望 HTTP 204
```

---

## Q8: Omnara Dashboard 里这台机器一直是灰点 / 名字错了

**症状**：
- Omnara 网页机器列表里，这台容器对应的条目是灰点（offline）
- 或者出现了一个意外的机器名（不是你期望的 `airacle-dev`）

**完整排查流程**（按顺序跑，第一个不对的就是病因）：

```bash
# ── Step 1: 容器还活着吗 ──
docker ps | grep airacle-dev
# 期望: Up X (healthy)
# 不对: 容器没起来 → docker-compose up -d

# ── Step 2: hostname 对吗 ──
docker exec airacle-dev hostname
# 期望: airacle-dev（或你 compose 里设的名字）
# 不对: 见坑 9 → 改 compose + down/up（不能只 restart）

# ── Step 3: 登录凭证还在吗 ──
docker exec airacle-dev ls -la /root/.omnara/creds.json
# 不对: 见坑 10 → omnara auth login 重新登录

# ── Step 4: daemon 在跑吗 ──
docker exec airacle-dev /root/.omnara/bin/omnara daemon status
# 期望: 显示 PID 和 Started 时间
# 不对: docker exec -d airacle-dev /root/.omnara/bin/omnara daemon start --no-wait

# ── Step 5: daemon 跑得稳吗（最关键，常见死循环点）──
# 等 90 秒以上，再次 daemon status，PID 应该没变
sleep 90 && docker exec airacle-dev /root/.omnara/bin/omnara daemon status
# 不对（PID 变了 / 不在跑了）: 几乎一定是坑 8——自更新循环
#   立即检查: docker exec airacle-dev /opt/omnara/omnara --version
#   如果输出包含 "Updating..."，就是这个坑

# ── Step 6: 看 daemon 日志确认注册名 ──
docker exec airacle-dev bash -c \
  "ls -t /root/.omnara/logs/daemon/ | head -1 | xargs -I {} cat /root/.omnara/logs/daemon/{}" \
  | grep "Registered machine"
# 期望: Registered machine airacle-dev (UUID) with backend
# 名字不对: 见坑 9
# 完全没这行: 见 Step 5
```

**最常见的根因排序**：
1. 自更新循环（坑 8）—— 至少占 60%
2. hostname 错配 + 没重建容器（坑 9）—— 30%
3. creds.json 没在 volume 里 + 重建丢了（坑 10）—— 10%

---

## Q9: Claude Code 报 `Invalid API key · Fix external API key`（但你明明登录过）

**症状**：
- `claude auth status` 显示登录态正常（OAuth token 有效）
- 但 `claude -p "hi"` 立即报 `Invalid API key · Fix external API key`
- `docker exec airacle-dev bash -c "unset ANTHROPIC_API_KEY && claude -p 'hi'"` 立刻能用

**根因**：env 里 `ANTHROPIC_API_KEY` 被设成了**占位符**（如 `sk-ant-xxxxxxxxxxxx`），
而 Claude 的认证优先级是 `ANTHROPIC_API_KEY` env > OAuth token。详见坑 11。

**排查**：
```bash
# 1. 看 env 里有没有 ANTHROPIC_API_KEY，是不是真 key
docker exec airacle-dev printenv ANTHROPIC_API_KEY
# 期望: 空（如果用 OAuth）或者真实 key（如果用 API 计费）
# 中招: 输出 sk-ant-xxxxxxxxxxxx 这种明显占位符

# 2. 看 .env 文件
cat /path/to/project/.env | grep ANTHROPIC
```

**正解**：
```bash
# 编辑 .env，把占位符清空
sed -i 's/^ANTHROPIC_API_KEY=.*/ANTHROPIC_API_KEY=/' /path/to/project/.env

# 重建容器（光 restart 不够，env 是在容器创建时定型的）
docker-compose down && docker-compose up -d

# 验证
docker exec airacle-dev printenv ANTHROPIC_API_KEY   # 应为空
docker exec airacle-dev claude -p "say OK"           # 应返回 OK
```

## Q10: Claude Code 报 `Claude configuration file not found at: /root/.claude.json`

**症状**：重建容器后第一次跑 `claude` 报这个错，附带一句 `A backup file exists at: ...`

**根因**：`.claude.json` 在容器**根目录**（`/root/.claude.json`），不在 `.claude/` 文件夹里。
如果挂载只挂了 `/root/.claude/`（文件夹），`.claude.json`（文件）就会写到容器层 → 重建丢失。
好在 Claude Code 启动时会自动备份到 `.claude/backups/`，所以 backup 在 volume 里。

**正解**：按提示恢复就好：
```bash
docker exec airacle-dev bash -c \
  'cp /root/.claude/backups/.claude.json.backup.* /root/.claude.json'
```

**根治**：把 `.claude.json` 也挂出来（需要先在宿主机创建空文件占位）：
```yaml
volumes:
  - ./projects/<name>/.claude.json:/root/.claude.json
  - ./projects/<name>/.claude:/root/.claude
```

## Q11: 我想知道现在镜像里到底装了什么

```bash
docker exec airacle-dev bash -c "
  echo '── 系统包 ──'
  dpkg -l | tail -20
  echo '── npm 全局包 ──'
  npm list -g --depth=0
  echo '── pip 包 ──'
  pip list 2>/dev/null
  echo '── /opt 下的工具 ──'
  ls /opt/
"
```
