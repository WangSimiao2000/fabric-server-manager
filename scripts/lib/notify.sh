#!/bin/bash
# ============================================================
# Fabric Server Manager - 通知函数库（Python smtplib 发邮件）
# ============================================================

send_notify() {
    local subject="$1" body="$2"
    local enabled; enabled=$(cfg notify.enabled 2>/dev/null)
    [ "$enabled" != "true" ] && return 0

    python3 "$(dirname "${BASH_SOURCE[0]}")/send_email.py" "$subject" "$body" "$CONFIG_FILE"
}

notify_test() {
    send_notify "[MC服务器] 通知测试" "这是一封测试邮件，如果你收到了说明通知配置正确。\n\n服务器: $(hostname)\n时间: $(date '+%Y-%m-%d %H:%M:%S')"
}
