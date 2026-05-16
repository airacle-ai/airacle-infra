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
    && rm -rf /var/lib/apt/lists/*

# ── GitHub CLI ───────────────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js AI tools ─────────────────────────
RUN npm install -g \
    @anthropic-ai/claude-code \
    @openai/codex \
    && npm cache clean --force

# ── Omnara (official bash installer) ─────────
# 官方脚本会装到 ~/.omnara/bin/（500+MB 二进制）
# 把二进制剥离到 /opt/omnara/，让 ~/.omnara/ 只留数据
# 这样用户的 bind mount 不会遮蔽二进制
RUN curl -fsSL https://omnara.com/install.sh | bash \
    && mv /root/.omnara/bin /opt/omnara \
    && rm -rf /root/.omnara \
    && ln -s /opt/omnara/omnara /usr/local/bin/omnara
ENV PATH="/opt/omnara:$PATH"

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

# ── Healthcheck: verify all tools present ────
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD claude --version && codex --version && omnara --version || exit 1

CMD ["/bin/bash"]
