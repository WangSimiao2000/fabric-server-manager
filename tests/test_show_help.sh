#!/bin/bash
# 测试 show_help 输出
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
BASE_DIR="$TMP_DIR"; LOCK_FILE="$TMP_DIR/.mc.lock"; GAME_DIR="$TMP_DIR/GameFile"; mkdir -p "$GAME_DIR"
BACKUP_DIR="$TMP_DIR/backups"; mkdir -p "$BACKUP_DIR"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/server.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/player.sh"
source "$SCRIPT_DIR/lib/mods.sh"
source "$SCRIPT_DIR/lib/notify.sh"
load_config

# show_help 定义在 mc.sh 中，手动提取
show_help() {
    cat << 'EOF'
Fabric Server Manager - Minecraft 服务器管理工具

用法: mc.sh <命令> [参数]

服务器管理:
  start                启动服务器（含环境预检查）
  stop                 优雅关闭（倒计时通知玩家）
  restart              重启
  status               查看状态/内存/运行时间
  backup create        创建冷备份
  player list          列出所有历史玩家
  mods list            列出已安装 Mod
  logs search <关键词> 搜索日志
  upgrade              查找所有 Mod 都兼容的最新版本
  rollback             回退到升级前的版本
EOF
}

suite "show_help 包含关键命令"
out=$(show_help)
assert_contains "$out" "start" "包含 start"
assert_contains "$out" "stop" "包含 stop"
assert_contains "$out" "backup" "包含 backup"
assert_contains "$out" "player" "包含 player"
assert_contains "$out" "mods" "包含 mods"
assert_contains "$out" "logs" "包含 logs"
assert_contains "$out" "upgrade" "包含 upgrade"
assert_contains "$out" "rollback" "包含 rollback"
assert_contains "$out" "用法" "包含用法说明"

summary
