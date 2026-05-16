# Airacle Infra — 项目上下文（AI Agent 交接文档）

> 这份文档是给下一个接手的 AI agent 或开发者的完整上下文。
> 压缩对话 / 新开对话后，从这里开始就能完整恢复状态。

---

## 项目是什么

一套**批量可复制的 AI 开发容器环境**，一条命令在任意机器上起一个内置
Claude Code + Codex + Omnara + GPU 的沙箱，支持多项目并行、完全隔离、重启不丢状态。

---

## 关键位置

| 位置 | 路径 |
|------|------|
| GitHub Repo | https://github.com/airacle-ai/airacle-infra |
| 宿主机运行目录 | `/mnt/c/Users/oyzh8/Desktop/win_code/docker/airacle/` |
| 本地 Repo 副本 | `/mnt/c/Users/oyzh8/Desktop/win_code/docker/airacle-infra/` |
| SSH | `ssh slowpc-linux`，GitHub 用户 `oyzh888` |

---

## 已部署的容器（当前生产状态）

| 容器名 | 状态 | 说明 |
|--------|------|------|
| `airacle-dev` | ✅ 运行中 | 首个测试容器，Claude + Omnara 已登录 |

进入容器：`docker exec -it airacle-dev /bin/bash`

---

## 架构（三层数据模型）

```
Layer 1: airacle-dev:latest 镜像（只读，所有容器共享）
         工具：Claude Code 2.1.143 / Codex 0.130.0 / Omnara 0.25.6
               tmux / git / gh CLI / Node 22 / Python 3.11
               NVIDIA GPU 透传（RTX 5070，CUDA 13.1）

Layer 2: shared/claude-settings/（只读 bind mount，团队共用）
         CLAUDE.md 等团队文档

Layer 3: projects/<name>/（读写 bind mount，项目完全隔离）
         .claude/    ← Claude Code 登录态 + 对话历史（持久化）
         .omnara/    ← Omnara 凭证 + session（持久化）
         workspace/  ← 代码（持久化）
         .env        ← API Keys（gitignored，不入 git）
```

**黄金原则：二进制在镜像，状态在 bind mount，重启/重建永不丢数据。**

---

## 已配置的认证信息

| 变量 | 说明 | 存储位置 |
|------|------|---------|
| `GITHUB_TOKEN` / `GH_TOKEN` | oyzh888 的 GitHub PAT | `~/.bashrc` + `projects/*/. env` |
| `CF_API_TOKEN` / `CLOUDFLARE_API_TOKEN` | Cloudflare API Token | `~/.bashrc` + `projects/*/.env` |
| Claude Code OAuth | 已登录 | `projects/airacle-dev/.claude/` |
| Omnara PAT | 已登录，daemon 运行 | `projects/airacle-dev/.omnara/creds.json` |

**⚠️ Keys 绝不入 git。`.env` 已在 `.gitignore` 里。**

---

## 机器规格（SlowPC）

- **CPU**: 24 核，通常负载 < 1.0
- **内存**: 31GB，已用 ~11GB，剩余 ~19GB
- **GPU**: NVIDIA RTX 5070 8GB，驱动 591.90，CUDA 13.1（容器内已透传）
- **系统**: WSL2 on Windows，Docker 29.1.3，docker-compose 1.29.2（v1！）

---

## 踩过的坑（必读，别重复踩）

### 1. Omnara 安装方式
- ❌ `pipx install omnara` → 老版本，索要 key，用不了
- ✅ `curl -fsSL https://omnara.com/install.sh | bash`

### 2. Omnara 二进制位置陷阱
官方安装脚本把 **500MB+ 二进制**放到 `~/.omnara/bin/`。
如果直接 bind mount `~/.omnara/`，宿主机空目录会遮蔽二进制，命令消失。

**Dockerfile 里的解决方案**（已实现）：
```dockerfile
RUN curl -fsSL https://omnara.com/install.sh | bash \
    && mv /root/.omnara/bin /opt/omnara \
    && rm -rf /root/.omnara \
    && ln -s /opt/omnara/omnara /usr/local/bin/omnara
```

