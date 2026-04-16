#!/bin/bash
# ============================================================
# Fabric Server Manager - 公共函数库
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

# 根据 MC 版本返回所需的最低 Java 版本
required_java_version() {
    local mc_ver="${1:-}"
    if [ -z "$mc_ver" ]; then
        mc_ver=$(echo "$FABRIC_JAR" | grep -oP 'mc\.\K[0-9]+\.[0-9]+(\.[0-9]+)?' )
    fi
    local major minor
    major=$(echo "$mc_ver" | cut -d. -f2)
    minor=$(echo "$mc_ver" | cut -d. -f3)
    minor=${minor:-0}
    if [ "$major" -ge 21 ] || { [ "$major" -eq 20 ] && [ "$minor" -ge 5 ]; }; then
        echo 21
    elif [ "$major" -ge 18 ]; then
        echo 17
    elif [ "$major" -eq 17 ]; then
        echo 16
    else
        echo 8
    fi
}

# tmux 辅助
is_running() {
    tmux has-session -t "$SESSION_NAME" 2>/dev/null && pgrep -f "java.*$FABRIC_JAR" &>/dev/null
}

send_cmd() {
    tmux send-keys -t "$SESSION_NAME" "$1" Enter
}

get_pid() {
    local pid
    # tmux 直接启动 java，pane_pid 即为 Java 进程 PID
    pid=$(tmux list-panes -t "$SESSION_NAME" -F '#{pane_pid}' 2>/dev/null | head -1)
    if [ -z "$pid" ]; then
        pid=$(pgrep -f "java.*$FABRIC_JAR" | head -1)
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
