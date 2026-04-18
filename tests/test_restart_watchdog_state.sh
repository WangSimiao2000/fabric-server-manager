#!/bin/bash
# 测试 Bug 修复：mc-restart.sh 在关服前设置 watchdog 状态为 stopped
# 背景：mc-restart.sh 关服期间有 5 分钟警告等待，如果 watchdog 在此期间检测到
#       服务器离线且状态仍为 running，会误报"意外停止"并发送告警邮件。
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

CONFIG_FILE="$TMP_DIR/config.json"
cat > "$CONFIG_FILE" << 'EOF'
{"server":{"session_name":"mc","fabric_jar":"test.jar","java_opts":"","user":"mc","stop_countdown":0,"port":25565},
 "backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},
 "restart":{"warn_minutes":0},
 "check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false},
 "watchdog":{"crash_threshold":3,"crash_window_minutes":10}}
EOF
mkdir -p "$TMP_DIR/backups"

CALL_LOG="$TMP_DIR/calls.log"
MOCK_MC="$TMP_DIR/mc.sh"
cat > "$MOCK_MC" << 'MOCK'
#!/bin/bash
echo "$@" >> "$CALL_LOG"
MOCK
chmod +x "$MOCK_MC"

# 创建可测试的 restart 脚本副本
RESTART_COPY="$TMP_DIR/mc-restart.sh"
sed \
    -e "s|source \"\$SCRIPT_DIR/common.sh\"|source \"$SCRIPT_DIR/common.sh\"|" \
    -e "s|MC=.*|MC=\"$MOCK_MC\"|" \
    "$SCRIPT_DIR/mc-restart.sh" > "$RESTART_COPY"

# 注入 is_running mock（第一次返回 true 模拟服务器运行中）
RESTART_TEST="$TMP_DIR/mc-restart-test.sh"
sed '/^load_config$/a\
_RUN_COUNT=0\
is_running() { ((_RUN_COUNT++)); [ "$_RUN_COUNT" -le 1 ]; }' \
    "$RESTART_COPY" > "$RESTART_TEST"

suite "mc-restart.sh 源码在关服前设置 watchdog 状态"
# 验证源码中 watchdog state 设置在 is_running/stop 之前
state_line=$(grep -n 'watchdog.*state\|\.watchdog/state' "$SCRIPT_DIR/mc-restart.sh" | head -1 | cut -d: -f1)
stop_line=$(grep -n '"$MC" stop' "$SCRIPT_DIR/mc-restart.sh" | head -1 | cut -d: -f1)
assert_ok "watchdog 状态设置行存在" test -n "$state_line"
assert_ok "watchdog 状态设置在 stop 之前" test "$state_line" -lt "$stop_line"

suite "mc-restart.sh 执行时 watchdog 状态在 stop 前已为 stopped"
# 先设置初始状态为 running（模拟正常运行）
mkdir -p "$TMP_DIR/.watchdog"
echo "running" > "$TMP_DIR/.watchdog/state"

export BASE_DIR="$TMP_DIR" CONFIG_FILE CALL_LOG
(bash "$RESTART_TEST") > /dev/null 2>&1 || true

assert_eq "$(cat "$TMP_DIR/.watchdog/state" 2>/dev/null)" "stopped" \
    "执行后 watchdog 状态为 stopped"

suite "watchdog 在 stopped 状态下不误报"
# 模拟 watchdog 主逻辑：服务器离线 + 状态为 stopped → 不报警
source "$SCRIPT_DIR/common.sh"
load_config
BASE_DIR="$TMP_DIR"
WATCHDOG_DIR="$BASE_DIR/.watchdog"
STATE_FILE="$WATCHDOG_DIR/state"

# 设置 stopped 状态
echo "stopped" > "$STATE_FILE"

# mock is_running 返回 false（服务器离线）
is_running() { return 1; }

last_state=$(cat "$STATE_FILE" 2>/dev/null || echo "unknown")
if [ "$last_state" = "stopped" ] || [ "$last_state" = "notified" ]; then
    action="skip"
else
    action="alert"
fi
assert_eq "$action" "skip" "stopped 状态 + 服务器离线 → 不报警"

suite "watchdog 在 running 状态下会报警（对照组）"
echo "running" > "$STATE_FILE"
last_state=$(cat "$STATE_FILE")
if [ "$last_state" = "stopped" ] || [ "$last_state" = "notified" ]; then
    action="skip"
else
    action="alert"
fi
assert_eq "$action" "alert" "running 状态 + 服务器离线 → 报警"

summary
