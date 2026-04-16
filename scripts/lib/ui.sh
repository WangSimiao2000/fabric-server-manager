#!/bin/bash
# Fabric Server Manager - TUI 交互界面 (gum)

check_gum() {
    if ! command -v gum &>/dev/null; then
        error "需要 gum，请先安装: https://github.com/charmbracelet/gum"
        exit 1
    fi
}

# ==================== 工具函数 ====================
tui_choose() {
    gum choose --header="$1" "${@:2}"
}

tui_confirm() {
    gum confirm "$1"
}

tui_input() {
    gum input --placeholder="$1"
}

tui_run() {
    local output
    output=$("$@" 2>&1)
    # 去掉 ANSI 颜色码后用 pager 显示
    echo "$output" | sed 's/\x1b\[[0-9;]*m//g' | gum pager
}

tui_header() {
    local status
    if is_running; then
        status="● 运行中 (PID: $(get_pid))"
    else
        status="○ 未运行"
    fi
    gum style --border rounded --padding "0 2" --border-foreground 39 \
        "🧱 Fabric Server Manager" \
        "状态: $status"
}

# ==================== 主菜单 ====================
ui_main() {
    check_gum
    while true; do
        clear
        tui_header
        echo ""
        local choice
        choice=$(tui_choose "选择操作:" \
            "📊 查看状态" \
            "▶️  启动服务器" \
            "⏹️  停止服务器" \
            "🔄 重启服务器" \
            "🖥️  进入控制台" \
            "💾 备份管理" \
            "👥 玩家管理" \
            "🧩 Mod 管理" \
            "📋 日志查看" \
            "⬆️  版本升级" \
            "⬇️  版本回退" \
            "🔍 环境检查" \
            "❌ 退出") || break
        case "$choice" in
            *查看状态*)   tui_run cmd_status ;;
            *启动*)       tui_run cmd_start ;;
            *停止*)       tui_confirm "确认停止服务器？" && tui_run cmd_stop ;;
            *重启*)       tui_confirm "确认重启服务器？" && tui_run cmd_restart ;;
            *控制台*)     cmd_console ;;
            *备份*)       ui_backup ;;
            *玩家*)       ui_player ;;
            *Mod*)        ui_mods ;;
            *日志*)       ui_logs ;;
            *升级*)       clear; trap '' INT; bash "$SCRIPT_DIR/upgrade.sh"; trap - INT; read -rp "按回车返回..." ;;
            *回退*)       tui_confirm "确认回退到上一个版本？" && { clear; cmd_rollback; read -rp "按回车返回..."; } ;;
            *环境检查*)   tui_run preflight_check ;;
            *退出*)       break ;;
        esac
    done
}

# ==================== 备份管理 ====================
ui_backup() {
    while true; do
        local choice
        choice=$(tui_choose "备份管理:" \
            "📦 创建冷备份" \
            "📋 列出所有备份" \
            "🧹 清理旧备份" \
            "♻️  从备份恢复" \
            "↩️  返回") || return
        case "$choice" in
            *创建*)  tui_confirm "创建冷备份？" && tui_run backup_create ;;
            *列出*)  tui_run backup_list ;;
            *清理*)
                local days
                days=$(tui_input "清理天数 (默认 $BACKUP_KEEP_DAYS)") || continue
                tui_run backup_clean "${days:-$BACKUP_KEEP_DAYS}" ;;
            *恢复*)  clear; backup_restore; read -rp "按回车返回..." ;;
            *返回*)  return ;;
        esac
    done
}

# ==================== 玩家管理 ====================
ui_player() {
    while true; do
        local choice
        choice=$(tui_choose "玩家管理:" \
            "📋 列出所有玩家" \
            "⭐ 给予 OP" \
            "❌ 移除 OP" \
            "🚫 封禁玩家" \
            "✅ 解封玩家" \
            "📝 白名单管理" \
            "💬 发送命令" \
            "↩️  返回") || return
        case "$choice" in
            *列出*)   tui_run player_list ;;
            *给予*)
                local name; name=$(tui_input "玩家名") || continue
                [ -n "$name" ] && tui_run cmd_player op "$name" ;;
            *移除*)
                local name; name=$(tui_input "玩家名") || continue
                [ -n "$name" ] && tui_run cmd_player deop "$name" ;;
            *封禁*)
                local name; name=$(tui_input "玩家名") || continue
                [ -n "$name" ] && tui_run cmd_player ban "$name" ;;
            *解封*)
                local name; name=$(tui_input "玩家名") || continue
                [ -n "$name" ] && tui_run cmd_player unban "$name" ;;
            *白名单*) ui_whitelist ;;
            *命令*)
                local cmd; cmd=$(tui_input "服务器命令") || continue
                [ -n "$cmd" ] && tui_run cmd_player cmd "$cmd" ;;
            *返回*)   return ;;
        esac
    done
}

ui_whitelist() {
    while true; do
        local choice
        choice=$(tui_choose "白名单管理:" \
            "✅ 启用白名单" \
            "❌ 关闭白名单" \
            "➕ 添加玩家" \
            "➖ 移除玩家" \
            "↩️  返回") || return
        case "$choice" in
            *启用*) tui_run cmd_player whitelist on ;;
            *关闭*) tui_run cmd_player whitelist off ;;
            *添加*)
                local name; name=$(tui_input "玩家名") || continue
                [ -n "$name" ] && tui_run cmd_player whitelist add "$name" ;;
            *移除*)
                local name; name=$(tui_input "玩家名") || continue
                [ -n "$name" ] && tui_run cmd_player whitelist remove "$name" ;;
            *返回*) return ;;
        esac
    done
}

# ==================== Mod 管理 ====================
ui_mods() {
    while true; do
        local choice
        choice=$(tui_choose "Mod 管理:" \
            "📋 列出已安装 Mod" \
            "🔍 Mod 健康检查" \
            "↩️  返回") || return
        case "$choice" in
            *列出*)   tui_run mods_list ;;
            *健康*)   tui_run mods_check ;;
            *返回*)   return ;;
        esac
    done
}

# ==================== 日志查看 ====================
ui_logs() {
    while true; do
        local choice
        choice=$(tui_choose "日志查看:" \
            "📜 实时查看日志" \
            "🔍 搜索日志" \
            "💥 查看崩溃报告" \
            "↩️  返回") || return
        case "$choice" in
            *实时*)   clear; trap '' INT; logs_tail; trap - INT ;;
            *搜索*)
                local keyword; keyword=$(tui_input "搜索关键词") || continue
                [ -n "$keyword" ] && tui_run logs_search "$keyword" ;;
            *崩溃*)   tui_run logs_crash ;;
            *返回*)   return ;;
        esac
    done
}

cmd_ui() { ui_main; }
