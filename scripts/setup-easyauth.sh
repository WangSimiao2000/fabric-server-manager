#!/bin/bash
# 下载并安装 EasyAuth 登录认证 mod
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAME_DIR="$(dirname "$SCRIPT_DIR")/GameFile"
MODS_DIR="$GAME_DIR/mods"
EASYAUTH_URL="https://cdn.modrinth.com/data/aZj58GfX/versions/NocjXnNX/easyauth-mc1.21.5-3.3.3.jar"
EASYAUTH_FILE="easyauth-mc1.21.5-3.3.3.jar"

echo "=== 安装 EasyAuth 登录认证 Mod ==="

if [ -f "$MODS_DIR/$EASYAUTH_FILE" ]; then
    echo "EasyAuth 已存在，跳过下载"
    exit 0
fi

if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    echo "错误: 需要 curl 或 wget"
    exit 1
fi

echo "下载 EasyAuth 3.3.3 (MC 1.21.5)..."
if command -v curl &>/dev/null; then
    curl -L -o "$MODS_DIR/$EASYAUTH_FILE" "$EASYAUTH_URL"
else
    wget -O "$MODS_DIR/$EASYAUTH_FILE" "$EASYAUTH_URL"
fi

if [ -s "$MODS_DIR/$EASYAUTH_FILE" ]; then
    echo "安装成功: $EASYAUTH_FILE"
    echo ""
    echo "首次启动后请参考: docs/EASYAUTH_GUIDE.md 完成配置"
else
    echo "下载失败，请手动下载:"
    echo "  $EASYAUTH_URL"
    rm -f "$MODS_DIR/$EASYAUTH_FILE"
    exit 1
fi
