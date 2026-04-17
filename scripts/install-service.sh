#!/bin/bash
# 安装 MC 服务器 systemd 服务和 cron 定时重启
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"

if [ "$EUID" -ne 0 ]; then
    echo "请使用 sudo 运行此脚本"; exit 1
fi

SERVER_USER=$(cfg server.user)
SESSION_NAME=$(cfg server.session_name)
FABRIC_JAR=$(cfg server.fabric_jar)
JAVA_OPTS=$(cfg server.java_opts)
STOP_COUNTDOWN=$(cfg server.stop_countdown)
CRON_SCHEDULE=$(cfg restart.cron)
GAME_DIR="$BASE_DIR/GameFile"
MC_VERSION=$(get_mc_version)

# 自动生成 systemd service 文件
echo "生成 systemd 服务文件..."
cat > /etc/systemd/system/mc-server.service << EOF
[Unit]
Description=Minecraft Fabric Server ($MC_VERSION)
After=network.target

[Service]
Type=forking
User=$SERVER_USER
WorkingDirectory=$GAME_DIR
RemainAfterExit=yes
ExecStart=/usr/bin/tmux new-session -ds $SESSION_NAME -c $GAME_DIR "java $JAVA_OPTS -jar $FABRIC_JAR nogui"
# ExecStop 分步优雅关闭：通知 → 等待 → stop → 等待保存 → 清理
# -前缀表示忽略该步失败，确保后续步骤继续执行
ExecStop=-/usr/bin/tmux send-keys -t $SESSION_NAME "say §c服务器将在${STOP_COUNTDOWN}秒后关闭..." Enter
ExecStop=-/bin/sleep $STOP_COUNTDOWN
ExecStop=-/usr/bin/tmux send-keys -t $SESSION_NAME "stop" Enter
ExecStop=-/bin/sleep 15
ExecStop=-/usr/bin/tmux kill-session -t $SESSION_NAME
Restart=on-failure
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mc-server
echo "已安装并启用 mc-server 服务"

# 安装 cron 定时重启
CRON_CMD="$CRON_SCHEDULE $SCRIPT_DIR/mc-restart.sh >> $BASE_DIR/backups/restart.log 2>&1"
WATCHDOG_CMD="* * * * * $SCRIPT_DIR/watchdog.sh >> $BASE_DIR/.watchdog/watchdog.log 2>&1"
(sudo -u "$SERVER_USER" crontab -l 2>/dev/null | grep -v 'mc-restart.sh' | grep -v 'watchdog.sh'; echo "$CRON_CMD"; echo "$WATCHDOG_CMD") | sudo -u "$SERVER_USER" crontab -
echo "已添加 cron 定时重启: $CRON_SCHEDULE"
echo "已添加 cron watchdog: 每分钟检测"

# 设置权限
chmod +x "$SCRIPT_DIR"/*.sh

echo ""
echo "=== 安装完成 ==="
echo "  用户:     $SERVER_USER"
echo "  游戏目录: $GAME_DIR"
echo "  tmux 会话: $SESSION_NAME"
echo "  定时重启: $CRON_SCHEDULE"
echo ""
echo "  启动: systemctl start mc-server"
echo "  管理: $SCRIPT_DIR/mc.sh help"
