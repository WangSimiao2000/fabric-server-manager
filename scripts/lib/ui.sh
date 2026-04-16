#!/bin/bash
# Fabric Server Manager - TUI 交互界面 (whiptail/dialog)

# 自动选择 TUI 工具
if command -v whiptail &>/dev/null; then
    TUI=whiptail
elif command -v dialog &>/dev/null; then
    TUI=dialog
else
    error "需要 whiptail 或 dialog，请先安装"; exit 1
fi

TITLE="Fabric Server Manager"
W=60 H=20

# ==================== 工具函数 ====================
tui_menu() {
    local title="$1"; shift
    $TUI --title "$TITLE" --menu "$title" $H $W 10 "$@" 3>&1 1>&2 2>&3
}

tui_msg() { $TUI --title "$TITLE" --msgbox "$1" 10 $W; }
tui_yesno() { $TUI --title "$TITLE" --yesno "$1" 10 $W; }
tui_input() { $TUI --title "$TITLE" --inputbox "$1" 10 $W "$2" 3>&1 1>&2 2>&3; }

# 捕获命令输出并显示
tui_run() {
    local output
    output=$("$@" 2>&1)
    $TUI --title "$TITLE" --scrolltext --msgbox "$output" 22 70
}

# ==================== 状态栏 ====================
get_status_line() {
    if is_running; then
        echo "● 运行中 (PID: $(get_pid))"
    else
        echo "○ 未运行"
    fi
}

# ==================== 主菜单 ====================
ui_main() {
    while true; do
        local status
        status=$(get_status_line)
        local choice
        choice=$(tui_menu "状态: $status" \
            "status"   "查看服务器状态" \
            "start"    "启动服务器" \
            "stop"     "停止服务器" \
            "restart"  "重启服务器" \
            "console"  "进入控制台" \
            "backup"   "备份管理 ▸" \
            "player"   "玩家管理 ▸" \
            "mods"     "Mod 管理 ▸" \
            "logs"     "日志查看 ▸" \
            "upgrade"  "版本升级" \
            "rollback" "版本回退" \
            "check"    "环境检查") || break
        case "$choice" in
            status)   tui_run cmd_status ;;
            start)    tui_run cmd_start ;;
            stop)     tui_yesno "确认停止服务器？" && tui_run cmd_stop ;;
            restart)  tui_yesno "确认重启服务器？" && tui_run cmd_restart ;;
            console)  cmd_console ;;
            backup)   ui_backup ;;
            player)   ui_player ;;
            mods)     ui_mods ;;
            logs)     ui_logs ;;
            upgrade)  clear; bash "$SCRIPT_DIR/upgrade.sh"; read -rp "按回车返回..." ;;
            rollback) tui_yesno "确认回退到上一个版本？" && { clear; cmd_rollback; read -rp "按回车返回..."; } ;;
            check)    tui_run preflight_check ;;
        esac
    done
}

# ==================== 备份管理 ====================
ui_backup() {
    while true; do
        local choice
        choice=$(tui_menu "备份管理" \
            "create"  "创建冷备份" \
            "list"    "列出所有备份" \
            "clean"   "清理旧备份" \
            "restore" "从备份恢复") || return
        case "$choice" in
            create)  tui_yesno "创建冷备份？" && tui_run backup_create ;;
            list)    tui_run backup_list ;;
            clean)
                local days
                days=$(tui_input "清理多少天前的备份？" "$BACKUP_KEEP_DAYS") || continue
                tui_run backup_clean "$days" ;;
            restore) clear; backup_restore; read -rp "按回车返回..." ;;
        esac
    done
}

# ==================== 玩家管理 ====================
ui_player() {
    while true; do
        local choice
        choice=$(tui_menu "玩家管理" \
            "list"      "列出所有玩家" \
            "op"        "给予 OP 权限" \
            "deop"      "移除 OP 权限" \
            "ban"       "封禁玩家" \
            "unban"     "解封玩家" \
            "whitelist" "白名单管理 ▸" \
            "cmd"       "发送服务器命令") || return
        case "$choice" in
            list) tui_run player_list ;;
            op|deop|ban|unban)
                local name
                name=$(tui_input "输入玩家名:") || continue
                [ -z "$name" ] && continue
                tui_run cmd_player "$choice" "$name" ;;
            whitelist) ui_whitelist ;;
            cmd)
                local cmd
                cmd=$(tui_input "输入服务器命令:") || continue
                [ -z "$cmd" ] && continue
                tui_run cmd_player cmd "$cmd" ;;
        esac
    done
}

ui_whitelist() {
    while true; do
        local choice
        choice=$(tui_menu "白名单管理" \
            "on"     "启用白名单" \
            "off"    "关闭白名单" \
            "add"    "添加玩家" \
            "remove" "移除玩家") || return
        case "$choice" in
            on|off) tui_run cmd_player whitelist "$choice" ;;
            add|remove)
                local name
                name=$(tui_input "输入玩家名:") || continue
                [ -z "$name" ] && continue
                tui_run cmd_player whitelist "$choice" "$name" ;;
        esac
    done
}

# ==================== Mod 管理 ====================
ui_mods() {
    while true; do
        local choice
        choice=$(tui_menu "Mod 管理" \
            "list"  "列出已安装 Mod" \
            "check" "Mod 健康检查") || return
        case "$choice" in
            list)  tui_run mods_list ;;
            check) tui_run mods_check ;;
        esac
    done
}

# ==================== 日志查看 ====================
ui_logs() {
    while true; do
        local choice
        choice=$(tui_menu "日志查看" \
            "tail"   "实时查看日志" \
            "search" "搜索日志" \
            "crash"  "查看崩溃报告") || return
        case "$choice" in
            tail)   clear; logs_tail ;;
            search)
                local keyword
                keyword=$(tui_input "输入搜索关键词:") || continue
                [ -z "$keyword" ] && continue
                tui_run logs_search "$keyword" ;;
            crash) tui_run logs_crash ;;
        esac
    done
}

cmd_ui() { ui_main; }
