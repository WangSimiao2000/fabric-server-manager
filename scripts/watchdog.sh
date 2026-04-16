#!/bin/bash
# ============================================================
# Fabric Server Manager - Watchdog 看门狗
# 由 cron 每分钟调用，检测 crash 和反复重启
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

# 读取上次状态: running / stopped / notified
last_state=$(cat "$STATE_FILE" 2>/dev/null || echo "unknown")

if is_running; then
    echo "running" > "$STATE_FILE"
    exit 0
fi

# 服务器没在运行 —— 判断是正常关闭还是 crash

# 如果上次也是 stopped/notified，说明是人为关闭，不报警
if [ "$last_state" = "stopped" ] || [ "$last_state" = "notified" ]; then
    exit 0
fi

# 上次是 running，现在不在了 → 意外停止
echo "stopped" > "$STATE_FILE"

# 记录本次 crash 时间
date +%s >> "$CRASH_LOG"

# 统计窗口内 crash 次数
cutoff=$(( $(date +%s) - CRASH_WINDOW * 60 ))
recent=0
if [ -f "$CRASH_LOG" ]; then
    while read -r ts; do
        [ "$ts" -ge "$cutoff" ] 2>/dev/null && ((recent++))
    done < "$CRASH_LOG"
fi

# 获取最近的崩溃报告摘要
crash_info=""
latest_crash=$(ls -t "$GAME_DIR/crash-reports/"*.txt 2>/dev/null | head -1)
if [ -n "$latest_crash" ]; then
    crash_info="\n--- 最近崩溃报告 ---\n$(head -20 "$latest_crash")"
fi

hostname=$(hostname)
timestamp=$(date '+%Y-%m-%d %H:%M:%S')

if [ "$recent" -ge "$CRASH_THRESHOLD" ]; then
    # 反复崩溃
    echo "notified" > "$STATE_FILE"
    send_notify \
        "[MC服务器] ⚠️ 反复崩溃警告" \
        "服务器在 ${CRASH_WINDOW} 分钟内崩溃了 ${recent} 次！\n\n服务器: ${hostname}\n时间: ${timestamp}\n\n已停止自动重启，请人工检查。${crash_info}"
else
    # 单次崩溃，发通知并尝试重启
    send_notify \
        "[MC服务器] 服务器意外停止" \
        "服务器已意外停止，正在尝试自动重启...\n\n服务器: ${hostname}\n时间: ${timestamp}\n窗口内崩溃次数: ${recent}/${CRASH_THRESHOLD}${crash_info}"

    # 自动重启
    "$SCRIPT_DIR/mc.sh" start
fi

# 清理过期的 crash 记录
if [ -f "$CRASH_LOG" ]; then
    tmp=$(mktemp)
    while read -r ts; do
        [ "$ts" -ge "$cutoff" ] 2>/dev/null && echo "$ts"
    done < "$CRASH_LOG" > "$tmp"
    mv "$tmp" "$CRASH_LOG"
fi
