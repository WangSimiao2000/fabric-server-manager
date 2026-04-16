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

# 并发锁（flock），防止多实例同时操作
LOCK_FILE="${BASE_DIR}/.mc.lock"
LOCK_FD=200

acquire_lock() {
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        error "另一个 mc.sh 实例正在运行，请稍后再试"
        exit 1
    fi
}

# 读取 config.json（通过 sys.argv 传参，避免注入）
cfg() {
    python3 -c "
import json, sys
with open(sys.argv[1]) as f: c = json.load(f)
keys = sys.argv[2].split('.')
v = c
for k in keys: v = v[k]
if isinstance(v, bool): print(str(v).lower())
else: print(v)
" "$CONFIG_FILE" "$1" 2>/dev/null
}

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
    # 确保配置文件仅所有者可读写（含 SMTP 密码等敏感信息）
    chmod 600 "$CONFIG_FILE" 2>/dev/null || true
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

# 从 FABRIC_JAR 文件名提取 MC 版本号
get_mc_version() {
    echo "${1:-$FABRIC_JAR}" | grep -oP 'mc\.\K[0-9]+\.[0-9]+(\.[0-9]+)?'
}

# 根据 MC 版本返回所需的最低 Java 版本
required_java_version() {
    local mc_ver="${1:-}"
    if [ -z "$mc_ver" ]; then
        mc_ver=$(get_mc_version)
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

# SHA 校验：verify_sha <file> <expected_hash> [algorithm]
# algorithm: sha1 (default) 或 sha512
verify_sha() {
    local file="$1" expected="$2" algo="${3:-sha1}"
    [ -z "$expected" ] && return 0
    local actual
    if [ "$algo" = "sha512" ]; then
        actual=$(sha512sum "$file" | cut -d' ' -f1)
    else
        actual=$(sha1sum "$file" | cut -d' ' -f1)
    fi
    [ "$actual" = "$expected" ]
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
