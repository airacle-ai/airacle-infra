# 03 — 升级 / 维护操作手册

## 场景 1：加一个新工具（apt / npm / curl 装的）

例：想给所有容器加一个 `ripgrep`。

```bash
cd docker/airacle-dev
# 编辑 Dockerfile，在系统包那段加 ripgrep
vim Dockerfile

# 重新构建镜像
docker-compose build      # 或 docker build -t airacle-dev:latest .
```

然后让所有项目容器用新镜像：

```bash
cd docker/airacle
docker-compose up -d      # docker-compose 会自动重启用新镜像的服务
```

**影响范围**：
- ✅ 所有项目容器自动拿到 ripgrep
- ✅ 所有项目的 .claude/.omnara/workspace 完全保留
- ⏱️ 每个容器重启约 5 秒，期间该容器不可用
- ⚠️ 容器内之前临时 `apt install` 的东西会丢（如果有的话）

## 场景 2：升级 Claude Code / Codex / Omnara

工具是 `npm install -g latest` 或 `curl ... | bash` 装的，
rebuild 镜像就会自动拉最新版：

```bash
cd docker/airacle-dev
docker-compose build --no-cache   # --no-cache 强制重新拉最新

cd ../airacle
docker-compose up -d
```

**登录态不会丢**（在 bind mount 里）。

## 场景 3：加一个新项目

```bash
cd docker/airacle
./add-project.sh <name>          # 自动建目录 + 打印 compose 片段
# 把片段粘进 docker-compose.yml
docker-compose up -d <name>      # 启动（秒级，镜像已存在）
```

## 场景 4：临时调试，进容器装个东西

```bash
docker exec -it airacle-dev /bin/bash
apt install <whatever>           # 立即可用，但容器重建就丢
```

如果发现长期需要，请走场景 1 把它加进 Dockerfile。

## 场景 5：删除一个项目

```bash
cd docker/airacle
docker-compose stop <name>
docker-compose rm -f <name>

# 决定是否清理宿主机数据
# rm -rf projects/<name>          ⚠️ 这会真的把代码+登录态都删了
```

## 场景 6：完全重启所有容器（保留登录态）

```bash
cd docker/airacle
docker-compose down               # 全部停止
docker-compose up -d              # 全部启动
# 所有 .claude/.omnara/workspace 都保留
```

## 场景 7：镜像出问题了，要回滚

**强烈建议**每次大改 Dockerfile 前打个 tag：

```bash
docker tag airacle-dev:latest airacle-dev:backup-$(date +%Y%m%d)
```

万一新镜像有问题：

```bash
docker tag airacle-dev:backup-20260516 airacle-dev:latest
cd docker/airacle
docker-compose up -d              # 回到旧版本
```

## 维护节奏建议

| 频率 | 操作 |
|------|------|
| 每周 | rebuild 镜像（拉最新 Claude/Codex/Omnara） |
| 加新工具时 | 修 Dockerfile + rebuild + 文档更新 |
| 加新项目时 | `./add-project.sh` + 改 compose |
| 季度 | 检查 base image (node:22-bookworm) 是否要换主版本 |

## 关键命令速查

```bash
# 看所有 airacle 容器
docker ps --filter "name=airacle"

# 看某个容器日志
docker logs airacle-dev

# 看镜像大小（确认共享）
docker images airacle-dev

# 看磁盘占用（项目数据）
du -sh docker/airacle/projects/*
```
