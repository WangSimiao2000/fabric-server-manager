#!/bin/bash
# 测试 Bug 修复：mc-restart.sh 在 stop 后再次写入 watchdog 状态
# 背景：5 分钟警告期间 watchdog 每分钟运行，发现服务器在线会覆盖状态为 running，
#       导致服务器真正停止后 watchdog 误报"意外停止"。
#       修复：在 stop 等待循环之后再次写入 stopped 状态。
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

# 配置
CONFIG_FILE="$TMP_DIR/config.json"
cat > "$CONFIG_FILE" << 'EOF'
{"server":{"session_name":"mc","fabric_jar":"test.jar","java_opts":"","user":"mc","stop_countdown":0,"port":25565},
 "backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},
 "restart":{"warn_minutes":0},
 "check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false},
 "watchdog":{"crash_threshold":3,"crash_window_minutes":10}}
EOF
mkdir -p "$TMP_DIR/backups" "$TMP_DIR/.watchdog"

# Mock mc.sh
CALL_LOG="$TMP_DIR/calls.log"
MOCK_MC="$TMP_DIR/mc.sh"
cat > "$MOCK_MC" << 'MOCK'
#!/bin/bash
echo "$@" >> "$CALL_LOG"
MOCK
chmod +x "$MOCK_MC"

export BASE_DIR="$TMP_DIR" CONFIG_FILE CALL_LOG

suite "竞态模拟：watchdog 在警告期间覆盖状态后，restart 仍能恢复"

# 创建可测试的 restart 脚本：is_running 第一次返回 true（触发 stop 分支），之后返回 false
RESTART_TEST="$TMP_DIR/mc-restart-test.sh"
sed \
    -e "s|source \"\$SCRIPT_DIR/common.sh\"|source \"$SCRIPT_DIR/common.sh\"|" \
    -e "s|MC=.*|MC=\"$MOCK_MC\"|" \
    "$SCRIPT_DIR/mc-restart.sh" > "$TMP_DIR/mc-restart-copy.sh"

sed '/^load_config$/a\
_RUN_COUNT=0\
is_running() { ((_RUN_COUNT++)); [ "$_RUN_COUNT" -le 1 ]; }' \
    "$TMP_DIR/mc-restart-copy.sh" > "$RESTART_TEST"

# 模拟竞态：在 restart 执行前，watchdog 已将状态覆盖为 running
echo "running:watchdog:$(date +%s)" > "$TMP_DIR/.watchdog/state"

# 执行 restart 脚本
(bash "$RESTART_TEST") > /dev/null 2>&1 || true

# 验证：restart 完成后状态必须是 stopped（不是被 watchdog 覆盖的 running）
raw=$(cat "$TMP_DIR/.watchdog/state" 2>/dev/null)
assert_eq "${raw%%:*}" "stopped" "restart 完成后状态为 stopped（即使之前被覆盖为 running）"
assert_contains "$raw" "mc-restart" "状态来源标记为 mc-restart"

suite "竞态验证：watchdog 读到 stopped 不会误报"

# 模拟 watchdog 逻辑
is_running() { return 1; }  # 服务器已离线

last_state="${raw%%:*}"
if [ "$last_state" = "stopped" ] || [ "$last_state" = "notified" ]; then
    action="skip"
else
    action="alert"
fi
assert_eq "$action" "skip" "watchdog 读到 stopped + 服务器离线 → 不误报"

suite "对照组：如果没有二次写入，watchdog 会误报"

# 模拟旧行为：状态停留在 running（被 watchdog 覆盖后没有修复）
echo "running:watchdog:$(date +%s)" > "$TMP_DIR/.watchdog/state"
last_state="running"
if [ "$last_state" = "stopped" ] || [ "$last_state" = "notified" ]; then
    action="skip"
else
    action="alert"
fi
assert_eq "$action" "alert" "状态为 running + 服务器离线 → 误报（旧行为）"

suite "源码验证：stop 等待循环之后存在二次状态写入"

# 找到 while is_running 循环后面的状态写入
after_loop=$(awk '/while is_running.*timeout/,/done/' "$SCRIPT_DIR/mc-restart.sh" | wc -l)
post_stop_write=$(awk '/^done$/{found=1} found && /\.watchdog\/state/{print NR; exit}' "$SCRIPT_DIR/mc-restart.sh")
assert_ok "stop 等待循环后存在 watchdog 状态写入" test -n "$post_stop_write"

summary
