#!/bin/bash
# 集成测试：mc-restart.sh 全流程（mock mc.sh 为桩脚本）
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

CONFIG_FILE="$TMP_DIR/config.json"
cat > "$CONFIG_FILE" << 'EOF'
{"server":{"session_name":"mc","fabric_jar":"test.jar","java_opts":"","user":"mc","stop_countdown":0,"port":25565},
 "backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},
 "restart":{"warn_minutes":0},
 "check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}
EOF
mkdir -p "$TMP_DIR/backups"

CALL_LOG="$TMP_DIR/calls.log"
MOCK_MC="$TMP_DIR/mc.sh"

# mock mc.sh：记录调用参数，status 返回"运行中"
cat > "$MOCK_MC" << 'MOCK'
#!/bin/bash
echo "$@" >> "$CALL_LOG"
echo "LOCK=$_MC_LOCK_HELD" >> "$CALL_LOG"
case "$1" in
    status) echo "运行中" ;;
esac
MOCK
chmod +x "$MOCK_MC"

# 创建可测试的 restart 脚本副本，替换路径
RESTART_COPY="$TMP_DIR/mc-restart.sh"
sed \
    -e "s|source \"\$SCRIPT_DIR/common.sh\"|source \"$SCRIPT_DIR/common.sh\"|" \
    -e "s|MC=.*|MC=\"$MOCK_MC\"|" \
    "$SCRIPT_DIR/mc-restart.sh" > "$RESTART_COPY"

suite "mc-restart.sh 全流程调用顺序"
export BASE_DIR="$TMP_DIR" CONFIG_FILE CALL_LOG
(bash "$RESTART_COPY") > /dev/null 2>&1 || true
calls=$(cat "$CALL_LOG" 2>/dev/null)
assert_contains "$calls" "stop" "调用了 stop"
assert_contains "$calls" "backup create" "调用了 backup create"
assert_contains "$calls" "backup clean" "调用了 backup clean"
assert_contains "$calls" "start" "调用了 start"

suite "mc-restart.sh 调用顺序正确"
stop_line=$(grep -n "^stop" "$CALL_LOG" | head -1 | cut -d: -f1)
backup_line=$(grep -n "^backup create" "$CALL_LOG" | head -1 | cut -d: -f1)
start_line=$(grep -n "^start" "$CALL_LOG" | head -1 | cut -d: -f1)
assert_ok "stop 在 backup 之前" test "$stop_line" -lt "$backup_line"
assert_ok "backup 在 start 之前" test "$backup_line" -lt "$start_line"

suite "mc-restart.sh 锁传递给子进程"
assert_contains "$calls" "LOCK=1" "子进程收到 _MC_LOCK_HELD=1"

suite "mc-restart.sh 服务器未运行时跳过关服"
cat > "$MOCK_MC" << 'MOCK'
#!/bin/bash
echo "$@" >> "$CALL_LOG"
case "$1" in status) echo "已停止" ;; esac
MOCK
rm -f "$CALL_LOG"
(bash "$RESTART_COPY") > /dev/null 2>&1 || true
calls=$(cat "$CALL_LOG" 2>/dev/null)
assert_fail "未运行时不调用 stop" grep -q "^stop" "$CALL_LOG"
assert_contains "$calls" "backup create" "未运行时仍备份"
assert_contains "$calls" "start" "未运行时仍启动"

summary
