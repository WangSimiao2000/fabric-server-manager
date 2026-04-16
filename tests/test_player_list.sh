#!/bin/bash
# 测试 player_list
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
BASE_DIR="$TMP_DIR"; LOCK_FILE="$TMP_DIR/.mc.lock"
GAME_DIR="$TMP_DIR/GameFile"; mkdir -p "$GAME_DIR"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/player.sh"

suite "player_list 无 usercache"
out=$(player_list 2>&1)
assert_contains "$out" "不存在" "缺失文件显示警告"

suite "player_list 有玩家数据"
cat > "$GAME_DIR/usercache.json" << 'EOF'
[
    {"name": "Steve", "uuid": "12345678-1234-1234-1234-123456789abc", "expiresOn": "2026-05-01"},
    {"name": "Alex", "uuid": "abcdefab-abcd-abcd-abcd-abcdefabcdef", "expiresOn": "2026-04-15"}
]
EOF
out=$(player_list 2>&1)
assert_contains "$out" "玩家列表" "显示标题"
assert_contains "$out" "Steve" "列出 Steve"
assert_contains "$out" "Alex" "列出 Alex"
assert_contains "$out" "12345678" "显示 UUID"

suite "player_list 空数组"
echo "[]" > "$GAME_DIR/usercache.json"
out=$(player_list 2>&1)
assert_contains "$out" "玩家列表" "空数组仍显示标题"

summary
