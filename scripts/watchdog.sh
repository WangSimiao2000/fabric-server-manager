#!/bin/bash
# ============================================================
# Fabric Server Manager - Watchdog 看门狗
# 由 cron 每分钟调用，检测 crash 和反复重启
#
# 状态机:
#   running  → 服务器正常运行中
#   stopped  → 检测到意外停止，尝试自动重启
#   notified → 窗口内反复崩溃超阈值，停止重启并通知人工介入
#
# 转换规则:
#   running  + 服务器在线   → running（无操作）
#   running  + 服务器离线   → stopped（记录崩溃 + 通知 + 重启）
#   stopped  + 崩溃超阈值   → notified（通知 + 停止重启）
#   stopped/notified         → 不报警（人为关闭或已通知）
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/notify.sh"
load_config

WATCHDOG_DIR="$BASE_DIR/.watchdog"
CRASH_LOG="$WATCHDOG_DIR/crashes.log"
STATE_FILE="$WATCHDOG_DIR/state"
mkdir -p "$WATCHDOG_DIR"

CRASH_THRESHOLD=$(cfg watchdog.crash_threshold 2>/dev/null || echo 3)
CRASH_WINDOW=$(cfg watchdog.crash_window_minutes 2>/dev/null || echo 10)

# 原子写入状态文件（tmp + mv 防止竞态）
write_state() {
    local tmp; tmp=$(mktemp "$WATCHDOG_DIR/state.XXXXXX")
    echo "$1" > "$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

# 读取上次状态
read_state() {
    cat "$STATE_FILE" 2>/dev/null || echo "unknown"
}

# 记录一次崩溃时间戳
record_crash() {
    date +%s >> "$CRASH_LOG"
}

# 统计窗口内崩溃次数
count_recent_crashes() {
    local cutoff=$(( $(date +%s) - CRASH_WINDOW * 60 ))
    local count=0
    if [ -f "$CRASH_LOG" ]; then
        while read -r ts; do
            [ "$ts" -ge "$cutoff" ] 2>/dev/null && ((count++))
        done < "$CRASH_LOG"
    fi
    echo "$count"
}

# 获取最近崩溃报告摘要
get_crash_summary() {
    local latest
    latest=$(ls -t "$GAME_DIR/crash-reports/"*.txt 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
        echo "\n--- 最近崩溃报告 ---\n$(head -20 "$latest")"  # 取前 20 行作为摘要
    fi
}

# 清理过期的崩溃记录
cleanup_old_records() {
    [ ! -f "$CRASH_LOG" ] && return
    local cutoff=$(( $(date +%s) - CRASH_WINDOW * 60 ))
    local tmp; tmp=$(mktemp)
    while read -r ts; do
        [ "$ts" -ge "$cutoff" ] 2>/dev/null && echo "$ts"
    done < "$CRASH_LOG" > "$tmp"
    mv "$tmp" "$CRASH_LOG"
}

# 处理崩溃事件
handle_crash() {
    local recent="$1" crash_info="$2"
    local hostname; hostname=$(hostname)
    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [ "$recent" -ge "$CRASH_THRESHOLD" ]; then
        # 反复崩溃超阈值 → notified，停止自动重启
        write_state "notified"
        send_notify \
            "[MC服务器] ⚠️ 反复崩溃警告" \
            "服务器在 ${CRASH_WINDOW} 分钟内崩溃了 ${recent} 次！\n\n服务器: ${hostname}\n时间: ${timestamp}\n\n已停止自动重启，请人工检查。${crash_info}"
    else
        # 单次崩溃 → 通知并尝试重启
        send_notify \
            "[MC服务器] 服务器意外停止" \
            "服务器已意外停止，正在尝试自动重启...\n\n服务器: ${hostname}\n时间: ${timestamp}\n窗口内崩溃次数: ${recent}/${CRASH_THRESHOLD}${crash_info}"
        "$SCRIPT_DIR/mc.sh" start
    fi
}

# ==================== 主逻辑 ====================

main() {
    local last_state; last_state=$(read_state)

    # 服务器在线 → 标记 running，无需操作
    if is_running; then
        write_state "running"
        return 0
    fi

    # 服务器离线 + 上次已是 stopped/notified → 人为关闭或已通知，不报警
    if [ "$last_state" = "stopped" ] || [ "$last_state" = "notified" ]; then
        return 0
    fi

    # 服务器离线 + 上次是 running/unknown → 意外停止
    write_state "stopped"
    record_crash

    local recent; recent=$(count_recent_crashes)
    local crash_info; crash_info=$(get_crash_summary)
    handle_crash "$recent" "$crash_info"
    cleanup_old_records
}

main
