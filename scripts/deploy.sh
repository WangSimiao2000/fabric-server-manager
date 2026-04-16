#!/bin/bash
# MC_Server 一键部署脚本 - 在目标设备上运行
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$BASE_DIR/config.json"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
step()  { echo -e "\n${CYAN}=== $1 ===${NC}"; }

echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║  MickeyMiao's MC Server 部署工具        ║"
echo "  ║  MC 1.21.5 + Fabric | 离线模式          ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

if [ ! -f "$CONFIG_FILE" ]; then
    error "找不到 config.json: $CONFIG_FILE"; exit 1
fi
info "配置文件: $CONFIG_FILE"

step "1/4 安装系统依赖"
bash "$SCRIPT_DIR/install-deps.sh"

step "2/4 清理无用文件"
bash "$SCRIPT_DIR/cleanup.sh"

step "3/4 安装 EasyAuth 登录认证"
bash "$SCRIPT_DIR/setup-easyauth.sh"

step "4/4 安装系统服务"
chmod +x "$SCRIPT_DIR"/*.sh
echo "是否安装 systemd 服务和 cron 定时重启？(y/n)"
read -r answer
if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    sudo bash "$SCRIPT_DIR/install-service.sh"
else
    warn "跳过，稍后运行: sudo bash $SCRIPT_DIR/install-service.sh"
fi

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}部署完成！${NC}                              ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "快速开始:"
echo "  启动服务器:   $SCRIPT_DIR/mc.sh start"
echo "  查看状态:     $SCRIPT_DIR/mc.sh status"
echo "  进入控制台:   $SCRIPT_DIR/mc.sh console"
echo "  查看帮助:     $SCRIPT_DIR/mc.sh help"
echo ""
echo "重要提醒:"
echo "  1. 首次启动后执行 /auth setSpawn 设置登录等待点"
echo "  2. 通知玩家首次进服需要 /register <密码> <密码>"
echo "  3. 配置修改: $CONFIG_FILE"
echo "  4. 详细文档: $BASE_DIR/docs/README.md"
