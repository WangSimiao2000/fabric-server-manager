#!/bin/bash
# 安装 MC 服务器 systemd 服务和 cron 定时重启
# 所有参数从 config.json 读取，路径自动检测
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$BASE_DIR/config.json"

if [ "$EUID" -ne 0 ]; then
    echo "请使用 sudo 运行此脚本"; exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 找不到 $CONFIG_FILE"; exit 1
fi

cfg() {
    python3 -c "
import json
with open('$CONFIG_FILE') as f: c = json.load(f)
keys = '$1'.split('.')
v = c
for k in keys: v = v[k]
print(v)
"
}

SERVER_USER=$(cfg server.user)
SESSION_NAME=$(cfg server.session_name)
FABRIC_JAR=$(cfg server.fabric_jar)
JAVA_OPTS=$(cfg server.java_opts)
STOP_COUNTDOWN=$(cfg server.stop_countdown)
CRON_SCHEDULE=$(cfg restart.cron)
GAME_DIR="$BASE_DIR/GameFile"
MC_VERSION=$(echo "$FABRIC_JAR" | grep -oP 'mc\.\K[0-9]+\.[0-9]+(\.[0-9]+)?')

# 创建用户（如果不存在）
if ! id -u "$SERVER_USER" &>/dev/null; then
    echo "创建用户: $SERVER_USER"
    useradd -r -m -d "$BASE_DIR" -s /bin/bash "$SERVER_USER"
fi

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
ExecStart=/usr/bin/tmux new-session -ds $SESSION_NAME -c $GAME_DIR "java $JAVA_OPTS -jar $FABRIC_JAR nogui"
ExecStop=/usr/bin/tmux send-keys -t $SESSION_NAME "say §c服务器将在${STOP_COUNTDOWN}秒后关闭..." Enter
ExecStop=/bin/sleep $STOP_COUNTDOWN
ExecStop=/usr/bin/tmux send-keys -t $SESSION_NAME "stop" Enter
ExecStop=/bin/sleep 15
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
(crontab -u "$SERVER_USER" -l 2>/dev/null | grep -v 'mc-restart.sh'; echo "$CRON_CMD") | crontab -u "$SERVER_USER" -
echo "已添加 cron 定时重启: $CRON_SCHEDULE"

# 设置权限
chown -R "$SERVER_USER":"$SERVER_USER" "$BASE_DIR"
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
