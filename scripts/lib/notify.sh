#!/bin/bash
# ============================================================
# Fabric Server Manager - 通知函数库（Python smtplib 发邮件）
# ============================================================

send_notify() {
    local subject="$1" body="$2"
    local enabled; enabled=$(cfg notify.enabled 2>/dev/null)
    [ "$enabled" != "true" ] && return 0

    python3 -c "
import sys, json, smtplib
from email.mime.text import MIMEText

subject = sys.argv[1]
body = sys.argv[2].replace(r'\n', '\n')
with open(sys.argv[3]) as f: cfg = json.load(f)
e = cfg['notify']['email']
msg = MIMEText(body, 'plain', 'utf-8')
msg['From'], msg['To'], msg['Subject'] = e['from'], e['to'], subject
try:
    port = int(e['smtp_port'])
    if port == 465:
        s = smtplib.SMTP_SSL(e['smtp_host'], port, timeout=10)
    else:
        s = smtplib.SMTP(e['smtp_host'], port, timeout=10)
        s.starttls()
    s.login(e['from'], e['password'])
    s.sendmail(e['from'], [e['to']], msg.as_string())
    s.quit()
    print('[NOTIFY] 邮件已发送: ' + subject)
except Exception as ex:
    print('[NOTIFY] 邮件发送失败: ' + str(ex), file=sys.stderr)
    sys.exit(1)
" "$subject" "$body" "$CONFIG_FILE"
}

notify_test() {
    send_notify "[MC服务器] 通知测试" "这是一封测试邮件，如果你收到了说明通知配置正确。\n\n服务器: $(hostname)\n时间: $(date '+%Y-%m-%d %H:%M:%S')"
}
