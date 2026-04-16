#!/bin/bash
# 测试 load_config 权限和错误处理
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

suite "load_config 正常加载"
CONFIG_FILE="$TMP_DIR/config.json"
cat > "$CONFIG_FILE" << 'EOF'
{
    "server": {
        "user": "minecraft", "session_name": "mc",
        "fabric_jar": "fabric-server-mc.1.21.4-loader.0.16.14-launcher.1.0.3.jar",
        "java_opts": "-Xms4G", "port": 25565, "stop_countdown": 10
    },
    "backup": { "keep_days": 7, "min_keep": 3, "rsync_dest": "", "exclude": [] },
    "check": { "disk_warn_mb": 5120, "require_easyauth": true },
    "notify": { "enabled": false }
}
EOF
chmod 644 "$CONFIG_FILE"
BASE_DIR="$TMP_DIR"
LOCK_FILE="$TMP_DIR/.mc.lock"
source "$SCRIPT_DIR/common.sh"
load_config

assert_eq "$SESSION_NAME" "mc" "SESSION_NAME 正确"
assert_eq "$FABRIC_JAR" "fabric-server-mc.1.21.4-loader.0.16.14-launcher.1.0.3.jar" "FABRIC_JAR 正确"
assert_eq "$BACKUP_KEEP_DAYS" "7" "BACKUP_KEEP_DAYS 正确"
assert_eq "$BACKUP_MIN_KEEP" "3" "BACKUP_MIN_KEEP 正确"
assert_eq "$REQUIRE_EASYAUTH" "true" "REQUIRE_EASYAUTH 正确"

suite "load_config 权限修复"
# load_config 应将 config.json 设为 600
perms=$(stat -c '%a' "$CONFIG_FILE")
assert_eq "$perms" "600" "config.json 权限被设为 600"

suite "load_config 文件不存在"
# 在子 shell 中测试，因为 load_config 会 exit 1
CONFIG_FILE="$TMP_DIR/nonexistent.json"
output=$(load_config 2>&1 || true)
# 子 shell 中 exit 1 不会终止测试
result=$(bash -c "
    source '$SCRIPT_DIR/common.sh'
    CONFIG_FILE='$TMP_DIR/nonexistent.json'
    load_config
" 2>&1; echo "EXIT:$?")
assert_contains "$result" "EXIT:1" "缺失配置文件 exit 1"

summary
