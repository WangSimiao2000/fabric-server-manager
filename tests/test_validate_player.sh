#!/bin/bash
# 测试 validate_player: 合法/非法玩家名、注入防护
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
BASE_DIR="$TMP_DIR"; LOCK_FILE="$TMP_DIR/.mc.lock"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/player.sh"

suite "合法玩家名"
assert_ok "普通名 Steve" validate_player "Steve"
assert_ok "含数字 Player123" validate_player "Player123"
assert_ok "含下划线 my_name" validate_player "my_name"
assert_ok "3 字符最短 abc" validate_player "abc"
assert_ok "16 字符最长" validate_player "abcdefghijklmnop"

suite "非法玩家名"
assert_fail "2 字符太短" validate_player "ab"
assert_fail "17 字符太长" validate_player "abcdefghijklmnopq"
assert_fail "含空格" validate_player "my name"
assert_fail "含连字符" validate_player "my-name"
assert_fail "含点号" validate_player "my.name"
assert_fail "空字符串" validate_player ""

suite "注入防护"
assert_fail "含换行符" validate_player $'test\nstop'
assert_fail "含分号" validate_player 'test;stop'
assert_fail "含引号" validate_player "test'stop"
assert_fail "含斜杠" validate_player "test/stop"

suite "cmd_player 集成 - 非法名不执行命令"
CMD_LOG="$TMP_DIR/cmds.log"
send_cmd() { echo "$1" >> "$CMD_LOG"; }
is_running() { return 0; }

rm -f "$CMD_LOG"
cmd_player op 'ab' >/dev/null 2>&1
assert_ok "太短的名字不发送命令" test ! -f "$CMD_LOG"

rm -f "$CMD_LOG"
cmd_player op $'test\nstop' >/dev/null 2>&1
assert_ok "含换行的名字不发送命令" test ! -f "$CMD_LOG"

rm -f "$CMD_LOG"
cmd_player op "ValidName" >/dev/null 2>&1
assert_ok "合法名字发送了命令" test -f "$CMD_LOG"
assert_contains "$(cat "$CMD_LOG")" "op ValidName" "命令内容正确"

summary
