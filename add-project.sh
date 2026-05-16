#!/bin/bash
# ──────────────────────────────────────────────
#  airacle 新增项目脚本
#  用法: ./add-project.sh <project-name>
#
#  每个项目 = 一个完全隔离的 Docker 容器
#  共享镜像，但 .claude/.omnara/workspace 完全独立
# ──────────────────────────────────────────────
set -e

PROJECT=$1
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ -z "$PROJECT" ]; then
  echo "用法: ./add-project.sh <project-name>"
  echo "例:   ./add-project.sh eric"
  exit 1
fi

if [ -d "$BASE_DIR/projects/$PROJECT" ]; then
  echo "❌ 项目 $PROJECT 已存在: $BASE_DIR/projects/$PROJECT"
  exit 1
fi

echo "🚀 创建项目: $PROJECT"

# 1. 持久化目录
mkdir -p "$BASE_DIR/projects/$PROJECT/.claude"
mkdir -p "$BASE_DIR/projects/$PROJECT/.omnara"
mkdir -p "$BASE_DIR/projects/$PROJECT/workspace"

# 2. .env 模板
cat > "$BASE_DIR/projects/$PROJECT/.env" <<EOF
# $PROJECT 项目 API Keys（可选，也可在容器里浏览器登录）
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
EOF

echo "✅ 目录创建完成: projects/$PROJECT/"
echo ""
echo "── 把以下内容追加到 docker-compose.yml 的 services 下 ──"
cat <<EOF

  $PROJECT:
    <<: *airacle-base
    container_name: airacle-$PROJECT
    hostname: airacle-$PROJECT
    env_file: projects/$PROJECT/.env
    volumes:
      - ./shared/claude-settings:/shared/claude-settings:ro
      - ./projects/$PROJECT/.claude:/root/.claude
      - ./projects/$PROJECT/.omnara:/root/.omnara
      - ./projects/$PROJECT/workspace:/workspace
      - ~/.gitconfig:/root/.gitconfig:ro
      - ~/.ssh:/root/.ssh:ro
EOF
echo ""
echo "── 然后启动 ──"
echo "    docker-compose up -d $PROJECT"
