# ─────────────────────────────────────────────
#  airacle-dev
#  AI coding environment: Claude Code + Codex + Omnara
#  Base: node:22-bookworm (locally cached)
# ─────────────────────────────────────────────
FROM node:22-bookworm

LABEL maintainer="airacle-dev"
LABEL description="AI dev environment with Claude Code, Codex, Omnara"

# ── System packages ──────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Python runtime
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    # Dev essentials
    git \
    curl \
    wget \
    vim \
    nano \
    jq \
    unzip \
    build-essential \
    ca-certificates \
    gnupg \
    # Shell niceties
    bash-completion \
    less \
    htop \
    tmux \
    # Media & search CLI
    ffmpeg \
    ripgrep \
    fd-find \
    bat \
    && rm -rf /var/lib/apt/lists/* \
    # Debian 把 fd-find / bat 装成 fdfind / batcat —— 补上更常用的名字
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# ── GitHub CLI ───────────────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js AI tools + 常用 SDK + Cloudflare wrangler ─────
# claude-code / codex: CLI
# @anthropic-ai/sdk / openai: 给项目代码用的 SDK（全局装方便临时脚本 import）
# axios / dotenv / zod: Node 高频库
# wrangler: Cloudflare Workers / Pages 部署 CLI
RUN npm install -g \
    @anthropic-ai/claude-code \
    @openai/codex \
    @anthropic-ai/sdk \
    openai \
    axios \
    dotenv \
    zod \
    wrangler \
    && npm cache clean --force

# 让 require() 能找到全局装的模块（默认不会去 /usr/local/lib/node_modules 找）
# 项目本地 node_modules 仍然优先，所以不会污染 npm install --save 的行为
ENV NODE_PATH=/usr/local/lib/node_modules

# ── Python AI/Web 基础包 ─────────────────────
# --break-system-packages: bookworm 默认禁止 pip 装系统级；
# 这是一个一次性受控镜像，明确知道在干什么，所以打开
RUN pip3 install --no-cache-dir --break-system-packages \
    anthropic \
    openai \
    requests \
    httpx \
    python-dotenv \
    pydantic \
    fastapi \
    uvicorn

# ── yt-dlp 通过 pipx（隔离不污染系统 Python）──
RUN pipx ensurepath \
    && PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install yt-dlp

# ── Omnara (official bash installer) ─────────
# 官方脚本会装到 ~/.omnara/bin/（500+MB 二进制）
# 把二进制剥离到 /opt/omnara/，让 ~/.omnara/ 只留数据
# 这样用户的 bind mount 不会遮蔽二进制
#
# ⚠️  不要把 /opt/omnara 加进 PATH！原因详见 docs/08-lessons-learned.md 坑 8。
#     简短版：/opt/omnara/omnara 是镜像内的"冻结版"，被直接调用时会触发自更新，
#     这个自更新过程会 kill 正在跑的 daemon，造成死循环。
#     唯一入口是 /usr/local/bin/omnara（entrypoint 维护，指向工作版）。
RUN curl -fsSL https://omnara.com/install.sh | bash \
    && mv /root/.omnara/bin /opt/omnara \
    && rm -rf /root/.omnara \
    && ln -sf /opt/omnara/omnara /usr/local/bin/omnara

# ── Shell config ─────────────────────────────
RUN echo '\n# ── airacle-dev env ──'     >> /root/.bashrc \
    && echo 'export IS_SANDBOX=1'        >> /root/.bashrc \
    && echo '\n# ── airacle-dev aliases ──' >> /root/.bashrc \
    && echo 'alias cc="claude"'          >> /root/.bashrc \
    && echo 'alias ll="ls -la --color"'  >> /root/.bashrc \
    && echo 'alias gs="git status"'      >> /root/.bashrc \
    && echo 'alias gd="git diff"'        >> /root/.bashrc \
    && echo 'export PS1="\[\e[36m\][airacle-dev]\[\e[0m\] \w \$ "' >> /root/.bashrc

# ── Workspace ────────────────────────────────
WORKDIR /workspace

# ── Entrypoint: auto-start Omnara daemon if logged in ──
COPY entrypoint.sh /usr/local/bin/airacle-entrypoint.sh
RUN chmod +x /usr/local/bin/airacle-entrypoint.sh

# ── Healthcheck: verify tool binaries present ────
# ⚠️  绝不要在健康检查里调 `omnara --version` —— 老版本会触发自更新，
#     30 秒一次的健康检查 + 自更新 kill daemon = 死循环。
#     详见 docs/08-lessons-learned.md 坑 8。
#     这里只检查二进制是否存在 + claude/codex 的 --version（这两个是 npm 包，--version 无副作用）。
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD claude --version && codex --version && test -x /usr/local/bin/omnara || exit 1

ENTRYPOINT ["/usr/local/bin/airacle-entrypoint.sh"]
CMD ["/bin/bash"]
