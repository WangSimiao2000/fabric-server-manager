#!/bin/bash
# 测试 watchdog write_state: 原子写入（tmp + mv）
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false},"watchdog":{"crash_threshold":3,"crash_window_minutes":10}}' > "$CONFIG_FILE"
BASE_DIR="$TMP_DIR"; LOCK_FILE="$TMP_DIR/.mc.lock"
GAME_DIR="$TMP_DIR/GameFile"; mkdir -p "$GAME_DIR"

source "$SCRIPT_DIR/common.sh"
load_config

WATCHDOG_DIR="$BASE_DIR/.watchdog"
STATE_FILE="$WATCHDOG_DIR/state"
mkdir -p "$WATCHDOG_DIR"

# 提取 write_state 函数
write_state() {
    local tmp; tmp=$(mktemp "$WATCHDOG_DIR/state.XXXXXX")
    echo "$1" > "$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

suite "write_state 基本功能"
write_state "running"
assert_eq "$(cat "$STATE_FILE")" "running" "写入 running"

write_state "stopped"
assert_eq "$(cat "$STATE_FILE")" "stopped" "写入 stopped"

write_state "notified"
assert_eq "$(cat "$STATE_FILE")" "notified" "写入 notified"

suite "write_state 原子性"
# 写入后不应有残留的临时文件
write_state "running"
tmp_count=$(ls "$WATCHDOG_DIR"/state.?????? 2>/dev/null | wc -l)
assert_eq "$tmp_count" "0" "无残留临时文件"

suite "write_state 覆盖已有状态"
write_state "running"
write_state "stopped"
assert_eq "$(cat "$STATE_FILE")" "stopped" "覆盖成功"
# 文件应只有一行
lines=$(wc -l < "$STATE_FILE")
assert_eq "$lines" "1" "文件只有一行"

suite "cmd_stop 也使用原子写入"
# 验证 server.sh 中 cmd_stop 的写入方式
grep -q 'mktemp.*watchdog/state' "$SCRIPT_DIR/lib/server.sh"
assert_eq "$?" "0" "server.sh cmd_stop 使用 mktemp"
grep -q 'mv -f.*watchdog/state' "$SCRIPT_DIR/lib/server.sh"
assert_eq "$?" "0" "server.sh cmd_stop 使用 mv"

summary
