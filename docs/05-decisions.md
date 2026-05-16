# 05 — 设计决策记录

记录"为什么这样做，而不是那样做"。避免未来反复纠结同一个问题。

## D1: 用"项目"作为隔离单位，而不是"用户"

**决策**：每个 Docker 容器对应一个"项目"，不是一个"人"。

**理由**：
- 一个真人可能要管 5-6 个 Claude 账号
- 一个项目可能是一组紧密相关的代码 + 上下文 + 账号绑定
- 用项目隔离更符合实际工作流

**代价**：如果两个项目要彻底共享 Claude 账号，得手动复制 .claude/。

## D2: Omnara 二进制从 ~/.omnara 移到 /opt/omnara

**决策**：在 Dockerfile 里强制把 Omnara 二进制移出用户家目录。

**理由**：
- Omnara 官方安装脚本把二进制 (500MB+) 和数据混放 `~/.omnara/`
- 如果 bind mount `~/.omnara/`，宿主机空目录会遮蔽掉二进制
- 移到 `/opt/omnara` 后，`~/.omnara/` 只剩用户数据，bind mount 干净

**代价**：每次 Omnara 升级要确认它的安装脚本路径没变。

## D3: 不锁工具版本（npm latest / curl latest）

**决策**：Dockerfile 里不写 `claude-code@2.1.143`，写 latest。

**理由**：
- Claude Code/Codex/Omnara 都是 SaaS 工具，紧跟新版本才有最佳体验
- 版本锁定可能导致协议不兼容（客户端太老连不上服务）

**代价**：rebuild 不能完美复现旧版本。需要时用 docker tag 备份镜像（见 03-update-playbook 场景 7）。

## D4: network_mode: host 而不是 bridge

**决策**：所有容器用宿主机网络。

**理由**：
- Omnara 需要和云端建持久连接，bridge 模式有时会出问题
- 不需要管端口映射
- 反正每个容器都是自己人在用，安全性影响可忽略

**代价**：容器内服务直接占宿主机端口，多项目跑 web server 要错开端口。

## D5: 不预装 Ollama / 不内嵌 LLM 运行时

**决策**：不在镜像里塞 Ollama 或其他本地 LLM。

**理由**：
- 用户明确说不要
- Ollama 应该作为独立 sidecar 服务（多容器共享一份模型）
- 镜像保持轻量

**未来如需**：加一个独立的 `ollama` service 到 compose，所有 airacle 容器通过 `OLLAMA_HOST=http://ollama:11434` 连接。

## D6: API Key 走 .env，不走 docker secret

**决策**：每个项目 `projects/<name>/.env` 存 API Key。

**理由**：
- 简单直观，单机部署够用
- docker secret 是 swarm 模式的功能，单机用太重

**代价**：`.env` 是明文。如果未来要多机分发，得换成 secret。

## D7: 不用 named volume，用 bind mount

**决策**：`.claude/.omnara/workspace` 都是宿主机目录 bind mount，不是 Docker named volume。

**理由**：
- bind mount 在宿主机文件系统里直接可见，方便备份/查看/编辑
- named volume 藏在 `/var/lib/docker/volumes/`，调试不便
- 单机场景下两者性能没差别

**代价**：跨机迁移时 bind mount 路径要保持一致。

## D8: 团队共享走只读挂载，不走 git pull

**决策**：`shared/claude-settings/` 通过宿主机 bind mount 给所有容器，不是每个容器 git clone。

**理由**：
- 改一处所有容器立即生效
- 不需要每个容器都跑 git
- 维护者直接在宿主机改文件

**代价**：宿主机这个目录最好自己是个 git repo（未来加），方便版本管理。
