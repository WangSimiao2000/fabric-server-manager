#!/bin/bash
# 测试 backup_clean 保留策略逻辑
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
cat > "$CONFIG_FILE" << 'EOF'
{
    "server": { "user": "mc", "session_name": "mc", "fabric_jar": "test", "java_opts": "", "port": 25565, "stop_countdown": 10 },
    "backup": { "keep_days": 7, "min_keep": 3, "rsync_dest": "", "exclude": [] },
    "check": { "disk_warn_mb": 5120, "require_easyauth": false },
    "notify": { "enabled": false }
}
EOF

BASE_DIR="$TMP_DIR"
BACKUP_DIR="$TMP_DIR/backups"
LOCK_FILE="$TMP_DIR/.mc.lock"
GAME_DIR="$TMP_DIR/GameFile"
mkdir -p "$BACKUP_DIR" "$GAME_DIR"

source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/backup.sh"
load_config

# 辅助函数：创建假备份文件，指定天数前
create_backup() {
    local name="$1" days_ago="${2:-0}"
    local f="$BACKUP_DIR/$name"
    echo "fake backup" > "$f"
    if [ "$days_ago" -gt 0 ]; then
        touch -d "$days_ago days ago" "$f"
    fi
}

reset_backups() { rm -f "$BACKUP_DIR"/mc-backup-*.tar.gz; }

# ==================== 测试 ====================

suite "backup_clean 不足最少保留数时跳过"
reset_backups
create_backup "mc-backup-20260101_000000.tar.gz" 30
create_backup "mc-backup-20260102_000000.tar.gz" 20
# min_keep=3, 只有 2 份，不应删除
backup_clean 7 >/dev/null 2>&1
count=$(ls "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | wc -l)
assert_eq "$count" "2" "2 份备份 < min_keep=3，全部保留"

suite "backup_clean 删除过期但保留 min_keep"
reset_backups
create_backup "mc-backup-20260101_000000.tar.gz" 30
create_backup "mc-backup-20260102_000000.tar.gz" 20
create_backup "mc-backup-20260103_000000.tar.gz" 10
create_backup "mc-backup-20260104_000000.tar.gz" 1
# 4 份，min_keep=3，最多删 1 份；30天和20天和10天都过期(>7天)
backup_clean 7 >/dev/null 2>&1
count=$(ls "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | wc -l)
assert_eq "$count" "3" "4 份删 1 份，保留 3 份 (min_keep)"

suite "backup_clean 无过期备份时不删除"
reset_backups
create_backup "mc-backup-20260401_000000.tar.gz" 1
create_backup "mc-backup-20260402_000000.tar.gz" 0
create_backup "mc-backup-20260403_000000.tar.gz" 0
create_backup "mc-backup-20260404_000000.tar.gz" 0
backup_clean 7 >/dev/null 2>&1
count=$(ls "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | wc -l)
assert_eq "$count" "4" "无过期备份，全部保留"

suite "backup_clean 大量过期但受 min_keep 限制"
reset_backups
create_backup "mc-backup-20260101_000000.tar.gz" 30
create_backup "mc-backup-20260102_000000.tar.gz" 25
create_backup "mc-backup-20260103_000000.tar.gz" 20
create_backup "mc-backup-20260104_000000.tar.gz" 15
create_backup "mc-backup-20260105_000000.tar.gz" 10
# 5 份全过期(>7天)，min_keep=3，最多删 2 份
backup_clean 7 >/dev/null 2>&1
count=$(ls "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | wc -l)
assert_eq "$count" "3" "5 份全过期，保留 min_keep=3"

summary
