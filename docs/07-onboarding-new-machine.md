# 07 — 新机器开通（10 分钟从零到可用）

**目标**：在一台新的 Linux/WSL 机器上，从零部署一套 Airacle 开发环境。

---

## 前置要求

- Linux / WSL2 / macOS（amd64 或 arm64）
- Docker + docker-compose（v1 或 v2 均可）
- Git
- SSH 已配置好 GitHub 访问权限
- 至少 10 GB 可用磁盘（镜像约 4 GB，每个项目几十 MB）

---

## Step 1: Clone 仓库

```bash
git clone git@github.com:airacle-ai/airacle-infra.git
cd airacle-infra
```

## Step 2: 构建基础镜像（约 5 分钟）

```bash
cd airacle-dev
docker build -t airacle-dev:latest .
cd ..
```

> 如果用 docker-compose v2 (`docker compose`)：`docker compose build`

## Step 3: 设置中央 secrets 文件（**新机器必做**）

所有 API key（GITHUB / CLOUDFLARE / OPENAI 等）走中央 secrets 文件，
所有项目容器共享一份，git 永远碰不到。

```bash
mkdir -p ~/.airacle && chmod 700 ~/.airacle
cat > ~/.airacle/secrets.env <<'EOF'
# ─────────────────────────────────────
# Airacle 中央 secrets
# - 只放 API keys 类的密钥
# - 留空 = 该 key 不存在（OK），不要写占位符 sk-xxx（会触发坑 11）
# ─────────────────────────────────────
OPENAI_API_KEY=
GITHUB_TOKEN=
GH_TOKEN=
CF_API_TOKEN=
CLOUDFLARE_API_TOKEN=
# 按需补充：VERCEL_TOKEN=、SUPABASE_*=、AWS_*=…
EOF
chmod 600 ~/.airacle/secrets.env
# 然后用你喜欢的编辑器填入真实值
```

> **从已有机器迁移**：如果旧机器的 key 散在 `~/.bashrc` 里：
> ```bash
> grep -E "^export (OPENAI_API_KEY|GITHUB_TOKEN|GH_TOKEN|CF_API_TOKEN|CLOUDFLARE_API_TOKEN)=" \
>   ~/.bashrc | sed 's/^export //' > ~/.airacle/secrets.env
> chmod 600 ~/.airacle/secrets.env
> ```

## Step 4: 准备首个项目

```bash
PROJECT_NAME=airacle-dev   # 改成你想要的名字

mkdir -p projects/$PROJECT_NAME/{.claude,.omnara,workspace}
touch projects/$PROJECT_NAME/.claude.json   # Claude Code 需要这个文件挂载点
cp .env.example projects/$PROJECT_NAME/.env
# 项目专属的非密参数（如 CLAUDE_MODEL）填这里；API key 由 ~/.airacle/secrets.env 注入
```

`docker-compose.yml` 默认有 `airacle-dev` 这个 service，
如果你用了别的名字，复制并改名即可（或者用 `./add-project.sh <name>`）。

## Step 5: 启动容器

```bash
docker-compose up -d            # v1
# 或
docker compose up -d            # v2
```

验证：
```bash
docker ps --filter "name=airacle"
# 应看到 airacle-dev (或你的项目名) Up and healthy
```

## Step 6: 登录工具（一次性，登好就持久化）

```bash
# 推荐先开 tmux 防 SSH 断
tmux new -s setup

# 1. Claude Code
docker exec -it airacle-dev claude        # 走浏览器 OAuth
# 详见 06-login-procedures.md

# 2. Omnara
docker exec -it airacle-dev omnara auth login
# 浏览器授权 + fallback code，详见 06-login-procedures.md
```

## Step 7: 验证全链路

```bash
# 容器里跑：
docker exec airacle-dev bash -c "
  claude auth status &&
  omnara auth status &&
  omnara daemon status
"
```

打开 https://omnara.com，应该能看到这台机器的容器名出现在下拉列表里。

## Step 8: 重启验证持久性（推荐做一次）

```bash
docker rm -f airacle-dev
docker-compose up -d
sleep 5
docker exec airacle-dev omnara auth status   # 仍为 PAT stored
docker exec airacle-dev omnara daemon status # daemon 自动起来了
```

如果通过，**这台机器从此进入"开机即用"状态**。

---

## 批量部署 N 台机器的思路

如果你要给团队一次性开 N 台开发机：

### 方案 A: 一台机器跑 N 个项目容器
适合资源充足的强力机器，比如 Mac Studio / 高配 NUC。
按 Step 1-4 部署后，重复执行：
```bash
./add-project.sh <project-2>
./add-project.sh <project-3>
# 把 docker-compose.yml 里粘进对应 service，然后 docker-compose up -d
```

每个项目独立沙箱、互不影响。

### 方案 B: N 台物理机/VM 各部署一份
每台机器都执行 Step 1-6 一遍。
为了避免每台都手动登录，可以：
- 在中央保管一份"参考"`projects/<n>/.claude/` 和 `.omnara/creds.json`
- 通过 `rsync` 把它们分发到每台机器对应路径
- 重启容器，daemon 自动起来

⚠️ **凭证文件涉密**，分发流程要走加密通道（scp + 服务端密钥 / 1Password / vault）。

### 方案 C: 镜像里预置共享凭证（**不推荐**）
如果团队公用一个 Omnara 账号（已经讨论过），
可以把 `creds.json` 烤进基础镜像。
**但 API key / token 烤进镜像意味着推 GitHub 就泄密了**，强烈不推荐。

---

## 维护节奏建议

| 频率 | 操作 | 命令 |
|------|------|------|
| 每周 | 拉最新工具版本 | `cd airacle-dev && docker build --no-cache -t airacle-dev:latest .` |
| 加工具时 | 修 Dockerfile | `vim airacle-dev/Dockerfile && docker build ...` |
| 出问题时 | 看日志 | `docker logs airacle-dev` |
| 加项目 | 一键脚本 | `./add-project.sh <name>` |

详见 [03-update-playbook.md](./03-update-playbook.md)。
