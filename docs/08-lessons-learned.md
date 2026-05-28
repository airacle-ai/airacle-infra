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

## 坑 8 (扩展): Omnara 自更新循环（PATH + 健康检查的隐形配合）

> 2026-05-19 commit `efc6024` 已经修过一次 symlink 问题，但仍有残余症状。
> 2026-05-24 又复发，这次抓到了完整死循环。**这一节是上次修复的补丁**。

**症状**（复发后）：
- 容器 `Up X hours (unhealthy)`，FailingStreak 数百次
- `docker inspect ... Health` 日志全是：
  ```
  Updating Omnara CLI (0.25.6 -> 0.25.x)...
  ==> Downloading bundled artifact from: https://releases.omnara.com/...
  Health check exceeded timeout (10s)
  ```
- `omnara daemon status` 偶尔显示 running，但 30 秒后就死
- Dashboard 上机器要么不见，要么显示成宿主机 hostname

**完整死循环**（三个 bug 互相加持）：

```
[1] PATH 顺序错  →  健康检查里 `omnara --version` 走了老二进制
        ↓
[2] 老二进制 (/opt/omnara) 检测到新版本 → 触发自动更新
        ↓
[3] 自动更新过程会 stop 正在跑的 daemon
        ↓
[4] 下载 500MB+ 超过 10s 健康检查超时 → 进程被 docker SIGKILL
        ↓
[5] daemon 死了，watchdog 120s 后重启 → 再次被下次健康检查 (30s) 搞死
        ↓
[6] 无限循环（实测连续 702 次 / 37 小时）
```

**根因 1: PATH 顺序错置**

Dockerfile 里写了 `ENV PATH="/opt/omnara:$PATH"`，把"老 bootstrap 二进制目录"放到 PATH 最前。
即使 `/usr/local/bin/omnara` 这个 symlink 在 entrypoint 里被重新指向了工作版，
shell 解析 `omnara` 还是优先命中 `/opt/omnara/omnara` —— 也就是被永远冻结的镜像内老版本。

**根因 2: 健康检查命令有副作用**

`HEALTHCHECK CMD ... && omnara --version` —— `--version` 在 Omnara 老版本里 **不是纯查询**，
它会检测有没有新版本，有就触发自更新。一个本该只读的命令变成了破坏性操作。

**根因 3: 自更新会主动 kill 正在跑的 daemon**

Omnara 的 install 脚本 (`https://omnara.com/install.sh`) 替换二进制前会调 `daemon stop`。
这是合理设计——但和健康检查每 30 秒触发一次自更新组合起来就是灾难。

**正解（三连击，缺一不可）**：

1. **Dockerfile**：去掉 `ENV PATH="/opt/omnara:$PATH"`。`/usr/local/bin` 自带在 PATH 里，
   靠 entrypoint 维护的 symlink 是唯一入口。
2. **entrypoint**：首次启动后，把 `/root/.omnara/bin/omnara*` **回写一份到 `/opt/omnara/`**，
   消灭"bootstrap 版本永远停在镜像构建那一刻"这个隐患。即使 PATH 顺序万一变了也安全。
3. **健康检查**：不要直接调 `omnara --version`。改为检查 daemon 文件 / PID 存在，
   或者用 `test -x /usr/local/bin/omnara` 这种纯文件存在性检查。

**应急处理**（已经在死循环里时）：
```bash
# 1. 进容器，用绝对路径覆盖老版本
docker exec airacle-dev bash -c \
  "cp -f /root/.omnara/bin/omnara{,-claude,-codex} /opt/omnara/"

# 2. 验证 /opt/omnara/omnara --version 不再触发更新
docker exec airacle-dev /opt/omnara/omnara --version
# 期望：直接打印版本号，没有 "Updating..." 字样

# 3. 重启 daemon
docker exec -d airacle-dev /root/.omnara/bin/omnara daemon start --no-wait
```

> **⚠️ 重要：上面的 cp 只是创可贴**
> `/opt/omnara/` 是**镜像层**的一部分。`docker exec ... cp` 只写到当前容器的**可写层**。
> 一旦你 `docker-compose down && up -d`（哪怕是为了改完全不相关的配置），
> 新容器从镜像重建，`/opt/omnara/omnara` 又回到镜像里冻结的老版本 → **病又复发**。
>
> **真正的根治** = 把同步逻辑写进 entrypoint（本仓库已实现的 Step 2.5），
> 然后 `docker build` 重建镜像。光改 entrypoint.sh 不 rebuild 镜像也没用（entrypoint 是 COPY 进镜像的）。
>
> 这个反复横跳的剧情已经在 2026-05-24 上演过一次：
> 改 entrypoint.sh ✓ → 忘了 rebuild → 重启容器没用 → 又掉坑里。
> **永远记住：改了 Dockerfile / entrypoint.sh / COPY 进镜像的任何文件 → 必须 `docker build`**。

