"""发送邮件通知（由 notify.sh 调用）。

用法: python3 send_email.py <subject> <body> <config.json>
根据 config.json 中 notify.email 配置发送邮件。
端口 465 使用 SSL，其他端口使用 STARTTLS。
"""
import sys, json, smtplib
from email.mime.text import MIMEText

subject = sys.argv[1]
body = sys.argv[2].replace(r'\n', '\n')

with open(sys.argv[3]) as f:
    cfg = json.load(f)
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
