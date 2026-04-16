#!/bin/bash
# 测试 backup_list
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
BACKUP_DIR="$TMP_DIR/backups"; mkdir -p "$BACKUP_DIR"
BASE_DIR="$TMP_DIR"; LOCK_FILE="$TMP_DIR/.mc.lock"; GAME_DIR="$TMP_DIR/GameFile"; mkdir -p "$GAME_DIR"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/backup.sh"

suite "backup_list 空目录"
out=$(backup_list 2>&1)
assert_contains "$out" "暂无备份" "空目录显示暂无备份"

suite "backup_list 有备份"
echo "data1" > "$BACKUP_DIR/mc-backup-20260101_000000.tar.gz"
echo "data22" > "$BACKUP_DIR/mc-backup-20260102_000000.tar.gz"
out=$(backup_list 2>&1)
assert_contains "$out" "备份列表" "显示标题"
assert_contains "$out" "mc-backup-20260101_000000.tar.gz" "列出第一个备份"
assert_contains "$out" "mc-backup-20260102_000000.tar.gz" "列出第二个备份"

summary
