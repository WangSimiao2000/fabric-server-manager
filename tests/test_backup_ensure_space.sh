#!/bin/bash
# 测试 backup_ensure_space
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":2,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
BACKUP_DIR="$TMP_DIR/backups"; mkdir -p "$BACKUP_DIR"
BASE_DIR="$TMP_DIR"; LOCK_FILE="$TMP_DIR/.mc.lock"
GAME_DIR="$TMP_DIR/GameFile"; mkdir -p "$GAME_DIR/world"
# 创建一个小 world 目录使 needed_mb 很小
echo "x" > "$GAME_DIR/world/level.dat"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/backup.sh"
load_config
BACKUP_MIN_KEEP=2

suite "backup_ensure_space 空间充足"
# 真实磁盘空间肯定 > 1MB（world 很小），应直接通过
out=$(backup_ensure_space 2>&1)
assert_contains "$out" "磁盘空间充足" "空间充足时正常通过"

suite "backup_ensure_space 无 world 目录时默认 500MB"
mv "$GAME_DIR/world" "$GAME_DIR/world.bak"
# 磁盘空间通常 > 500MB，应通过
out=$(backup_ensure_space 2>&1)
assert_contains "$out" "磁盘空间充足" "无 world 时使用默认值仍通过"
mv "$GAME_DIR/world.bak" "$GAME_DIR/world"

summary
