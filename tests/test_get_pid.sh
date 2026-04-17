#!/bin/bash
# 测试 get_pid: 排除 tmux server PID、正确识别 java 进程
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc_test_pid","fabric_jar":"fabric-server-mc.1.21.4.jar","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
BASE_DIR="$TMP_DIR"; LOCK_FILE="$TMP_DIR/.mc.lock"
source "$SCRIPT_DIR/common.sh"
load_config

suite "get_pid 通过 mock tmux 测试"

# Mock tmux list-panes 返回一个假 PID
MOCK_PANE_PID=""
tmux() {
    case "$1" in
        list-panes) [ -n "$MOCK_PANE_PID" ] && echo "$MOCK_PANE_PID" ;;
        has-session) return 0 ;;
    esac
}

# Mock ps 和 pgrep
_MOCK_COMM=""
ps() {
    if [[ "$*" == *"-o comm="* ]]; then
        echo "$_MOCK_COMM"
    fi
}
pgrep() {
    if [[ "$*" == *"-P"* ]]; then
        echo "99999"  # 模拟子进程
    fi
    return 0
}

# 场景 1: pane_pid 就是 java 进程
MOCK_PANE_PID="12345"
_MOCK_COMM="java"
pid=$(get_pid)
assert_eq "$pid" "12345" "pane_pid 是 java 时直接返回"

# 场景 2: pane_pid 是 shell，子进程是 java
MOCK_PANE_PID="12345"
_MOCK_COMM="bash"
pid=$(get_pid)
assert_eq "$pid" "99999" "pane_pid 是 shell 时返回 java 子进程"

# 场景 3: tmux 无会话
MOCK_PANE_PID=""
pid=$(get_pid)
# fallback 到 pgrep -x java
assert_ok "无 tmux 会话时 fallback 不报错" test -n "$pid"

suite "get_pid 不返回 tmux server PID（实际环境）"
# 如果真实 MC 服务器在运行，验证返回的 PID 是 java 而非 tmux
if tmux has-session -t mc 2>/dev/null; then
    # 恢复真实的 tmux/ps/pgrep
    unset -f tmux ps pgrep
    SESSION_NAME="mc"
    real_pid=$(get_pid)
    if [ -n "$real_pid" ]; then
        comm=$(command ps -p "$real_pid" -o comm= 2>/dev/null)
        assert_eq "$comm" "java" "实际返回的 PID ($real_pid) 是 java 进程"
    fi
fi

summary