---

## 坑 9: hostname 错配 → Omnara 注册成奇怪的机器名

**症状**：
- Omnara Dashboard 里看到的机器名不是预期的（比如本来想叫 `airacle-dev`，结果显示 `airacle-slowpc`）
- 或者 Dashboard 里有个灰色的目标名（offline），同时多了个绿色的"野"名字（online，其实就是这台机器）

**根因**：
- Omnara daemon 用容器的 `hostname` 作为机器注册名上报到后端
- `docker-compose.yml` 里如果把 `hostname:` 字段写错（比如复制服务块时没改），
  容器就会以那个错误名注册
- **更隐蔽的坑**：如果容器已经创建过，光改 compose 不重建，旧的 `Config.Hostname` 还粘在容器上。
  `docker restart` 不会改 hostname，必须 `docker-compose down && up -d`

**排查**：
```bash
docker exec airacle-dev hostname                          # 容器实际 hostname
docker inspect airacle-dev --format='{{.Config.Hostname}}' # docker 配置的 hostname
grep "hostname:" docker-compose.yml                       # compose 文件里写的
```

三者应该一致。任何一个不对都会让 Omnara 注册错名字。

**正解**：
1. `docker-compose.yml` 里每个 service 的 `hostname:` 必须和 `container_name:` 一致
   （除非有特殊理由）
2. 改完 compose 后 **务必 `docker-compose down && docker-compose up -d`**，不能只 restart
3. Omnara 后端会留下旧名字的机器记录（灰色离线），可以在 Web UI 里手动删除

**机器 ID vs 机器名**：
- Omnara 后端用 UUID 标识机器，hostname 只是"显示名"
- daemon 第一次连后端时上报 hostname → 后端创建一条 (UUID, hostname) 记录
- 之后即使改 hostname，本地 `daemon.json` 里缓存的 UUID 不变，机器名也不会自动同步
- **要彻底重命名**：删 `~/.omnara/daemon.json`（保留 `creds.json`！），让 daemon 重新注册一个新 UUID

---

## 坑 10: `~/.omnara/` 数据没真正落进 volume

**症状**：
- 容器跑了好久 `/root/.omnara/creds.json` 一直存在，但 `docker volume inspect` 或宿主机对应 bind-mount 目录里**没有这个文件**
- `docker-compose down` 重建容器后，登录态丢失，要重新 `omnara auth login`

**根因**：
- 如果容器创建时**还没有**这个 volume 声明（比如 compose 是后来加的），
  Docker 会把对应路径的数据写在**容器的可写层**而不是 volume
- 之后再加 volume 也不会"追溯迁移"已有数据
- 用户感觉数据在 `/root/.omnara/`，但实际只在容器层 —— `docker rm` 立即丢失

**预防**：
- 第一次 `docker-compose up` 之前就确保 volume / bind mount 配好
- 重大改动 compose 前，**先备份关键文件出来**：
  ```bash
  docker cp airacle-dev:/root/.omnara/creds.json ./creds.backup.json
  docker cp airacle-dev:/root/.claude/ ./claude.backup/
  ```

**已经丢失的补救**：
- `creds.json` 的内容就是一个 PAT JWT，可以从 Omnara 网页（Settings → CLI tokens）重新生成
- `.claude/` 里的对话历史**真的丢了就是丢了**，没有云端备份

---

## 坑 11: `ANTHROPIC_API_KEY=占位符` 会遮蔽 OAuth 登录态

**症状**：
- 容器里已经 `claude auth login` 登录过（`.credentials.json` 里有 OAuth token）
- 但执行 `claude -p 'hi'` 报：`Invalid API key · Fix external API key`
- 神奇之处：`docker exec airacle-dev bash -c "unset ANTHROPIC_API_KEY && claude -p 'hi'"` 立刻能用

**根因**：Claude Code 的认证优先级是 **环境变量 ANTHROPIC_API_KEY > `.credentials.json` 里的 OAuth**。
只要 env 里有 `ANTHROPIC_API_KEY`（**哪怕是占位符 `sk-ant-xxxxxxxx`**），它就会拿这个 key 去打 API，
直接绕过浏览器登录拿到的 OAuth token → 报 Invalid API key。

