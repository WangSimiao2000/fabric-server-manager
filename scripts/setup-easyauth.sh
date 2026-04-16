#!/bin/bash
# Fabric Server Manager - 下载并安装 EasyAuth 登录认证 mod
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
GAME_DIR="$BASE_DIR/GameFile"
MODS_DIR="$GAME_DIR/mods"
CONFIG_FILE="$BASE_DIR/config.json"

# 从 config.json 读取当前 MC 版本
MC_VERSION=$(python3 -c "
import json, re
with open('$CONFIG_FILE') as f: c = json.load(f)
m = re.search(r'mc\.([0-9]+\.[0-9]+(?:\.[0-9]+)?)', c['server']['fabric_jar'])
print(m.group(1) if m else '')
" 2>/dev/null)

if [ -z "$MC_VERSION" ]; then
    echo "错误: 无法从 config.json 获取 MC 版本"
    exit 1
fi

echo "=== 安装 EasyAuth 登录认证 Mod ==="

# 检查是否已安装
if ls "$MODS_DIR"/easyauth-*.jar &>/dev/null; then
    echo "EasyAuth 已存在，跳过下载"
    exit 0
fi

if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    echo "错误: 需要 curl 或 wget"
    exit 1
fi

# 从 Modrinth API 获取兼容当前 MC 版本的最新 EasyAuth
echo "查找 EasyAuth (MC $MC_VERSION)..."
EASYAUTH_PROJECT="aZj58GfX"
DOWNLOAD_INFO=$(curl -s "https://api.modrinth.com/v2/project/$EASYAUTH_PROJECT/version?game_versions=%5B%22$MC_VERSION%22%5D&loaders=%5B%22fabric%22%5D" \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
releases = [v for v in d if v['version_type'] == 'release']
if not releases: releases = d
if releases:
    v = releases[0]
    f = next((f for f in v['files'] if f['primary']), v['files'][0])
    print(f['url'])
    print(f['filename'])
" 2>/dev/null)

if [ -z "$DOWNLOAD_INFO" ]; then
    echo "错误: 未找到兼容 MC $MC_VERSION 的 EasyAuth 版本"
    echo "请手动从 https://modrinth.com/mod/easyauth 下载"
    exit 1
fi

EASYAUTH_URL=$(echo "$DOWNLOAD_INFO" | sed -n '1p')
EASYAUTH_FILE=$(echo "$DOWNLOAD_INFO" | sed -n '2p')

echo "下载 $EASYAUTH_FILE..."
if command -v curl &>/dev/null; then
    curl -fSL -o "$MODS_DIR/$EASYAUTH_FILE" "$EASYAUTH_URL"
else
    wget -O "$MODS_DIR/$EASYAUTH_FILE" "$EASYAUTH_URL"
fi

if [ -s "$MODS_DIR/$EASYAUTH_FILE" ]; then
    echo "安装成功: $EASYAUTH_FILE"
    echo ""
    echo "首次启动后请参考: docs/EASYAUTH_GUIDE.md 完成配置"
else
    echo "下载失败，请手动下载:"
    echo "  https://modrinth.com/mod/easyauth"
    rm -f "$MODS_DIR/$EASYAUTH_FILE"
    exit 1
fi
