# Airacle Docker 开发环境 — 维护文档

这个文件夹是整个 Airacle Docker 开发环境的**单一事实来源 (Single Source of Truth)**。
后续无论是人类维护者还是 AI agent，看完这里就能完整接手。

## 阅读顺序建议

### 🚀 想用起来
1. [07-onboarding-new-machine.md](./07-onboarding-new-machine.md) — 10 分钟部署一台新机器
2. [06-login-procedures.md](./06-login-procedures.md) — Claude / Omnara 登录方式

### 🧠 想理解架构
1. [01-architecture.md](./01-architecture.md) — 整体架构、设计原则
2. [02-what-persists.md](./02-what-persists.md) — **★ 必读** 每个文件/目录在哪、什么会丢
3. [05-decisions.md](./05-decisions.md) — 设计决策记录（为什么 X 不用 Y）

### 🔧 想维护
1. [03-update-playbook.md](./03-update-playbook.md) — 升级镜像、加工具、回滚
2. [04-troubleshooting.md](./04-troubleshooting.md) — 故障排查
3. [08-lessons-learned.md](./08-lessons-learned.md) — **★ 必读** 踩坑实录

## 文档总览

| 文档 | 内容 |
|------|------|
| [01-architecture.md](./01-architecture.md) | 整体架构、三层数据模型、关键设计决策 |
| [02-what-persists.md](./02-what-persists.md) | 每个文件/目录在哪、镜像 rebuild 后会不会丢 |
| [03-update-playbook.md](./03-update-playbook.md) | 升级/加工具/加项目/回滚操作手册 |
| [04-troubleshooting.md](./04-troubleshooting.md) | 8 个常见故障场景与解法 |
| [05-decisions.md](./05-decisions.md) | 设计决策记录（D1-D8） |
| [06-login-procedures.md](./06-login-procedures.md) | Claude Code + Omnara 登录的正确姿势 |
| [07-onboarding-new-machine.md](./07-onboarding-new-machine.md) | 新机器 10 分钟开通 + 批量部署思路 |
| [08-lessons-learned.md](./08-lessons-learned.md) | 8 个踩过的坑与正解，好镜像 checklist |

## 一句话总结

> 一个 `airacle-dev` 镜像（共享所有工具），N 个项目容器（隔离所有状态），
> 工具更新只需重建镜像 + 重启容器，**登录态/对话记录永不丢失**。
