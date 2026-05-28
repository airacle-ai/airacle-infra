# 09 — 镜像预装环境清单

容器进去能直接用什么、API key 怎么来——这一篇查清楚。

---

## 🔑 API Keys（中央 secrets 注入）

所有 API key 来自宿主机 `~/.airacle/secrets.env`，由 docker-compose `env_file` 注入。
**这个文件 git 永远碰不到，团队成员各自维护自己的副本**。

### 默认提供的 key 槽位

| Key | 用途 |
|-----|------|
| `OPENAI_API_KEY` | OpenAI API（Codex 自己也有 OAuth，这个是给项目代码调 API 用的）|
| `GITHUB_TOKEN` / `GH_TOKEN` | gh CLI、git push、GitHub Actions API |
| `CF_API_TOKEN` / `CLOUDFLARE_API_TOKEN` | wrangler 部署、Cloudflare API |

### 不该出现的 key

- `ANTHROPIC_API_KEY`——除非你显式用 API 计费。详见 [坑 11](./08-lessons-learned.md)
- 任何**占位符**（`sk-ant-xxx`、`your-key-here`）——比留空更糟

### 加新 key 的流程

```bash
# 1. 编辑中央文件
$EDITOR ~/.airacle/secrets.env
# 例如加: SUPABASE_URL=https://xxx.supabase.co

# 2. 重启容器让新 env 生效（env_file 在容器创建时定型，光 restart 不够）
docker-compose down && docker-compose up -d

# 3. 验证
docker exec airacle-dev printenv SUPABASE_URL
```

---

## 📦 预装命令行工具

### 系统包（apt）

| 类别 | 包 |
|------|-----|
| Python 运行时 | `python3` `python3-pip` `python3-venv` `pipx` |
| Dev 基础 | `git` `curl` `wget` `vim` `nano` `jq` `unzip` `build-essential` |
| Shell 体验 | `bash-completion` `less` `htop` `tmux` |
| 媒体/搜索 | `ffmpeg` `ripgrep`(`rg`) `fd-find`(`fd`) `bat` |
| GitHub | `gh` |

### Node CLI

| 工具 | 用途 |
|------|------|
| `claude` | Claude Code CLI（OAuth 登录） |
| `codex` | OpenAI Codex CLI |
| `omnara` | Omnara CLI（也有 daemon，详见架构文档） |
| `wrangler` | Cloudflare Workers / Pages 部署 |

### pipx 工具

| 工具 | 用途 |
|------|------|
| `yt-dlp` | 视频下载 |

---

## 🐍 Python 预装库（系统级，`import` 即用）

| 包 | 用途 |
|----|------|
| `anthropic` | Anthropic SDK |
| `openai` | OpenAI SDK |
| `requests` | 经典 HTTP |
| `httpx` | 现代 HTTP（同步 + 异步）|
| `python-dotenv` | 加载 .env 文件 |
| `pydantic` | 数据校验 / 结构化输出 |
| `fastapi` | Web 框架 |
| `uvicorn` | ASGI server |

**项目专属依赖**：在 `workspace/` 下用 `python3 -m venv .venv && pip install ...`，
不要污染系统 Python。

---

## 📜 Node 预装库（全局，可直接 `require/import`）

| 包 | 用途 |
|----|------|
| `@anthropic-ai/sdk` | Anthropic SDK |
| `openai` | OpenAI SDK |
| `axios` | HTTP 客户端 |
| `dotenv` | 加载 .env |
| `zod` | 运行时 schema 校验 |

**项目专属依赖**：在 `workspace/<proj>/` 下用 `npm install`，本地 node_modules 优先。

---

## ⚙️ 容器环境变量

| 变量 | 值 | 来源 | 作用 |
|------|----|----|------|
| `IS_SANDBOX` | `1` | docker-compose `environment` | Claude Code 跳过权限提示（详见坑 12）|
| `CLAUDE_MODEL` | `claude-sonnet-4-5` | 项目 `.env` | Claude 默认模型 |
| `LANG` | `en_US.UTF-8` | docker-compose | locale |
| `TZ` | `Asia/Shanghai` | docker-compose | 时区 |
| `NVIDIA_*` | `all` / `compute,utility` | docker-compose | GPU 透传（airacle-infra）|
| API keys | — | `~/.airacle/secrets.env` | 见上 |

---

## 加包/换 key 的常见任务

### 新增一个 Python 库到镜像

```dockerfile
# 编辑 Dockerfile，在 pip3 install 那一段加
RUN pip3 install --no-cache-dir --break-system-packages \
    anthropic openai requests httpx python-dotenv pydantic fastapi uvicorn \
    <你要的新包>
```

然后 `docker build -t airacle-dev:latest .` 重建。详见 [03-update-playbook.md](./03-update-playbook.md)。

### 新增一个 Node CLI

```dockerfile
# 编辑 Dockerfile 的 npm install -g 段
RUN npm install -g claude-code codex ... <新包>
```

### 临时在容器里装东西（不入镜像）

```bash
docker exec -it airacle-dev bash
pip3 install --break-system-packages <pkg>   # 装在容器层，重建容器丢失
```

如果觉得这个包以后还要用，**加进 Dockerfile 重建镜像**才能持久。

---

## 故障排查

- 找不到命令 → 看 [04-troubleshooting.md Q1](./04-troubleshooting.md)
- API key 没生效 → `docker exec airacle-dev printenv <KEY_NAME>` 看真容器 env 有没有
  - 没有：检查 `~/.airacle/secrets.env` 有没有这行 + 改完是否 `down && up -d`
  - 有但是错误：检查不是占位符（详见坑 11）
- 加了包但 import 报错 → 可能是装在了用户层而不是系统级，看上面"临时装"小节
