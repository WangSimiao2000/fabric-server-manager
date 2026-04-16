#!/bin/bash
# ============================================================
# MickeyMiao's Minecraft Server 管理工具
# MC 1.21.5 + Fabric | 离线模式
# 所有配置项见 config.json
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
GAME_DIR="$BASE_DIR/GameFile"
BACKUP_DIR="$BASE_DIR/backups"
CONFIG_FILE="$BASE_DIR/config.json"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ==================== 读取配置 ====================
cfg() {
    python3 -c "
import json, sys
with open('$CONFIG_FILE') as f: c = json.load(f)
keys = '$1'.split('.')
v = c
for k in keys: v = v[k]
print(v)
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

load_config

# ==================== 环境预检查 ====================
preflight_check() {
    local errors=0 warnings=0

    echo -e "${CYAN}=== 环境与配置检查 ===${NC}"

    if [ -f "$CONFIG_FILE" ]; then
        info "config.json 已加载 ✓"
    else
        error "config.json 不存在"; ((errors++))
    fi

    # Java
    if command -v java &>/dev/null; then
        local java_ver
        java_ver=$(java -version 2>&1 | head -1 | grep -oP '"\K[^"]+' | cut -d. -f1)
        if [ "$java_ver" -ge 21 ] 2>/dev/null; then
            info "Java 版本: $java_ver ✓"
        else
            error "Java 版本 $java_ver < 21"; ((errors++))
        fi
    else
        error "Java 未安装"; ((errors++))
    fi

    # tmux
    if command -v tmux &>/dev/null; then
        info "tmux 已安装 ✓"
    else
        error "tmux 未安装"; ((errors++))
    fi

    # GameFile
    if [ -d "$GAME_DIR" ]; then
        info "GameFile 目录存在 ✓"
    else
        error "GameFile 目录不存在: $GAME_DIR"; ((errors++))
    fi

    # Fabric jar
    if [ -f "$GAME_DIR/$FABRIC_JAR" ]; then
        info "Fabric 服务端存在 ✓"
    else
        error "Fabric jar 不存在: $FABRIC_JAR"; ((errors++))
    fi

    # eula.txt
    if grep -q 'eula=true' "$GAME_DIR/eula.txt" 2>/dev/null; then
        info "EULA 已同意 ✓"
    else
        error "EULA 未同意"; ((errors++))
    fi

    # server.properties
    if [ -f "$GAME_DIR/server.properties" ]; then
        if grep -q 'online-mode=false' "$GAME_DIR/server.properties"; then
            info "离线模式已启用 ✓"
        else
            warn "online-mode 不是 false"; ((warnings++))
        fi
    else
        error "server.properties 不存在"; ((errors++))
    fi

    # EasyAuth
    if ls "$GAME_DIR/mods"/easyauth-*.jar &>/dev/null; then
        info "EasyAuth 登录认证 mod 已安装 ✓"
    elif [ "$REQUIRE_EASYAUTH" = "True" ] || [ "$REQUIRE_EASYAUTH" = "true" ]; then
        warn "EasyAuth 未安装！离线模式下任何人可冒充其他玩家"; ((warnings++))
        warn "运行: $SCRIPT_DIR/setup-easyauth.sh 安装"
    fi

    # 磁盘空间
    local avail_mb
    avail_mb=$(df -m "$GAME_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$avail_mb" ]; then
        if [ "$avail_mb" -lt "$DISK_WARN_MB" ]; then
            warn "磁盘剩余空间不足: ${avail_mb}MB"; ((warnings++))
        else
            info "磁盘剩余: ${avail_mb}MB ✓"
        fi
    fi

    echo ""
    if [ "$errors" -gt 0 ]; then
        error "发现 $errors 个严重问题，$warnings 个警告"
        return 1
    elif [ "$warnings" -gt 0 ]; then
        warn "发现 $warnings 个警告，建议处理"
        return 0
    else
        info "所有检查通过 ✓"
        return 0
    fi
}

# ==================== 辅助函数 (tmux) ====================
is_running() {
    sudo -u "$SERVER_USER" tmux has-session -t "$SESSION_NAME" 2>/dev/null && return 0
    pgrep -u "$SERVER_USER" -x java &>/dev/null
}

send_cmd() {
    sudo -u "$SERVER_USER" tmux send-keys -t "$SESSION_NAME" "$1" Enter
}

get_pid() {
    local pid
    pid=$(pgrep -u "$SERVER_USER" -x java | head -1)
    if [ -z "$pid" ]; then
        pid=$(sudo -u "$SERVER_USER" tmux list-panes -t "$SESSION_NAME" -F '#{pane_pid}' 2>/dev/null | head -1)
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

# ==================== 启停管理 ====================
cmd_start() {
    preflight_check || { error "预检查未通过，无法启动"; exit 1; }
    if is_running; then
        warn "服务器已在运行中"; return 1
    fi
    local port
    port=$(cfg server.port)
    if ss -tlnp | grep -q ":${port} "; then
        error "端口 ${port} 已被占用:"; ss -tlnp | grep ":${port} "; return 1
    fi
    info "启动服务器..."
    sudo -u "$SERVER_USER" tmux new-session -ds "$SESSION_NAME" -c "$GAME_DIR" \
        "java $JAVA_OPTS -jar $FABRIC_JAR nogui"
    sleep 3
    if is_running; then
        info "服务器已启动 (PID: $(get_pid))"
    else
        error "启动失败，请检查日志: $GAME_DIR/logs/latest.log"
    fi
}

cmd_stop() {
    if ! is_running; then
        warn "服务器未在运行"; return 1
    fi
    info "正在关闭服务器 (${STOP_COUNTDOWN}秒倒计时)..."
    send_cmd "say §c服务器将在${STOP_COUNTDOWN}秒后关闭..."
    sleep "$STOP_COUNTDOWN"
    send_cmd "stop"
    if wait_stop 30; then
        info "服务器已关闭"
    else
        error "服务器未能在30秒内关闭，强制终止..."
        sudo -u "$SERVER_USER" tmux kill-session -t "$SESSION_NAME" 2>/dev/null
    fi
}

cmd_restart() {
    if is_running; then cmd_stop; fi
    sleep 2
    cmd_start
}

cmd_status() {
    echo -e "${CYAN}=== 服务器状态 ===${NC}"
    if is_running; then
        local pid
        pid=$(get_pid)
        info "状态: 运行中 (PID: $pid)"
        ps -p "$pid" -o %cpu,%mem,etime --no-headers 2>/dev/null | awk '{printf "  CPU: %s%%  内存: %s%%  运行时间: %s\n", $1, $2, $3}'
        local rss
        rss=$(ps -p "$pid" -o rss --no-headers 2>/dev/null | awk '{printf "%.0f", $1/1024}')
        [ -n "$rss" ] && echo "  Java 实际内存: ${rss}MB"
    else
        warn "状态: 未运行"
    fi
    if [ -d "$GAME_DIR/world" ]; then
        echo "  世界大小: $(du -sh "$GAME_DIR/world" 2>/dev/null | cut -f1)"
    fi
    local mod_count
    mod_count=$(find "$GAME_DIR/mods" -maxdepth 1 -name '*.jar' 2>/dev/null | wc -l)
    echo "  已安装 Mod: ${mod_count} 个"
    df -h "$GAME_DIR" 2>/dev/null | awk 'NR==2{printf "  磁盘: 已用 %s / 总计 %s (剩余 %s)\n", $3, $2, $4}'
}

cmd_console() {
    if ! is_running; then
        error "服务器未在运行"; exit 1
    fi
    info "附加到服务器控制台 (按 Ctrl+B 然后 D 退出)"
    if [ "$(whoami)" = "$SERVER_USER" ]; then
        tmux attach -t "$SESSION_NAME"
    else
        sudo -u "$SERVER_USER" tmux attach -t "$SESSION_NAME"
    fi
}

# ==================== 备份管理 ====================
cmd_backup() {
    case "${1:-help}" in
        create) backup_create ;;
        list)   backup_list ;;
        clean)  backup_clean "${2:-$BACKUP_KEEP_DAYS}" ;;
        *)      echo "用法: mc.sh backup <create|list|clean [天数]>" ;;
    esac
}