最常见的踩坑路径：
1. 用户从 `.env.example` 复制出 `.env`，里头有 `ANTHROPIC_API_KEY=sk-ant-xxxxxxxxxxxx` 这种占位
2. 用户没填，想用浏览器 OAuth 登录
3. `docker-compose` 把整个 `.env` 注入容器
4. Claude 一启动就被占位符卡死

**正解**：
- **`.env` 模板里的 `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` 必须留空**（`KEY=` 而不是 `KEY=sk-xxx`）
- 注释里写清楚："如用浏览器登录则必须留空"
- `docker-compose.yml` 也不要 `environment: [ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}]` 这种透传写法
  —— 因为如果宿主机 shell 里有同名 env 也会被带进来。要传就走 `env_file` 一处

**通用启示**：
**占位符是危险的**。模板文件里宁可留空、加注释，也不要写假值（`sk-xxx`、`your-key-here` 等）。
任何下游消费这个变量的代码很难区分"真 key vs 占位 key"。

---

## 坑 12: `IS_SANDBOX=1` 只在 `~/.bashrc` 里，子进程拿不到

**症状**：
- `docker exec airacle-dev bash -lc 'echo $IS_SANDBOX'` → `1`（有）
- `docker exec airacle-dev bash -c 'echo $IS_SANDBOX'` → 空（没）
- `docker exec airacle-dev claude` 直接调，Claude 不认为自己在 sandbox 里，
  每个工具调用都要权限确认

**根因**：
- Dockerfile 把 `export IS_SANDBOX=1` 写进了 `~/.bashrc`
- `.bashrc` 只在**交互式非 login bash** 启动时 source（也有些情况 login bash 走 `.bash_profile`）
- `docker exec ... bash -c '...'` 是非交互 bash，**不 source `.bashrc`**
- `docker exec ... claude` 直接 exec node 进程，更不可能 source `.bashrc`
- 健康检查、daemon、和直接 `docker exec` 调的工具 **全部拿不到 `IS_SANDBOX`**

**正解**：所有真正需要全局生效的容器 env，都要写在 `docker-compose.yml` 的 `environment:` 块，
**不能只靠 `.bashrc`**：

```yaml
environment:
  - IS_SANDBOX=1            # ← 真容器 env，所有子进程都继承
  - LANG=en_US.UTF-8
  - TZ=Asia/Shanghai
```

`.bashrc` 适合放：alias、PS1、其他**只对人交互有意义**的东西。

**通用启示**：
- 容器的"环境变量"分两层：**真容器 env**（compose `environment` / Dockerfile `ENV`）和 **shell rc**（`.bashrc` 等）
- 区分原则：**子进程能否继承到** —— 真容器 env 能，shell rc 不能
- 检测：`docker exec <ct> printenv VAR_NAME` 看真容器 env，`docker exec <ct> bash -lc 'echo $VAR_NAME'` 看 shell rc

---

## 坑 14: env_file 多文件加载——空值会覆盖中央 secrets

**症状**：
- `~/.airacle/secrets.env` 里明明有 `OPENAI_API_KEY=sk-proj-real-value`
- `docker exec airacle-dev printenv OPENAI_API_KEY` 却是空
- `docker run --env-file ~/.airacle/secrets.env alpine printenv OPENAI_API_KEY` ✓ 正常

**根因**：
docker-compose 的 `env_file:` 支持列多个文件，**后者覆盖前者**。
即使后面的文件里写 `OPENAI_API_KEY=`（空值），也会把前面文件里的真值清成空。

```yaml
env_file:
  - ~/.airacle/secrets.env   # OPENAI_API_KEY=sk-proj-real
  - .env                     # OPENAI_API_KEY=    ← 把真值覆盖成空！
```

这跟"未声明 = 保持前面的值"的直觉完全相反。

**正解**：项目级 `.env` 文件**不要声明任何 API key**（连空值都不要写）。
只放项目特有的非密参数（如 `CLAUDE_MODEL`）。

**通用启示**：
- docker-compose 的多 env_file 是"逐文件 merge，每个键独立赋最后一次的值"
- 在模板（.env.example）里**强烈倾向于把不需要的键直接删掉而不是留空**
- "保留为空" 是大多数配置系统里的危险模式

---

## 坑 13 (旧): 镜像里的 gh CLI 无法和宿主机 gh CLI 共享认证

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
