#!/bin/bash
# 测试 show_help 输出（测试真实 mc.sh help 命令）
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

# 创建最小配置让 mc.sh 能加载
CONFIG_FILE="$TMP_DIR/config.json"
cat > "$CONFIG_FILE" << 'EOF'
{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}
EOF

# 运行真实的 mc.sh help，通过环境变量覆盖路径
out=$(CONFIG_FILE="$CONFIG_FILE" BASE_DIR="$TMP_DIR" bash "$SCRIPT_DIR/mc.sh" help 2>&1)

suite "show_help 包含关键命令"
assert_contains "$out" "start" "包含 start"
assert_contains "$out" "stop" "包含 stop"
assert_contains "$out" "backup" "包含 backup"
assert_contains "$out" "player" "包含 player"
assert_contains "$out" "mods" "包含 mods"
assert_contains "$out" "logs" "包含 logs"
assert_contains "$out" "upgrade" "包含 upgrade"
assert_contains "$out" "rollback" "包含 rollback"
assert_contains "$out" "用法" "包含用法说明"

summary