### 3. Claude Code 登录方式
- ❌ `claude auth login` → 有时走 API Key 流程，没 Console 账号就卡死
- ✅ `claude` 直接进 → 选 "Use Claude account" → 浏览器 OAuth

### 4. Omnara 登录 ≠ 出现在 Dashboard
`omnara auth login` 只存凭证。必须 `omnara daemon start` 机器才出现在 dashboard。
**entrypoint.sh 已处理**：检测到 `creds.json` 就自动起 daemon + watchdog 保活。

### 5. docker-compose v1 的两个坑
- `deploy.resources.reservations.devices`（GPU）是 Swarm 语法，v1 忽略 → 用 `runtime: nvidia`
- v1 + Docker 29.x 有 `KeyError: ContainerConfig` bug → 先 `docker rm -f <name>` 再 `up -d`

### 6. interactive 登录必须用 tmux
SSH 断开 → 进程死 → 重新走 OAuth。
所有登录操作先 `tmux new -s setup`，再在里面操作。

### 7. API Key 的 env_file vs environment 优先级
docker-compose 中 `environment:` 里只列变量名（无值）会以宿主机环境变量**覆盖** `env_file`。
如果宿主机没有该变量，结果是空值。
**正确做法**：Keys 只放 `env_file`，不在 `environment:` 里重复列。

---

## 常用命令

```bash
# 进容器
docker exec -it airacle-dev /bin/bash

# 重启容器（不丢登录态）
cd /mnt/c/Users/oyzh8/Desktop/win_code/docker/airacle
docker rm -f airacle-dev && docker-compose up -d

# 加新项目
./add-project.sh <name>
# → 把输出的 compose 片段粘进 docker-compose.yml
docker-compose up -d <name>

# 升级镜像（全员升级，登录态不丢）
docker build --no-cache -t airacle-dev:latest .
docker-compose up -d

# 推送到 GitHub
cd /mnt/c/Users/oyzh8/Desktop/win_code/docker/airacle-infra
source ~/.bashrc
git add -A && git commit -m "..." && git push origin main
```

---

## 新机器部署（10 分钟）

```bash
git clone git@github.com:airacle-ai/airacle-infra.git
cd airacle-infra

# 构建镜像
docker build -t airacle-dev:latest .

# 准备项目
mkdir -p projects/airacle-dev/{.claude,.omnara,workspace}
cp .env.example projects/airacle-dev/.env
# 填入 Keys: GITHUB_TOKEN, CF_API_TOKEN, ANTHROPIC_API_KEY 等

# 启动
docker-compose up -d

# 进容器登录（在 tmux 里）
tmux new -s setup
docker exec -it airacle-dev claude          # Claude Code OAuth
docker exec -it airacle-dev omnara auth login  # Omnara OAuth
```

---

## 待完成

- [ ] **`init.sh` 一键初始化脚本** —— 自动化新机器的 build + 首次登录引导
- [ ] **验证多项目隔离** —— 加第二个容器，确认 Claude/Omnara session 互不干扰
- [ ] **CUDA toolkit**（可选）—— 如需 PyTorch 推理，在 Dockerfile 加 cuda-runtime
- [ ] **docker-compose v2 迁移**（可选）—— `sudo apt install docker-compose-v2`

---

## 文档索引

| 文档 | 内容 |
|------|------|
| `docs/01-architecture.md` | 整体架构 |
| `docs/02-what-persists.md` | ★ 什么会丢/什么不会 |
| `docs/03-update-playbook.md` | 升级/加工具操作手册 |
| `docs/04-troubleshooting.md` | 故障排查 |
| `docs/05-decisions.md` | 设计决策记录 |
| `docs/06-login-procedures.md` | Claude + Omnara 登录正确姿势 |
| `docs/07-onboarding-new-machine.md` | 新机器部署指南 |
| `docs/08-lessons-learned.md` | ★ 踩坑实录 |
