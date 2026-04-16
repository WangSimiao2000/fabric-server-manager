#!/bin/bash
# 定时重启 + 冷备份脚本（由 cron 每天调用）
# 警告时间等参数从 config.json 读取
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$BASE_DIR/config.json"
MC="$SCRIPT_DIR/mc.sh"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

WARN_MIN=$(python3 -c "
import json
with open('$CONFIG_FILE') as f: c = json.load(f)
print(c['restart']['warn_minutes'])
" 2>/dev/null || echo 5)

log "=== 定时重启开始 (警告时间: ${WARN_MIN}分钟) ==="

if "$MC" status 2>/dev/null | grep -q "运行中"; then
    log "发送重启警告..."
    "$MC" player cmd "say §e[自动维护] 服务器将在${WARN_MIN}分钟后重启"

    if [ "$WARN_MIN" -gt 1 ]; then
        sleep $(( (WARN_MIN - 1) * 60 ))
        "$MC" player cmd "say §c[自动维护] 服务器将在1分钟后重启"
    fi

    sleep 50
    "$MC" player cmd "say §c[自动维护] 服务器将在10秒后重启！"
    sleep 10

    log "关闭服务器..."
    "$MC" stop
    sleep 5
fi

# 等待完全停止
timeout=30
while "$MC" status 2>/dev/null | grep -q "运行中" && [ $timeout -gt 0 ]; do
    sleep 1; ((timeout--))
done

# 冷备份
log "开始冷备份..."
"$MC" backup create

# 清理旧备份
log "清理旧备份..."
"$MC" backup clean

# 启动
log "启动服务器..."
"$MC" start

log "=== 定时重启完成 ==="
