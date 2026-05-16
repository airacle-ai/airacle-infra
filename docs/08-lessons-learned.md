# 08 — 经验沉淀（踩坑实录）

记录搭建过程中所有踩过的坑、走过的弯路、和最终的正解。
**新人/AI agent 接手前必读**，避免重复造轮子或重复踩雷。

---

## 坑 1: pipx install omnara 装的是旧版

**症状**：装完 `omnara` 命令存在，但启动时疯狂索要 key，没 key 就用不了。

**原因**：PyPI 上 `omnara` 是 1.x 老版，新版 Omnara CLI 走的是官方 bash installer。

**正解**：
```dockerfile
RUN curl -fsSL https://omnara.com/install.sh | bash
```

会装 0.25+ 的新版，走浏览器 OAuth，无需手动输 key。

---

## 坑 2: Omnara 二进制和数据在同一目录

**症状**：bind mount `~/.omnara/` 后，进容器 `omnara` 命令找不到。

**原因**：官方 installer 把 500MB+ 二进制和用户数据都塞 `~/.omnara/`。
bind mount 把宿主机空目录挂上去，遮蔽了二进制。

**正解**：在 Dockerfile 里**剥离**二进制到 `/opt/omnara/`：
```dockerfile
RUN curl -fsSL https://omnara.com/install.sh | bash \
    && mv /root/.omnara/bin /opt/omnara \
    && rm -rf /root/.omnara \
    && ln -s /opt/omnara/omnara /usr/local/bin/omnara
```

`~/.omnara/` 留给用户数据（creds、sessions），随便 bind mount。

**通用启示**：**任何把代码和数据混放同一目录的软件，装进镜像前都要"剥离"**。

---

## 坑 3: 登录后机器不出现在 Omnara Dashboard

**症状**：`omnara auth login` 成功，但 https://omnara.com 下拉列表里没这台机器。

**原因**：登录只存了凭证，**不会自动注册机器**。Dashboard 上的机器是 daemon 主动上报的。

**正解**：
- 手动起：`omnara daemon start`
- **更好**：写进 entrypoint 自动起（见本仓库 `airacle-dev/entrypoint.sh`）

---

## 坑 4: 容器重启后装的东西不见了

**症状**：`docker exec ... apt install xxx` 装好了，重启容器 `xxx` 没了。

**原因**：容器内的可写层会随容器销毁而消失。`docker restart` 不销毁，但 `docker-compose down/up` 会重建。

**正解**：
- 长期工具 → 写进 Dockerfile，rebuild 镜像
- 临时工具 → 容器内装，知道会丢
- 项目专用 → 装在 `/workspace/` 里（bind mount 持久化）

详见 [02-what-persists.md](./02-what-persists.md)。

---

## 坑 5: docker-compose v1 与新 Docker 守护进程不兼容

**症状**：`docker-compose up -d` 报错 `KeyError: 'ContainerConfig'`。

**原因**：docker-compose 1.29.2 + Docker 29.x 的已知 bug。

**临时解法**：手动用 docker 命令重建容器：
```bash
docker rm -f airacle-dev
docker-compose up -d         # 创建路径下次会顺
```

**根治**：升级 docker-compose v2（`docker compose` 是子命令）：
```bash
# Debian/Ubuntu
sudo apt install docker-compose-v2
# 然后用 `docker compose` 替代 `docker-compose`
```

---

## 坑 6: SSH 断开 → 交互式登录进程死掉

**症状**：跑 `omnara auth login` 时断开 SSH，回来发现进程没了，得重新走 OAuth。

**正解**：**所有长时间交互流都跑在 tmux 里**。

```bash
ssh slowpc-linux
tmux new -s setup        # 一定要先 tmux！
docker exec -it airacle-dev omnara auth login
# 即使 SSH 断了，进程仍活着
# 回来后:
tmux attach -t setup
```

这条规则适用于：
- OAuth 登录流程
- 长任务的 Claude Code session
- 任何"启动后不能死"的进程

---

## 坑 7: API Key 不小心进了 git

**症状**：往 GitHub push 后才发现 commit 里有 token。

**预防**：本仓库 `.gitignore` 已配置：
```
airacle/projects/*/        # 用户数据全部忽略
**/.env                    # 任何 .env 都忽略
```

**已经泄露的补救**：
1. **立即在 GitHub revoke 那个 token**（不要只删 commit，链上记录还在）
2. 重新生成
3. （可选）用 `git filter-repo` 清历史

---

## 坑 8: 镜像里的 gh CLI 无法和宿主机 gh CLI 共享认证

**症状**：宿主机 gh 登录了，进容器 `gh auth status` 显示未登录。

**原因**：gh 认证存在 `~/.config/gh/`，没在 bind mount 范围内。

**正解（如果想共享认证）**：在 docker-compose volumes 里加：
```yaml
- ~/.config/gh:/root/.config/gh:ro
```

**但更推荐**：在容器里独立 `gh auth login`，认证存在 `projects/<n>/.config/gh/`
（前提是把这个路径加进 bind mount）。

---

## 经验总结：好镜像的 Checklist

设计一个能批量部署的开发镜像，按这个清单审视：

- [ ] **代码与数据分离**：所有有状态的工具，二进制都不放 `$HOME` 下
- [ ] **可写状态在 bind mount**：登录态、配置、历史记录都在宿主机持久化
- [ ] **entrypoint 自愈**：检测到登录凭证就自动启动后台服务（daemon）
- [ ] **`.gitignore` 严密**：项目数据、`.env`、token 一律不入 git
- [ ] **健康检查**：`HEALTHCHECK` 验证关键工具可用
- [ ] **文档完备**：登录、升级、故障、决策有专章
- [ ] **可重现**：从零开始按 README 能跑通

本仓库（airacle-infra）已经满足以上全部。

---

## AI Agent 接手前的速读路径

1. [README](../README.md) — 1 分钟知道这是什么
2. [01-architecture.md](./01-architecture.md) — 5 分钟懂整体设计
3. [02-what-persists.md](./02-what-persists.md) — **必读**，理解"什么会丢"
4. [本文档] — **必读**，避免重复踩坑
5. 其他文档按需查
