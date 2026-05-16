#!/bin/bash
# =============================================================================
# Airacle Team — 工作目录初始化脚本
# 用途：批量创建团队成员工作目录 + 共享目录结构
# 用法：bash init-workspace.sh [BASE_DIR]
#       BASE_DIR 默认为 /workspace，可通过参数指定其他路径
# =============================================================================

BASE_DIR="${1:-/workspace}"

echo "========================================"
echo "  Airacle Team 工作目录初始化"
echo "  根目录：$BASE_DIR"
echo "========================================"

# ---------- 团队成员工作目录 ----------
MEMBERS=(Steve Jack Kevin Xiaolu)

echo ""
echo "[ 1/2 ] 创建团队成员工作目录..."
for member in "${MEMBERS[@]}"; do
    TARGET="$BASE_DIR/$member"
    if [ -d "$TARGET" ]; then
        echo "  ⚠️  已存在，跳过：$TARGET"
    else
        mkdir -p "$TARGET"
        echo "  ✅  已创建：$TARGET"
    fi
done

# ---------- 共享目录 ----------
SHARED_DIRS=(
    "Share/Code"
    "Share/Data"
)

echo ""
echo "[ 2/2 ] 创建共享目录..."
for dir in "${SHARED_DIRS[@]}"; do
    TARGET="$BASE_DIR/$dir"
    if [ -d "$TARGET" ]; then
        echo "  ⚠️  已存在，跳过：$TARGET"
    else
        mkdir -p "$TARGET"
        echo "  ✅  已创建：$TARGET"
    fi
done

# ---------- 结果预览 ----------
echo ""
echo "========================================"
echo "  初始化完成！目录结构如下："
echo "========================================"
if command -v tree &>/dev/null; then
    tree -L 2 "$BASE_DIR" --dirsfirst
else
    find "$BASE_DIR" -maxdepth 2 -type d | sort | sed "s|$BASE_DIR||" | sed 's|^/||' | sed 's|/|  └── |g' | sed 's|^|  |'
fi

echo ""
echo "Done. 如需重新指定根目录，运行：bash init-workspace.sh /your/path"
