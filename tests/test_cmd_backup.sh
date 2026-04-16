#!/bin/bash
# 测试 cmd_backup 路由分发
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
BACKUP_DIR="$TMP_DIR/backups"; mkdir -p "$BACKUP_DIR"
BASE_DIR="$TMP_DIR"; LOCK_FILE="$TMP_DIR/.mc.lock"; GAME_DIR="$TMP_DIR/GameFile"; mkdir -p "$GAME_DIR"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/backup.sh"
load_config

suite "cmd_backup 路由"
out=$(cmd_backup help 2>&1)
assert_contains "$out" "用法" "help 显示用法"

out=$(cmd_backup 2>&1)
assert_contains "$out" "用法" "无参数显示用法"

out=$(cmd_backup list 2>&1)
assert_contains "$out" "暂无备份" "list 路由到 backup_list"

out=$(cmd_backup unknown 2>&1)
assert_contains "$out" "用法" "未知子命令显示用法"

out=$(cmd_backup clean 2>&1)
assert_contains "$out" "备份" "clean 路由到 backup_clean"

summary
