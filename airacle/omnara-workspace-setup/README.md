# Omnara 批量 Workspace 配置脚本

将本地子目录批量注册为 Omnara Workspace，注册后在 Omnara 客户端左侧列表即可看到并开启对话。

## 快速使用

```bash
# 把某个父目录下所有子目录都变成独立 workspace
./omnara-add-workspaces.sh /workspace

# 或指定具体目录
./omnara-add-workspaces.sh /workspace/Jack /workspace/Kevin /workspace/NewPerson

# 查看当前所有已注册的 workspace
./omnara-list-workspaces.sh
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `omnara-add-workspaces.sh` | 主脚本：批量初始化 Git + 注册 Daemon + 创建 Workspace |
| `omnara-list-workspaces.sh` | 查询脚本：列出 Daemon 目录和后端 Workspace 状态 |

## 原理

Omnara CLI 本身没有 `workspace create` 命令，但可以通过以下三步实现同等效果：

1. **初始化 Git 仓库** — Omnara workspace 必须是 Git 仓库
2. **注册到本地 Daemon** — `POST localhost:{port}/directories`，让客户端感知到该目录
3. **调用后端 API** — `POST https://api.omnara.com/api/v1/workspaces/ensure`，在服务端创建 Workspace 并绑定到当前机器，完成后客户端左侧列表立即出现

## 依赖

- Omnara CLI 已安装（`/opt/omnara/omnara`）
- 已登录（`~/.omnara/creds.json` 存在）
- Omnara Daemon 正在运行（`omnara daemon start`）
- `python3`、`curl`、`git`

详细原理见 [09-omnara-workspace-setup.md](../docs/09-omnara-workspace-setup.md)
