#!/bin/bash
# 定时重启 + 冷备份脚本（由 cron 每天调用）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
MC="$SCRIPT_DIR/mc.sh"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# 加锁防止并发
acquire_lock
# 让子进程（mc.sh）跳过锁获取，因为本进程已持有锁
export _MC_LOCK_HELD=1

WARN_MIN=$(cfg restart.warn_minutes 2>/dev/null || echo 5)

log "=== 定时重启开始 (警告时间: ${WARN_MIN}分钟) ==="

if "$MC" status 2>/dev/null | grep -q "运行中"; then
    log "发送重启警告..."
    "$MC" player cmd "say §e[自动维护] 服务器将在${WARN_MIN}分钟后重启"

    if [ "$WARN_MIN" -gt 1 ]; then
        sleep $(( (WARN_MIN - 1) * 60 ))
        "$MC" player cmd "say §c[自动维护] 服务器将在1分钟后重启"
    fi

    sleep 50  # 最后 1 分钟的前 50 秒静默等待
    "$MC" player cmd "say §c[自动维护] 服务器将在10秒后重启！"
    sleep 10  # 最后 10 秒倒计时

    log "关闭服务器..."
    "$MC" stop
    sleep 5  # 等待 stop 命令被 tmux 发送并处理
fi

# 等待完全停止（通过轮询 mc.sh status，不能复用 wait_stop 因为是跨进程调用）
timeout=30  # 最多等待 30 秒
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
