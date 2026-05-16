# 01 — 架构总览

## 物理目录结构

```
docker/
├── airacle-dev/                  ← 镜像构建源（Dockerfile）
│   ├── Dockerfile
│   └── docker-compose.yml        （旧的，已弃用，可删）
│
└── airacle/                      ← 运行时管理目录
    ├── docker-compose.yml        ← 管理所有项目容器
    ├── add-project.sh            ← 一键加项目
    ├── docs/                     ← 本文件夹
    ├── shared/
    │   └── claude-settings/      ← 团队共享只读配置
    └── projects/
        └── <project-name>/
            ├── .env              ← 项目级 API Keys
            ├── .claude/          ← 项目独立 Claude 登录态 + 对话
            ├── .omnara/          ← 项目独立 Omnara session
            └── workspace/        ← 项目代码
```

## 三层模型

```
┌──────────────────────────────────────────────────────────┐
│  Layer 1: 镜像 (airacle-dev:latest)                       │
│  - 二进制: claude, codex, omnara, node, python, tmux, gh │
│  - 位置:   全部在镜像只读层                                │
│  - 共享:   所有容器共用同一份（Docker 自动去重）           │
│  - 变更:   只能通过 rebuild 镜像                          │
└──────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────┐
│  Layer 2: 团队共享 (shared/)                              │
│  - 内容:   CLAUDE.md, 团队 prompt, 团队脚本               │
│  - 挂载:   只读 (ro)                                      │
│  - 路径:   /shared/claude-settings/                       │
│  - 变更:   改宿主机文件即可，立即对所有容器生效            │
└──────────────────────────────────────────────────────────┘
┌──────────────────────────────────────────────────────────┐
│  Layer 3: 项目隔离 (projects/<name>/)                     │
│  - 内容:   Claude 登录态、Omnara session、代码、对话记录  │
│  - 挂载:   读写 (rw)                                      │
│  - 隔离:   项目间完全独立                                  │
│  - 持久:   重启/删除容器都不丢                            │
└──────────────────────────────────────────────────────────┘
```

## 关键设计决策

### 1. 为什么用"项目"而不是"用户"作为隔离单位
一个真人可能要管理多个 Claude 账号（5-6 个）。用项目隔离比用人隔离更灵活：
- 一个项目 = 一个容器 = 一个独立账号上下文
- 同一个人可以跑多个项目容器，每个登不同账号

### 2. 为什么 Omnara 二进制要从 ~/.omnara 移到 /opt/omnara
Omnara 官方安装脚本把**二进制 (500MB+) 和数据**都放 `~/.omnara/`。
如果直接 bind mount `~/.omnara/`，宿主机的空目录会遮蔽掉二进制。
所以 Dockerfile 里做了一步剥离：
```dockerfile
RUN curl -fsSL https://omnara.com/install.sh | bash \
    && mv /root/.omnara/bin /opt/omnara \
    && rm -rf /root/.omnara \
    && ln -s /opt/omnara/omnara /usr/local/bin/omnara
```

### 3. 为什么 network_mode: host
Omnara 需要直接和云端通信，host 网络最简单可靠。
也避免了端口映射的复杂性。

### 4. 为什么不在 Dockerfile 里固定工具版本
Claude Code / Codex / Omnara 都是 SaaS 工具，需要紧跟官方版本。
锁版本反而会让我们错过功能/安全更新。
依靠 npm/curl 拉 latest 是合理的取舍。
