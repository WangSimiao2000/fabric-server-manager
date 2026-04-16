#!/bin/bash
# ============================================================
# 公共函数库 - 所有脚本 source 此文件
# ============================================================

# 路径（如果调用者未设置）
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
BASE_DIR="${BASE_DIR:-$(dirname "$SCRIPT_DIR")}"
GAME_DIR="${GAME_DIR:-$BASE_DIR/GameFile}"
BACKUP_DIR="${BACKUP_DIR:-$BASE_DIR/backups}"
CONFIG_FILE="${CONFIG_FILE:-$BASE_DIR/config.json}"

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 读取 config.json
cfg() {
    python3 -c "
import json
with open('$CONFIG_FILE') as f: c = json.load(f)
keys = '$1'.split('.')
v = c
for k in keys: v = v[k]
if isinstance(v, bool): print(str(v).lower())
else: print(v)
" 2>/dev/null
}

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
    SESSION_NAME=$(cfg server.session_name)
    FABRIC_JAR=$(cfg server.fabric_jar)
    JAVA_OPTS=$(cfg server.java_opts)
    SERVER_USER=$(cfg server.user)
    STOP_COUNTDOWN=$(cfg server.stop_countdown)
    BACKUP_KEEP_DAYS=$(cfg backup.keep_days)
    BACKUP_MIN_KEEP=$(cfg backup.min_keep)
    RSYNC_DEST=$(cfg backup.rsync_dest)
    DISK_WARN_MB=$(cfg check.disk_warn_mb)
    REQUIRE_EASYAUTH=$(cfg check.require_easyauth)
}

# tmux 辅助
is_running() {
    tmux has-session -t "$SESSION_NAME" 2>/dev/null && return 0
    pgrep -f "$FABRIC_JAR" &>/dev/null
}

send_cmd() {
    tmux send-keys -t "$SESSION_NAME" "$1" Enter
}

get_pid() {
    local pid
    pid=$(pgrep -f "$FABRIC_JAR" | head -1)
    if [ -z "$pid" ]; then
        pid=$(tmux list-panes -t "$SESSION_NAME" -F '#{pane_pid}' 2>/dev/null | head -1)
    fi
    echo "$pid"
}

wait_stop() {
    local timeout=${1:-30} i=0
    while is_running && [ $i -lt $timeout ]; do
        sleep 1; ((i++))
    done
    ! is_running
}
