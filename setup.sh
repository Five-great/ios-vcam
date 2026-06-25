#!/bin/bash

# VCam 项目初始化脚本
# 用法: bash setup.sh [你的GitHub用户名]

set -e

USERNAME=${1:-$(whoami)}
REPO_NAME="VCam"

echo "🚀 初始化 VCam 项目..."

# 检查是否在 VCam 目录
if [ ! -f "Makefile" ]; then
    echo "❌ 请在 VCam 目录下运行此脚本"
    exit 1
fi

# 初始化 Git
if [ ! -d ".git" ]; then
    echo "📦 初始化 Git 仓库..."
    git init
    git add .
    git commit -m "init: VCam virtual camera tweak"
else
    echo "✓ Git 仓库已存在"
fi

# 创建 GitHub 仓库（需要 gh CLI）
if command -v gh &> /dev/null; then
    echo "🔗 创建 GitHub 仓库..."
    gh repo create "$USERNAME/$REPO_NAME" --public --source=. --push
    echo "✅ 仓库已创建并推送！"
else
    echo "⚠️  未安装 GitHub CLI (gh)"
    echo "请手动操作："
    echo "1. 在 GitHub 上创建仓库：https://github.com/new"
    echo "   仓库名：$REPO_NAME"
    echo "   不要初始化 README/license/gitignore"
    echo ""
    echo "2. 运行以下命令："
    echo "   git remote add origin https://github.com/$USERNAME/$REPO_NAME.git"
    echo "   git branch -M main"
    echo "   git push -u origin main"
fi

echo ""
echo "📝 下一步："
echo "1. 打开 https://github.com/$USERNAME/$REPO_NAME/actions"
echo "2. 等待编译完成（约 3-5 分钟）"
echo "3. 在 Artifacts 下载 VCam-dylib 或 VCam-deb"
