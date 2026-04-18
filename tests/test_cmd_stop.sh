#!/bin/bash
# 集成测试：cmd_stop 命令序列（mock tmux send-keys）
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

BASE_DIR="$TMP_DIR"; GAME_DIR="$TMP_DIR/GameFile"; BACKUP_DIR="$TMP_DIR/backups"
CONFIG_FILE="$TMP_DIR/config.json"; LOCK_FILE="$TMP_DIR/.mc.lock"
mkdir -p "$GAME_DIR" "$BACKUP_DIR" "$BASE_DIR/.watchdog"

cat > "$CONFIG_FILE" << 'EOF'
{"server":{"session_name":"mc_test","fabric_jar":"test.jar","java_opts":"","user":"mc","stop_countdown":1,"port":25565},
 "backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},
 "check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}
EOF

source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/server.sh"
load_config

CMD_LOG="$TMP_DIR/cmds.log"
send_cmd() { echo "$1" >> "$CMD_LOG"; }

_STOP_CALLS=0
is_running() { ((_STOP_CALLS++)); [ "$_STOP_CALLS" -le 3 ]; }
tmux() { echo "tmux $*" >> "$CMD_LOG"; }

suite "cmd_stop 命令序列"
cmd_stop > /dev/null 2>&1
cmds=$(cat "$CMD_LOG")
assert_contains "$cmds" "say" "发送了关服通知"
assert_contains "$cmds" "stop" "发送了 stop 命令"

suite "cmd_stop 通知包含倒计时秒数"
assert_contains "$cmds" "${STOP_COUNTDOWN}秒" "包含秒数"

suite "cmd_stop watchdog 状态"
raw=$(cat "$BASE_DIR/.watchdog/state")
assert_eq "${raw%%:*}" "stopped" "设为 stopped"
assert_contains "$raw" "cmd_stop" "包含来源标记"

suite "cmd_stop 命令顺序（say 在 stop 前）"
say_n=$(grep -n "say" "$CMD_LOG" | head -1 | cut -d: -f1)
stop_n=$(grep -n "^stop$" "$CMD_LOG" | head -1 | cut -d: -f1)
assert_ok "say 在 stop 之前" test "$say_n" -lt "$stop_n"

suite "cmd_stop 服务器未运行时"
is_running() { return 1; }
out=$(cmd_stop 2>&1)
ret=$?
assert_ok "返回非 0" test "$ret" -ne 0
assert_contains "$out" "未在运行" "提示未运行"

summary
