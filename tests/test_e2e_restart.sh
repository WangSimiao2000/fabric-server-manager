#!/bin/bash
# 端到端集成测试：mc-restart 全流程 + watchdog 协调 + CLOEXEC 锁释放
# 使用 mock mc.sh 和 mock is_running，不依赖真实 MC 服务器
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
mkdir -p "$TMP_DIR/backups" "$TMP_DIR/.watchdog" "$TMP_DIR/GameFile"

CALL_LOG="$TMP_DIR/calls.log"
# mock mc.sh
cat > "$TMP_DIR/mc.sh" << 'MOCK'
#!/bin/bash
echo "$@" >> "$CALL_LOG"
MOCK
chmod +x "$TMP_DIR/mc.sh"

# 构建可测试的 mc-restart 副本
build_restart() {
    local mock_is_running="$1" out="$2"
    sed \
        -e "s|source \"\$SCRIPT_DIR/common.sh\"|source \"$SCRIPT_DIR/common.sh\"|" \
        -e "s|MC=.*|MC=\"$TMP_DIR/mc.sh\"|" \
        "$SCRIPT_DIR/mc-restart.sh" > "$out"
    sed -i "/^load_config$/a\\
$mock_is_running" "$out"
}

# ==================== 测试 1: restart 全流程 + watchdog 不误报 ====================

suite "restart 全流程：watchdog 状态在 stop 前已为 stopped"
echo "running:watchdog:$(date +%s)" > "$TMP_DIR/.watchdog/state"
rm -f "$CALL_LOG"

RESTART_RUNNING="$TMP_DIR/restart_running.sh"
build_restart '_N=0; is_running() { ((_N++)); [ "$_N" -le 1 ]; }' "$RESTART_RUNNING"

(export BASE_DIR="$TMP_DIR" CONFIG_FILE CALL_LOG; bash "$RESTART_RUNNING") >/dev/null 2>&1 || true

# watchdog 状态应为 stopped（mc-restart 设置的）
state_raw=$(cat "$TMP_DIR/.watchdog/state" 2>/dev/null)
state=${state_raw%%:*}
assert_eq "$state" "stopped" "状态为 stopped"

# 意图标记应包含 mc-restart
assert_contains "$state_raw" "mc-restart" "标记来源为 mc-restart"

# 模拟 watchdog 在此时运行：服务器离线 + stopped → 不报警
source "$SCRIPT_DIR/common.sh"
load_config
BASE_DIR="$TMP_DIR"
WATCHDOG_DIR="$BASE_DIR/.watchdog"
STATE_FILE="$WATCHDOG_DIR/state"
CRASH_LOG="$WATCHDOG_DIR/crashes.log"
CRASH_THRESHOLD=3; CRASH_WINDOW=10

read_state() {
    local raw; raw=$(cat "$STATE_FILE" 2>/dev/null || echo "unknown")
    echo "${raw%%:*}"
}
is_running() { return 1; }

last_state=$(read_state)
if [ "$last_state" = "stopped" ] || [ "$last_state" = "notified" ]; then
    action="skip"
else
    action="alert"
fi
assert_eq "$action" "skip" "watchdog 在维护期间不误报"

# ==================== 测试 2: 调用顺序正确 ====================

suite "restart 调用顺序：stop → backup → start"
calls=$(cat "$CALL_LOG" 2>/dev/null)
assert_contains "$calls" "stop" "调用了 stop"
assert_contains "$calls" "backup create" "调用了 backup create"
assert_contains "$calls" "start" "调用了 start"

stop_n=$(grep -n "^stop" "$CALL_LOG" | head -1 | cut -d: -f1)
backup_n=$(grep -n "^backup create" "$CALL_LOG" | head -1 | cut -d: -f1)
start_n=$(grep -n "^start" "$CALL_LOG" | head -1 | cut -d: -f1)
assert_ok "stop < backup < start" test "$stop_n" -lt "$backup_n" -a "$backup_n" -lt "$start_n"

# ==================== 测试 3: 200>&- 防止锁泄漏 ====================

suite "200>&-：子进程不继承 flock fd"
LOCK_FILE="$TMP_DIR/.mc.lock"
(
    exec 200>"$LOCK_FILE"
    flock -n 200
    # 模拟 tmux：后台子进程带 200>&- 启动
    bash -c "sleep 5" 200>&- &
    # 父 shell 退出，释放自己的 fd
)
# 子进程存活但不应持有锁
result=$(
    exec 200>"$LOCK_FILE"
    flock -n 200 && echo "acquired" || echo "blocked"
)
assert_eq "$result" "acquired" "200>&- 后子进程不持有锁"
kill %1 2>/dev/null; wait 2>/dev/null

# ==================== 测试 4: 模拟崩溃 → watchdog 报警 ====================

suite "watchdog 检测意外停止（对照组）"
echo "running:watchdog:$(date +%s)" > "$STATE_FILE"
is_running() { return 1; }
last_state=$(read_state)
if [ "$last_state" = "stopped" ] || [ "$last_state" = "notified" ]; then
    action="skip"
else
    action="alert"
fi
assert_eq "$action" "alert" "running + 离线 → 报警"

# ==================== 测试 5: cmd_stop 也设置意图标记 ====================

suite "cmd_stop 状态包含意图标记"
# 直接检查源码
assert_ok "cmd_stop 写入 who 标记" \
    grep -q 'stopped:cmd_stop' "$SCRIPT_DIR/lib/server.sh"

summary
