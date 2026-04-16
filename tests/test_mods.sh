#!/bin/bash
# 测试 mods_list 和 mods_check
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
BASE_DIR="$TMP_DIR"; LOCK_FILE="$TMP_DIR/.mc.lock"
GAME_DIR="$TMP_DIR/GameFile"; mkdir -p "$GAME_DIR/mods"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/mods.sh"

suite "mods_list 空目录"
out=$(mods_list 2>&1)
assert_contains "$out" "共 0 个 Mod" "空目录显示 0 个"

suite "mods_list 有 Mod"
echo "fake" > "$GAME_DIR/mods/fabric-api-0.92.jar"
echo "fake" > "$GAME_DIR/mods/lithium-0.12.jar"
out=$(mods_list 2>&1)
assert_contains "$out" "fabric-api-0.92.jar" "列出 fabric-api"
assert_contains "$out" "lithium-0.12.jar" "列出 lithium"
assert_contains "$out" "共 2 个 Mod" "计数正确"

suite "mods_check 空文件检测"
> "$GAME_DIR/mods/empty-mod-1.0.jar"  # 0 字节
out=$(mods_check 2>&1)
assert_contains "$out" "空文件" "检测到空文件"

suite "mods_check 重复 Mod 检测"
rm -f "$GAME_DIR/mods"/*.jar
echo "v1" > "$GAME_DIR/mods/sodium-0.5.jar"
echo "v2" > "$GAME_DIR/mods/sodium-0.6.jar"
echo "ok" > "$GAME_DIR/mods/easyauth-1.0.jar"
out=$(mods_check 2>&1)
assert_contains "$out" "重复" "检测到重复 Mod"

suite "mods_check 缺少 EasyAuth"
rm -f "$GAME_DIR/mods"/easyauth-*.jar
out=$(mods_check 2>&1)
assert_contains "$out" "EasyAuth" "检测到缺少 EasyAuth"

suite "mods_check 全部通过"
rm -f "$GAME_DIR/mods"/*.jar
echo "ok" > "$GAME_DIR/mods/fabric-api-0.92.jar"
echo "ok" > "$GAME_DIR/mods/easyauth-1.0.jar"
out=$(mods_check 2>&1)
assert_contains "$out" "所有检查通过" "无问题时通过"

suite "cmd_mods 路由"
out=$(cmd_mods unknown 2>&1)
assert_contains "$out" "用法" "未知子命令显示用法"

summary
