# Airacle Infra

> **一台机器，跑 N 个互不干扰的 AI 开发沙箱。**
> 每个沙箱内置 Claude Code + Codex + Omnara + tmux + 常用 CLI，
> 二进制全部共享同一个镜像层，会话/登录态/代码完全隔离。

---

## 🎯 这套东西解决什么问题

1. **多账号多项目混用** —— 一个人手上 5-6 个 Claude 账号、N 个项目，账号互相串台是噩梦。
2. **新开发机环境一致** —— "开机即用"，工具版本齐刷刷，不用每台机器配半天。
3. **重启不丢登录** —— Docker 容器重启、镜像重建、宿主机重启，登录态全部保留。
4. **手机远控** —— Omnara 接入后，手机上能看到所有开发会话，随时审阅。

---

## 📂 仓库结构

```
airacle-infra/
├── README.md                       ← 你正在看的
├── CONTEXT.md                      ← AI agent 交接文档（含完整上下文）
├── Dockerfile                      ← 基础镜像源（Claude/Codex/Omnara 都在这里）
├── entrypoint.sh                   ← 容器启动脚本（Omnara daemon + watchdog）
├── docker-compose.yml              ← 项目容器编排
├── add-project.sh                  ← 一键加项目脚本
├── .env.example                    ← Key 模板
├── docs/                           ← 维护文档（必读）
│   ├── 01-architecture.md              整体架构
    │   ├── 02-what-persists.md     ★ 什么会丢/什么不会
    │   ├── 03-update-playbook.md       升级/加工具操作手册
    │   ├── 04-troubleshooting.md       故障排查
    │   └── 05-decisions.md             设计决策记录
    ├── shared/
    │   └── claude-settings/        ← 团队共享配置（CLAUDE.md 等）
    └── projects/                   ← 运行时项目目录（数据不入 git）
```

---

## 🚀 第一次部署（5 分钟）

```bash
git clone git@github.com:airacle-ai/airacle-infra.git
cd airacle-infra

# 1. 构建基础镜像（首次约 5 分钟，之后镜像缓存秒级）
cd airacle-dev && docker-compose build && cd ..

# 2. 准备首个项目目录
cd airacle
mkdir -p projects/airacle-dev/{.claude,.omnara,workspace}
cp .env.example projects/airacle-dev/.env

# 3. 启动
docker-compose up -d

# 4. 进容器
docker exec -it airacle-dev bash
```

---

## 🔑 在容器里登录工具

```bash
# 进容器后

# Claude Code 登录（弹出 OAuth URL，浏览器授权）
claude auth login --claudeai

# Omnara 登录（弹出 OAuth URL，浏览器授权后，手机端 dashboard 立刻看到这台机器）
omnara

# 验证沙箱标记
echo $IS_SANDBOX    # → 1
```

登录态自动持久化到宿主机的 `projects/airacle-dev/.claude/` 和 `.omnara/`，
**任何重启都不会丢**。

---

## ➕ 加新项目（一条命令）

```bash
cd airacle
./add-project.sh tom

# 脚本会:
#   1. 创建 projects/tom/{.claude,.omnara,workspace,.env}
#   2. 打印 docker-compose.yml 该粘贴的片段
#
# 粘贴后:
docker-compose up -d tom
```

每个项目就是一个完全独立的容器：
- 自己的 Claude 账号
- 自己的 Omnara session
- 自己的 workspace 代码
- **共享同一个镜像层**，磁盘上不重复

---

## 🛠️ 加新工具（例：装 ripgrep）

```bash
# 1. 改 Dockerfile，apt 安装那段加 ripgrep
vim airacle-dev/Dockerfile

# 2. 重建镜像
cd airacle-dev && docker-compose build

# 3. 让所有项目容器用新镜像
cd ../airacle && docker-compose up -d
```

**所有项目立刻拿到 ripgrep，登录态全保留。** 详见 [03-update-playbook.md](airacle/docs/03-update-playbook.md)。

---

## 🧠 设计要点速读（详见 docs/）

### 三层数据模型

| 层 | 内容 | 共享性 | 可变性 |
|----|------|--------|--------|
| **镜像层** | 二进制工具（claude/codex/omnara/tmux/...） | 所有容器共享 | 只读，rebuild 才能改 |
| **shared/** | 团队 CLAUDE.md、共享 prompt | 所有容器只读挂载 | 改一处全员生效 |
| **projects/`<n>`/** | 个人登录态、对话记录、代码 | 项目隔离 | 读写持久化 |

### 三句话原则

1. **凡是 bind mount 的，永远不会丢。** 项目数据全在宿主机目录下。
2. **凡是只在容器里的，重建就丢。** 临时调试可以装，长期要装到 Dockerfile。
3. **镜像更新不影响登录态。** 因为登录态根本不在镜像里。

---

## 🆘 出问题了？

先看 [docs/04-troubleshooting.md](airacle/docs/04-troubleshooting.md)，常见场景都有。

---

## 📜 工具清单（当前镜像内置）

| 工具 | 用途 |
|------|------|
| Claude Code | Anthropic 官方 AI Coding |
| Codex | OpenAI 的 AI Coding |
| Omnara | 手机端控制 + 监控 AI agent |
| Node.js 22 + npm | JS 运行时 |
| Python 3.11 | Python 运行时 |
| GitHub CLI (gh) | GitHub 操作 |
| tmux | 多会话终端 |
| git / vim / nano / curl / wget / jq / htop / fzf 等 | 常规开发工具 |

---

## License

Internal use only. Maintained by Airacle.
