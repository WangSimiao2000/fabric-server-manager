#!/bin/bash
# 测试 load_config 批量加载：一次 python3 调用、关键变量非空
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

CONFIG_FILE="$TMP_DIR/config.json"
cat > "$CONFIG_FILE" << 'EOF'
{
    "server": {
        "user": "testuser", "session_name": "mc_test",
        "fabric_jar": "fabric-server-mc.1.21.4-loader.0.16.14-launcher.1.0.3.jar",
        "java_opts": "-Xms4G -Xmx6G", "port": 25565, "stop_countdown": 15
    },
    "backup": { "keep_days": 14, "min_keep": 5, "rsync_dest": "user@host:/backup" },
    "check": { "disk_warn_mb": 10240, "require_easyauth": true },
    "notify": { "enabled": false }
}
EOF
BASE_DIR="$TMP_DIR"; LOCK_FILE="$TMP_DIR/.mc.lock"
source "$SCRIPT_DIR/common.sh"

suite "load_config 一次调用加载所有变量"
# 用 strace 计数 python3 调用次数（如果可用）
if command -v strace &>/dev/null; then
    py_calls=$(strace -f -e trace=execve bash -c "
        source '$SCRIPT_DIR/common.sh'
        CONFIG_FILE='$CONFIG_FILE'
        BASE_DIR='$TMP_DIR'
        LOCK_FILE='$TMP_DIR/.mc.lock'
        load_config
    " 2>&1 | grep -c 'python3' || true)
    assert_eq "$py_calls" "1" "load_config 只调用 1 次 python3"
fi

suite "load_config 所有变量正确"
load_config
assert_eq "$SESSION_NAME" "mc_test" "SESSION_NAME"
assert_eq "$FABRIC_JAR" "fabric-server-mc.1.21.4-loader.0.16.14-launcher.1.0.3.jar" "FABRIC_JAR"
assert_eq "$JAVA_OPTS" "-Xms4G -Xmx6G" "JAVA_OPTS 含空格"
assert_eq "$SERVER_USER" "testuser" "SERVER_USER"
assert_eq "$STOP_COUNTDOWN" "15" "STOP_COUNTDOWN"
assert_eq "$BACKUP_KEEP_DAYS" "14" "BACKUP_KEEP_DAYS"
assert_eq "$BACKUP_MIN_KEEP" "5" "BACKUP_MIN_KEEP"
assert_eq "$RSYNC_DEST" "user@host:/backup" "RSYNC_DEST"
assert_eq "$DISK_WARN_MB" "10240" "DISK_WARN_MB"
assert_eq "$REQUIRE_EASYAUTH" "true" "REQUIRE_EASYAUTH"

suite "load_config 关键变量非空"
assert_ok "SESSION_NAME 非空" test -n "$SESSION_NAME"
assert_ok "FABRIC_JAR 非空" test -n "$FABRIC_JAR"
assert_ok "SERVER_USER 非空" test -n "$SERVER_USER"

suite "load_config rsync_dest 为空时正常"
cat > "$CONFIG_FILE" << 'EOF'
{
    "server": {"user":"mc","session_name":"mc","fabric_jar":"test.jar","java_opts":"","port":25565,"stop_countdown":10},
    "backup": {"keep_days":7,"min_keep":3},
    "check": {"disk_warn_mb":5120,"require_easyauth":false},
    "notify": {"enabled":false}
}
EOF
load_config
assert_eq "$RSYNC_DEST" "" "缺失 rsync_dest 时为空"

summary