backup_ensure_space() {
    local needed_mb avail_mb
    needed_mb=$(du -sm "$GAME_DIR/world" 2>/dev/null | awk '{printf "%.0f", $1 / 2}')
    [ -z "$needed_mb" ] && needed_mb=500

    avail_mb=$(df -m "$BACKUP_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    [ -z "$avail_mb" ] && return 0

    while [ "$avail_mb" -lt "$needed_mb" ]; do
        local backup_count oldest
        backup_count=$(ls "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | wc -l)
        if [ "$backup_count" -le "$BACKUP_MIN_KEEP" ]; then
            error "磁盘空间不足 (剩余 ${avail_mb}MB，需要 ${needed_mb}MB)，但仅剩 ${backup_count} 份备份(最少保留 ${BACKUP_MIN_KEEP})，拒绝删除"
            error "请手动清理磁盘空间后重试"
            return 1
        fi
        oldest=$(ls -t "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | tail -1)
        warn "磁盘空间不足 (剩余 ${avail_mb}MB)，删除最早的备份: $(basename "$oldest")"
        rm -f "$oldest"
        avail_mb=$(df -m "$BACKUP_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    done
    info "磁盘空间充足: 剩余 ${avail_mb}MB，预估需要 ${needed_mb}MB"
}

backup_create() {
    mkdir -p "$BACKUP_DIR"
    backup_ensure_space || return 1

    local timestamp filename running=false
    timestamp=$(date +%Y%m%d_%H%M%S)
    filename="mc-backup-${timestamp}.tar.gz"

    if is_running; then
        running=true
        info "服务器运行中，暂停自动保存..."
        send_cmd "save-off"
        send_cmd "save-all flush"
        sleep 5
    fi

    local exclude_args=""
    exclude_args=$(python3 -c "
import json
with open('$CONFIG_FILE') as f: c = json.load(f)
for e in c['backup']['exclude']:
    print(f'--exclude={e}')
" 2>/dev/null)

    info "创建备份: $filename"
    tar -czf "$BACKUP_DIR/$filename" \
        -C "$GAME_DIR" \
        $exclude_args \
        world server.properties ops.json banned-players.json banned-ips.json \
        whitelist.json usercache.json mods config 2>/dev/null

    if [ "$running" = true ]; then
        send_cmd "save-on"
        info "已恢复自动保存"
    fi

    local size
    size=$(du -h "$BACKUP_DIR/$filename" | cut -f1)
    info "备份完成: $filename ($size)"

    if [ -n "$RSYNC_DEST" ]; then
        info "同步到远程: $RSYNC_DEST"
        rsync -az "$BACKUP_DIR/$filename" "$RSYNC_DEST" && info "远程同步完成" || warn "远程同步失败"
    fi
}

backup_list() {
    echo -e "${CYAN}=== 备份列表 ===${NC}"
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null)" ]; then
        warn "暂无备份"; return
    fi
    printf "%-40s %8s  %s\n" "文件名" "大小" "日期"
    echo "---------------------------------------------------------------"
    for f in $(ls -t "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null); do
        local name size mtime
        name=$(basename "$f")
        size=$(du -h "$f" | cut -f1)
        mtime=$(stat -c '%y' "$f" 2>/dev/null | cut -d. -f1)
        printf "%-40s %8s  %s\n" "$name" "$size" "$mtime"
    done
}

backup_clean() {
    local days=${1:-$BACKUP_KEEP_DAYS}
    info "清理 $days 天前的备份 (最少保留 $BACKUP_MIN_KEEP 份)..."
    local total candidates
    total=$(ls "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | wc -l)
    candidates=$(find "$BACKUP_DIR" -name 'mc-backup-*.tar.gz' -mtime +"$days" 2>/dev/null | wc -l)
    local max_delete=$(( total - BACKUP_MIN_KEEP ))
    if [ "$max_delete" -le 0 ]; then
        info "仅有 $total 份备份，不足最少保留数，跳过清理"; return
    fi
    local to_delete=$(( candidates < max_delete ? candidates : max_delete ))
    if [ "$to_delete" -le 0 ]; then
        info "没有需要清理的备份"; return
    fi
    find "$BACKUP_DIR" -name 'mc-backup-*.tar.gz' -mtime +"$days" -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null | tail -"$to_delete" | xargs rm -f
    info "已删除 $to_delete 个旧备份 (保留 $(( total - to_delete )) 份)"
}

# ==================== 监控 ====================
cmd_monitor() {
    echo -e "${CYAN}=== 服务器监控面板 ===${NC}"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    cmd_status
    echo ""

    echo -e "${CYAN}--- 备份信息 ---${NC}"
    local latest_cold
    latest_cold=$(ls -t "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | head -1)
    if [ -n "$latest_cold" ]; then
        echo "  最近冷备份: $(basename "$latest_cold") ($(stat -c '%y' "$latest_cold" 2>/dev/null | cut -d. -f1))"
    else
        echo "  最近冷备份: 无"
    fi
    local latest_hot
    latest_hot=$(ls -t "$GAME_DIR/backup/world"/*.zip 2>/dev/null | head -1)
    [ -n "$latest_hot" ] && echo "  最近热备份: $(basename "$latest_hot")"

    echo ""
    echo -e "${CYAN}--- 最近错误日志 ---${NC}"
    if [ -f "$GAME_DIR/logs/latest.log" ]; then
        grep -i 'error\|exception\|crash' "$GAME_DIR/logs/latest.log" 2>/dev/null | tail -5 | sed 's/^/  /'
        local err_count
        err_count=$(grep -ci 'error\|exception' "$GAME_DIR/logs/latest.log" 2>/dev/null || echo 0)
        echo "  (共 $err_count 条错误/异常)"
    else
        echo "  无日志文件"
    fi
}

# ==================== 玩家管理 ====================
cmd_player() {
    case "${1:-help}" in
        list) player_list ;;
        op)    [ -n "$2" ] && send_cmd "op $2"    && info "已给予 $2 OP 权限" || echo "用法: mc.sh player op <玩家名>" ;;
        deop)  [ -n "$2" ] && send_cmd "deop $2"  && info "已移除 $2 OP 权限" || echo "用法: mc.sh player deop <玩家名>" ;;
        ban)   [ -n "$2" ] && send_cmd "ban $2 ${*:3}" && info "已封禁 $2" || echo "用法: mc.sh player ban <玩家名> [原因]" ;;
        unban) [ -n "$2" ] && send_cmd "pardon $2" && info "已解封 $2" || echo "用法: mc.sh player unban <玩家名>" ;;
        whitelist)
            case "$2" in
                on)     send_cmd "whitelist on"         && info "白名单已启用" ;;
                off)    send_cmd "whitelist off"        && info "白名单已关闭" ;;
                add)    [ -n "$3" ] && send_cmd "whitelist add $3"    && info "已添加 $3 到白名单" || echo "用法: mc.sh player whitelist add <玩家名>" ;;
                remove) [ -n "$3" ] && send_cmd "whitelist remove $3" && info "已从白名单移除 $3" || echo "用法: mc.sh player whitelist remove <玩家名>" ;;
                *)      echo "用法: mc.sh player whitelist <on|off|add|remove> [玩家名]" ;;
            esac ;;
        cmd) [ -n "$2" ] && send_cmd "${*:2}" && info "已发送命令: ${*:2}" || echo "用法: mc.sh player cmd <命令>" ;;
        *)  echo "用法: mc.sh player <list|op|deop|ban|unban|whitelist|cmd>" ;;
    esac
}

player_list() {
    echo -e "${CYAN}=== 玩家列表 ===${NC}"
    if [ ! -f "$GAME_DIR/usercache.json" ]; then
        warn "usercache.json 不存在"; return
    fi
    printf "%-20s %-40s %s\n" "玩家名" "UUID" "最后登录"
    echo "------------------------------------------------------------------------"
    python3 -c "
import json
with open('$GAME_DIR/usercache.json') as f:
    players = json.load(f)
for p in sorted(players, key=lambda x: x.get('expiresOn',''), reverse=True):
    print(f\"{p['name']:<20s} {p['uuid']:<40s} {p.get('expiresOn','N/A')}\")
" 2>/dev/null || {
        grep -oP '"name"\s*:\s*"\K[^"]+' "$GAME_DIR/usercache.json" | while read -r name; do
            echo "  $name"
        done
    }
}

# ==================== Mod 管理 ====================
cmd_mods() {
    case "${1:-list}" in
        list)  mods_list ;;
        check) mods_check ;;
        *)     echo "用法: mc.sh mods <list|check>" ;;
    esac
}

mods_list() {
    echo -e "${CYAN}=== 已安装 Mod 列表 ===${NC}"
    printf "%-50s %10s\n" "Mod 文件" "大小"
    echo "--------------------------------------------------------------"
    local total=0
    for jar in "$GAME_DIR/mods"/*.jar; do
        [ -f "$jar" ] || continue
        printf "%-50s %10s\n" "$(basename "$jar")" "$(du -h "$jar" | cut -f1)"
        ((total++))
    done
    echo "--------------------------------------------------------------"
    echo "共 $total 个 Mod"
}

mods_check() {
    echo -e "${CYAN}=== Mod 健康检查 ===${NC}"
    local issues=0

    for jar in "$GAME_DIR/mods"/*.jar; do
        [ -f "$jar" ] || continue
        if [ ! -s "$jar" ]; then
            warn "空文件: $(basename "$jar")"; ((issues++))
        fi
    done

    local names
    names=$(ls "$GAME_DIR/mods"/*.jar 2>/dev/null | xargs -I{} basename {} | sed 's/-[0-9].*//' | sort | uniq -d)
    if [ -n "$names" ]; then
        echo "$names" | while read -r n; do
            warn "可能重复的 Mod: $n"
            ls "$GAME_DIR/mods"/${n}-* 2>/dev/null | xargs -I{} basename {} | sed 's/^/  /'
        done
        ((issues++))
    fi

    if ! ls "$GAME_DIR/mods"/easyauth-*.jar &>/dev/null; then
        warn "缺少 EasyAuth 登录认证 mod（离线模式必需）"; ((issues++))
    fi

    [ "$issues" -eq 0 ] && info "所有检查通过 ✓"
}

# ==================== 日志管理 ====================
cmd_logs() {
    case "${1:-tail}" in
        tail)   logs_tail ;;
        search) shift; logs_search "$@" ;;
        crash)  logs_crash ;;
        *)      echo "用法: mc.sh logs <tail|search <关键词>|crash>" ;;
    esac
}

logs_tail() {
    if [ ! -f "$GAME_DIR/logs/latest.log" ]; then
        error "日志文件不存在"; return
    fi
    info "实时日志 (Ctrl+C 退出)"
    tail -f "$GAME_DIR/logs/latest.log"
}

logs_search() {
    if [ -z "$1" ]; then echo "用法: mc.sh logs search <关键词>"; return; fi
    info "搜索日志: $*"
    grep -rni --color=auto "$*" "$GAME_DIR/logs/latest.log" 2>/dev/null | tail -50
    echo "---"
    echo "共 $(grep -ci "$*" "$GAME_DIR/logs/latest.log" 2>/dev/null || echo 0) 条匹配"
}

logs_crash() {
    echo -e "${CYAN}=== 崩溃报告 ===${NC}"
    local crash_dir="$GAME_DIR/crash-reports"
    if [ ! -d "$crash_dir" ] || [ -z "$(ls "$crash_dir"/*.txt 2>/dev/null)" ]; then
        info "暂无崩溃报告"; return
    fi
    echo "最近的崩溃报告:"
    ls -t "$crash_dir"/*.txt 2>/dev/null | head -10 | while read -r f; do
        echo "  $(basename "$f")"
    done
    echo ""
    local latest
    latest=$(ls -t "$crash_dir"/*.txt 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
        info "最新崩溃报告 ($(basename "$latest")):"
        head -30 "$latest"
    fi
}

# ==================== 主入口 ====================
show_help() {
    cat << 'EOF'
MickeyMiao's Minecraft Server 管理工具

用法: mc.sh <命令> [参数]

服务器管理:
  start              启动服务器
  stop               优雅关闭服务器
  restart            重启服务器
  status             查看服务器状态
  console            附加到服务器控制台
  monitor            服务器监控面板
  check              仅运行环境检查

备份管理:
  backup create      创建冷备份
  backup list        列出所有备份
  backup clean [天]  清理旧备份

玩家管理:
  player list                    列出所有玩家
  player op/deop <玩家名>        管理OP权限
  player ban/unban <玩家名>      封禁/解封
  player whitelist <on|off|add|remove> [玩家名]
  player cmd <命令>              发送任意命令

Mod 管理:
  mods list          列出已安装 Mod
  mods check         Mod 健康检查

日志:
  logs tail          实时查看日志
  logs search <词>   搜索日志
  logs crash         查看崩溃报告

配置文件: config.json
EOF
}

require_running() {
    if ! is_running; then
        error "服务器未在运行，此命令需要服务器运行中"
        exit 1
    fi
}

case "${1:-help}" in
    start)   cmd_start ;;
    stop)    cmd_stop ;;
    restart) cmd_restart ;;
    status)  cmd_status ;;
    console) cmd_console ;;
    monitor) cmd_monitor ;;
    check)   preflight_check ;;
    backup)  shift; cmd_backup "$@" ;;
    player)
        shift
        case "$1" in
            list|help|"") ;;
            *) require_running ;;
        esac
        cmd_player "$@" ;;
    mods)    shift; cmd_mods "$@" ;;
    logs)    shift; cmd_logs "$@" ;;
    help|*)  show_help ;;
esac
