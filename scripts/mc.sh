#!/bin/bash
# ============================================================
# MickeyMiao's Minecraft Server 管理工具
# 统一入口 - 所有功能通过子命令调用
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 加载公共函数和模块
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/server.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/player.sh"
source "$SCRIPT_DIR/lib/mods.sh"

load_config

# ==================== 帮助 ====================
show_help() {
    cat << 'EOF'
MickeyMiao's Minecraft Server 管理工具

用法: mc.sh <命令> [参数]

服务器管理:
  start                启动服务器（含环境预检查）
  stop                 优雅关闭（倒计时通知玩家）
  restart              重启
  status               查看状态/内存/运行时间
  console              进入服务器控制台（Ctrl+B D 退出）
  monitor              监控面板
  check                仅运行环境检查

版本升级与回退:
  upgrade              查找所有 Mod 都兼容的最新版本
  upgrade <版本>       升级到指定版本（如: mc.sh upgrade 1.21.6）
  rollback             回退到升级前的版本

备份管理:
  backup create        创建冷备份
  backup list          列出所有备份
  backup clean [天数]  清理旧备份
  backup restore       从冷备份一键恢复

玩家管理:
  player list                    列出所有历史玩家
  player op/deop <玩家名>        管理 OP 权限
  player ban/unban <玩家名>      封禁/解封
  player whitelist on/off        开关白名单
  player whitelist add/remove <玩家名>  管理白名单
  player cmd <命令>              发送任意服务器命令

Mod 和日志:
  mods list            列出已安装 Mod
  mods check           Mod 健康检查
  logs tail            实时查看日志
  logs search <关键词> 搜索日志
  logs crash           查看崩溃报告

配置文件: config.json（修改后无需重启，下次执行自动生效）
EOF
}

# ==================== 路由 ====================
require_running() {
    if ! is_running; then
        error "服务器未在运行，此命令需要服务器运行中"
        exit 1
    fi
}

case "${1:-help}" in
    start)    cmd_start ;;
    stop)     cmd_stop ;;
    restart)  cmd_restart ;;
    status)   cmd_status ;;
    console)  cmd_console ;;
    monitor)  cmd_monitor ;;
    check)    preflight_check ;;
    backup)   shift; cmd_backup "$@" ;;
    player)
        shift
        case "${1:-}" in
            list|help|"") ;;
            *) require_running ;;
        esac
        cmd_player "$@" ;;
    mods)     shift; cmd_mods "$@" ;;
    upgrade)  shift; bash "$SCRIPT_DIR/upgrade.sh" "$@" ;;
    rollback) cmd_rollback ;;
    logs)     shift; cmd_logs "$@" ;;
    help|*)   show_help ;;
esac
