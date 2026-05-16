# 02 — 什么会丢、什么不会丢

**这是最重要的一份文档。每次更新镜像前请对照检查。**

## 速查表

| 物品 | 实际位置 | 镜像 rebuild 后 | 容器删除后 | 重启容器后 |
|------|----------|----------------|-----------|-----------|
| **Claude 二进制** | 镜像层 `/usr/local/bin/claude` | ⚠️ 升级到镜像里的版本 | ✅ 在 | ✅ 在 |
| **Codex 二进制** | 镜像层 `/usr/local/bin/codex` | ⚠️ 升级到镜像里的版本 | ✅ 在 | ✅ 在 |
| **Omnara 二进制** | 镜像层 `/opt/omnara/omnara` | ⚠️ 升级到镜像里的版本 | ✅ 在 | ✅ 在 |
| **Claude 登录态** | `projects/<n>/.claude/` | ✅ **保留** | ✅ **保留** | ✅ **保留** |
| **Claude 对话历史** | `projects/<n>/.claude/projects/` | ✅ **保留** | ✅ **保留** | ✅ **保留** |
| **Omnara 登录态** | `projects/<n>/.omnara/` | ✅ **保留** | ✅ **保留** | ✅ **保留** |
| **Omnara session** | `projects/<n>/.omnara/recent-sessions.json` | ✅ **保留** | ✅ **保留** | ✅ **保留** |
| **代码工作区** | `projects/<n>/workspace/` | ✅ **保留** | ✅ **保留** | ✅ **保留** |
| **API Keys (.env)** | `projects/<n>/.env` | ✅ **保留** | ✅ **保留** | ✅ **保留** |
| **团队共享文档** | `shared/claude-settings/` | ✅ **保留** | ✅ **保留** | ✅ **保留** |
| **容器内 apt install 的包** | 容器可写层 | ❌ **丢失** | ❌ **丢失** | ✅ 在 |
| **容器内 npm install -g** | 容器可写层 | ❌ **丢失** | ❌ **丢失** | ✅ 在 |
| **shell history** | 容器内 `/root/.bash_history` | ❌ **丢失** | ❌ **丢失** | ✅ 在 |

## 核心原则

> **凡是宿主机有 bind mount 的，永远不会丢。**
> **凡是只在容器里的，重建容器就丢。**

## "我想装个新工具，该装哪里？"

### 方案 A：所有项目都该有 → 装进镜像
```dockerfile
# 在 airacle-dev/Dockerfile 加一行
RUN apt-get install -y <tool>
```
然后 `docker-compose build` + `docker-compose up -d`，
**所有项目登录态保留**，新工具立即生效。

### 方案 B：只有某个项目需要 → 装在 workspace 里
进容器后用项目本地安装（如 `npm install` 在 workspace 里，
或 `pip install --user` 到 bind mount 的目录里）。

### 方案 C：临时试用 → 直接装在容器里
进容器 `apt install xxx`，但要知道容器删除就没了。
试用 OK，长期依赖请走方案 A。

## 关于"升级 Claude Code 会不会影响登录态"

**完全不会**。逻辑链：
1. Claude Code 二进制在镜像里 → rebuild 镜像 → 二进制更新到新版本
2. Claude 登录态在 `projects/<n>/.claude/auth.json` → 这个目录是宿主机 bind mount → 跟镜像无关
3. 新版二进制启动，读取宿主机上的旧登录态 → 继续工作

唯一可能出问题的场景：Claude Code 大版本升级改了登录态文件格式。
这种情况极少，且 Anthropic 通常会做向后兼容。

## 关于"用户在容器里改了 ~/.bashrc 会丢"

**会丢**。`/root/.bashrc` 不在 bind mount 范围内。
如果某个 alias / 环境变量值得长期保留：
- 加到 Dockerfile 的 `RUN echo ... >> /root/.bashrc`（所有项目生效）
- 或者用户在自己的 workspace 里维护一个 `.envrc` 用 direnv 加载（仅自己项目生效）
