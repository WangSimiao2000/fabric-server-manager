#!/bin/bash
# 测试 info/warn/error 输出格式
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
BASE_DIR="$TMP_DIR"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
source "$SCRIPT_DIR/common.sh"

suite "info() 输出"
out=$(info "测试消息")
assert_contains "$out" "[INFO]" "包含 [INFO] 前缀"
assert_contains "$out" "测试消息" "包含消息内容"

suite "warn() 输出"
out=$(warn "警告消息")
assert_contains "$out" "[WARN]" "包含 [WARN] 前缀"
assert_contains "$out" "警告消息" "包含消息内容"

suite "error() 输出"
out=$(error "错误消息")
assert_contains "$out" "[ERROR]" "包含 [ERROR] 前缀"
assert_contains "$out" "错误消息" "包含消息内容"

summary
