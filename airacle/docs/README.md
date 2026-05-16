# Airacle Docker 开发环境 — 维护文档

这个文件夹是整个 Airacle Docker 开发环境的**单一事实来源 (Single Source of Truth)**。
后续无论是人类维护者还是 AI agent，看完这里就能完整接手。

## 文档索引

| 文档 | 内容 |
|------|------|
| [01-architecture.md](./01-architecture.md) | 整体架构、设计原则、为什么这样设计 |
| [02-what-persists.md](./02-what-persists.md) | **每个文件/目录在哪里、更新镜像后会不会丢** |
| [03-update-playbook.md](./03-update-playbook.md) | 如何升级镜像、加新工具、回滚 |
| [04-troubleshooting.md](./04-troubleshooting.md) | 常见问题排查 |
| [05-decisions.md](./05-decisions.md) | 设计决策记录（为什么 X 不用 Y） |

## 一句话总结

> 一个 `airacle-dev` 镜像（共享所有工具），N 个项目容器（隔离所有状态），
> 工具更新只需重建镜像 + 重启容器，**登录态/对话记录永不丢失**。
