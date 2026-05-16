# 04 — 故障排查

## Q1: 进容器后 `omnara` 命令找不到

**症状**：`bash: omnara: command not found`

**原因**：可能是镜像没装好，或 `~/.omnara` 被错误挂载遮蔽。

**排查**：
```bash
docker exec airacle-dev which omnara
docker exec airacle-dev ls /opt/omnara/   # 应该有 omnara 二进制
docker exec airacle-dev ls -la /usr/local/bin/omnara   # 应该是 symlink
```

如果 `/opt/omnara` 是空的，说明镜像有问题，rebuild：
```bash
cd docker/airacle-dev && docker-compose build --no-cache
```

## Q2: 重启容器后 Claude 要求重新登录

**症状**：之前登过的 Claude，重启容器后又让登录。

**原因**：`.claude/` 没正确 bind mount。

**排查**：
```bash
# 1. 检查宿主机目录里有没有 auth 相关文件
ls -la docker/airacle/projects/<name>/.claude/

# 2. 进容器看挂载点
docker exec airacle-dev mount | grep claude
```

如果宿主机目录是空的但你之前明明登录过，说明登录时 .claude/ 是写到容器的可写层去了——
确认 docker-compose.yml 里这个项目的 volumes 段有：
```yaml
- ./projects/<name>/.claude:/root/.claude
```

## Q3: 镜像 rebuild 后所有容器都打不开

**症状**：`docker-compose up -d` 失败。

**排查**：
```bash
docker logs airacle-dev      # 看具体错误
docker images airacle-dev    # 确认镜像存在
```

**回滚**：见 03-update-playbook 场景 7。

## Q4: 磁盘空间不够

**先看占用大头**：
```bash
docker system df                    # Docker 总体
du -sh docker/airacle/projects/*    # 各项目数据
du -sh docker/airacle-dev/          # 镜像构建上下文
```

**清理**：
```bash
docker image prune                  # 删悬空镜像
docker builder prune                # 删构建缓存
docker container prune              # 删停止的容器
```

## Q5: 容器健康检查显示 unhealthy

**排查**：
```bash
docker inspect airacle-dev --format='{{json .State.Health}}' | jq
```

健康检查是 `claude --version && codex --version && omnara --version`。
任何一个失败容器就 unhealthy。但容器本身仍然能用，只是状态显示问题。

## Q6: 多个容器同时跑，端口冲突

**症状**：第二个项目启动失败，端口被占用。

**原因**：`network_mode: host`，多个容器抢宿主机同一个端口。

**解法**：
- 在容器里跑服务时手动指定不同端口
- 或在该项目的 compose 里改回 bridge 模式 + 端口映射

## Q7: 在容器里 `git push` 失败

**症状**：`Permission denied (publickey)` 或类似。

**原因**：SSH key 没正确挂载，或 key 在容器里权限不对。

**排查**：
```bash
docker exec airacle-dev ls -la /root/.ssh/
docker exec airacle-dev ssh -T git@github.com
```

如果是权限问题，宿主机上确认 `~/.ssh/` 是 700，私钥是 600。

## Q8: 我想知道现在镜像里到底装了什么

```bash
docker exec airacle-dev bash -c "
  echo '── 系统包 ──'
  dpkg -l | tail -20
  echo '── npm 全局包 ──'
  npm list -g --depth=0
  echo '── pip 包 ──'
  pip list 2>/dev/null
  echo '── /opt 下的工具 ──'
  ls /opt/
"
```
