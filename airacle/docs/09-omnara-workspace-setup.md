# 09 — Omnara Workspace 批量配置

**场景**：你有一台机器，`/workspace` 下有多个成员子目录（Jack、Kevin、Steve、Xiaolu、Share），想让每个子目录都作为独立的 Omnara Workspace 出现在客户端左侧列表，方便各自开启 AI 对话。

---

## 结论先行

Omnara CLI **没有** `workspace create` 这样的命令，但可以通过调用 **本地 Daemon API + 后端 REST API** 完全实现。整个流程已脚本化，见 [`airacle/omnara-workspace-setup/`](../omnara-workspace-setup/)。

```bash
# 一行搞定：把 /workspace 所有子目录变成独立 workspace
./airacle/omnara-workspace-setup/omnara-add-workspaces.sh /workspace
```

---

## 背景与发现过程

### Omnara 的 workspace sync 命令为什么不够用？

`omnara workspace sync -d <目录>` 是官方同步命令，但它要求该目录**已经在后端注册为 Workspace**（报错：`Workspace not found. Run a session first`）。所以不能用它来创建新 Workspace，只能用它来为已有 Workspace 开启同步。

### 真正的注册流程是什么？

通过查看 Omnara 官方 OpenAPI 文档（`https://docs.omnara.com/openapi.json`）发现两个关键端点：

**1. 本地 Daemon API — 注册目录**
```
POST http://localhost:{daemon_port}/directories
Authorization: Bearer {daemon_token}
Content-Type: application/json

{"path": "/workspace/Jack"}
```
- `daemon_port` 和 `daemon_token` 从 `~/.omnara/daemon-state.json` 读取
- 作用：让本机 Daemon 感知到该目录，并通过 WebSocket 同步给 Omnara 后端

**2. 后端 API — 创建 Workspace**
```
POST https://api.omnara.com/api/v1/workspaces/ensure
Authorization: Bearer {pat}
Content-Type: application/json

{"machine_id": "{machine_id}", "local_path": "/workspace/Jack"}
```
- `pat` 从 `~/.omnara/creds.json` 读取（key 为 `pat`）
- `machine_id` 从 `~/.omnara/daemon.json` 的 `machines` 对象的 value 读取
- 调用后 Workspace **立即出现**在客户端左侧列表，无需刷新等待

---

## 前置条件

每个目录必须是一个 **Git 仓库**（有 `.git/` 目录且至少一次 commit），否则 Omnara 会报错。脚本会自动检测并初始化。

另外，如果运行 git 时遇到 `detected dubious ownership` 报错，需要设置系统级 git 信任：
```bash
git config --system safe.directory '*'
```

---

## 配置文件位置速查

| 文件 | 内容 |
|------|------|
| `~/.omnara/creds.json` | PAT Token（`pat` 字段） |
| `~/.omnara/daemon-state.json` | Daemon 端口（`port`）和本地认证 token（`token`） |
| `~/.omnara/daemon.json` | Machine ID（`machines` 对象的 value） |

---

## 脚本使用

脚本位于 `airacle/omnara-workspace-setup/`，需在容器内执行。

```bash
# 进入容器
docker exec -it airacle-dev bash

# 批量注册（展开子目录模式）
/workspace/Share/omnara-workspace-setup/omnara-add-workspaces.sh /workspace

# 或直接在仓库目录执行
cd /path/to/airacle-infra
./airacle/omnara-workspace-setup/omnara-add-workspaces.sh /workspace/Jack /workspace/Kevin

# 查看当前状态
./airacle/omnara-workspace-setup/omnara-list-workspaces.sh
```

### 典型输出

```
============================================
  Omnara Workspace 批量配置脚本
============================================

[INFO]  Daemon 端口: 47711
[INFO]  Machine ID: b09b3e78-eae9-4675-ac1a-9f35f91e134e
[INFO]  待处理目录 (5 个):
    /workspace/Jack
    /workspace/Kevin
    /workspace/Steve
    /workspace/Xiaolu
    /workspace/Share

--------------------------------------------
处理: /workspace/Jack
[INFO]  Jack: 初始化 Git 仓库...
[OK]    Jack: Git 仓库初始化完成
[OK]    Jack: 已注册到 Daemon
[OK]    Jack: Workspace 创建成功 → ID: 98d3a7f7-c94c-46d7-a0b3-ba4209c25e8c
...

============================================
  完成！结果汇总
  目录               Workspace ID
  ---                ---
  Jack               98d3a7f7-c94c-46d7-a0b3-ba4209c25e8c
  Kevin              eb30eca7-43c6-40a0-bc92-33205ed5c030
  ...
  成功: 5 个  失败: 0 个
============================================
```

---

## 注意事项

- **幂等性**：`/api/v1/workspaces/ensure` 是 ensure 语义，同一路径重复调用不会创建重复 Workspace
- **Daemon 必须运行**：脚本开头会检查 `daemon-state.json` 是否存在，如果 Daemon 没启动需先 `omnara daemon start`
- **PAT 有效期**：如果调用后端 API 返回 401，重新登录 `omnara auth login` 刷新 token
