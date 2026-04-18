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
# 日志输出
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# 并发锁（flock），防止多实例同时操作
LOCK_FILE="${BASE_DIR}/.mc.lock"
_MC_LOCK_HELD="${_MC_LOCK_HELD:-0}"

acquire_lock() {
    # 幂等：已持有锁时跳过（父进程通过 export _MC_LOCK_HELD=1 传递）
    [ "$_MC_LOCK_HELD" -eq 1 ] && return 0
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        error "另一个 mc.sh 实例正在运行，请稍后再试"
        exit 1
    fi
    # 注意：Bash 无法对 exec N> 的 fd 设置 CLOEXEC，
    # 启动长期子进程（如 tmux）时必须手动加 200>&- 关闭继承
    export _MC_LOCK_HELD=1
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
    # 一次 python3 调用读取所有配置，避免 10+ 次 fork
    eval "$(python3 -c "
import json, sys, shlex
with open(sys.argv[1]) as f: c = json.load(f)
s, b, ck = c['server'], c['backup'], c['check']
for var, val in [
    ('SESSION_NAME', s['session_name']),
    ('FABRIC_JAR',   s['fabric_jar']),
    ('JAVA_OPTS',    s['java_opts']),
    ('SERVER_USER',  s['user']),
    ('STOP_COUNTDOWN', s['stop_countdown']),
    ('BACKUP_KEEP_DAYS', b['keep_days']),
    ('BACKUP_MIN_KEEP',  b['min_keep']),
    ('RSYNC_DEST',       b.get('rsync_dest', '')),
    ('DISK_WARN_MB',     ck['disk_warn_mb']),
    ('REQUIRE_EASYAUTH', str(ck['require_easyauth']).lower()),
]:
    print(f'{var}={shlex.quote(str(val))}')
" "$CONFIG_FILE")"
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
    # pgrep -f 会匹配 tmux server 进程（其命令行含 jar 名），用 -x 排除不了，改回 tmux pane_pid
    # tmux pane 直接 exec java 时 pane_pid 就是 java；若经 shell 中转则取其子进程
    pid=$(tmux list-panes -t "$SESSION_NAME" -F '#{pane_pid}' 2>/dev/null | head -1)
    if [ -n "$pid" ]; then
        # pane_pid 可能是 shell，检查是否是 java，不是则找子进程
        if ! ps -p "$pid" -o comm= 2>/dev/null | grep -q java; then
            local child
            child=$(pgrep -P "$pid" -x java 2>/dev/null | head -1)
            [ -n "$child" ] && pid="$child"
        fi
    else
        pid=$(pgrep -x java -f "$FABRIC_JAR" 2>/dev/null | head -1)
    fi
    echo "$pid"
}

wait_stop() {
    local timeout=${1:-30} i=0  # 默认 30 秒，足够 MC 保存世界并退出
    while is_running && [ $i -lt $timeout ]; do
        sleep 1; ((i++))
    done
    ! is_running
}
