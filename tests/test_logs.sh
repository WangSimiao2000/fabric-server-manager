#!/bin/bash
# 测试 logs_search 和 logs_crash
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
BASE_DIR="$TMP_DIR"; LOCK_FILE="$TMP_DIR/.mc.lock"
GAME_DIR="$TMP_DIR/GameFile"
mkdir -p "$GAME_DIR/logs" "$GAME_DIR/crash-reports"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/mods.sh"

# 创建假日志
cat > "$GAME_DIR/logs/latest.log" << 'EOF'
[10:00:01] [Server thread/INFO]: Starting minecraft server
[10:00:02] [Server thread/INFO]: Loading properties
[10:00:03] [Server thread/WARN]: Something went wrong
[10:00:04] [Server thread/ERROR]: Failed to load world
[10:00:05] [Server thread/INFO]: Done (3.5s)!
EOF

suite "logs_search 找到匹配"
out=$(logs_search "ERROR" 2>&1)
assert_contains "$out" "Failed to load world" "找到 ERROR 行"
assert_contains "$out" "共 1 条匹配" "匹配计数正确"

suite "logs_search 多条匹配"
out=$(logs_search "INFO" 2>&1)
assert_contains "$out" "共 3 条匹配" "INFO 匹配 3 条"

suite "logs_search 无匹配"
out=$(logs_search "NOTEXIST" 2>&1)
assert_contains "$out" "共 0" "无匹配显示 0"

suite "logs_search 无参数"
out=$(logs_search 2>&1)
assert_contains "$out" "用法" "无参数显示用法"

suite "logs_crash 无崩溃报告"
out=$(logs_crash 2>&1)
assert_contains "$out" "暂无崩溃报告" "空目录显示暂无"

suite "logs_crash 有崩溃报告"
echo "crash content line 1" > "$GAME_DIR/crash-reports/crash-2026-04-01.txt"
echo "crash content line 2" > "$GAME_DIR/crash-reports/crash-2026-04-02.txt"
out=$(logs_crash 2>&1)
assert_contains "$out" "崩溃报告" "显示标题"
assert_contains "$out" "crash-2026-04-01.txt" "列出报告文件"
assert_contains "$out" "crash content" "显示最新报告内容"

suite "cmd_logs 路由"
out=$(cmd_logs unknown 2>&1)
assert_contains "$out" "用法" "未知子命令显示用法"

summary
