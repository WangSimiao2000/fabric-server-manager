#!/bin/bash
# Mod 管理、日志查看、监控面板

# ==================== Mod 管理 ====================
cmd_mods() {
    case "${1:-list}" in
        list)  mods_list ;;
        check) mods_check ;;
        *)     echo "用法: mc.sh mods <list|check>" ;;
    esac
}

mods_list() {
    echo -e "${CYAN}=== 已安装 Mod 列表 ===${NC}"
    printf "%-50s %10s\n" "Mod 文件" "大小"
    echo "--------------------------------------------------------------"
    local total=0
    for jar in "$GAME_DIR/mods"/*.jar; do
        [ -f "$jar" ] || continue
        printf "%-50s %10s\n" "$(basename "$jar")" "$(du -h "$jar" | cut -f1)"
        ((total++))
    done
    echo "--------------------------------------------------------------"
    echo "共 $total 个 Mod"
}

mods_check() {
    echo -e "${CYAN}=== Mod 健康检查 ===${NC}"
    local issues=0

    for jar in "$GAME_DIR/mods"/*.jar; do
        [ -f "$jar" ] || continue
        [ ! -s "$jar" ] && { warn "空文件: $(basename "$jar")"; ((issues++)); }
    done

    local names
    names=$(ls "$GAME_DIR/mods"/*.jar 2>/dev/null | xargs -I{} basename {} | sed 's/-[0-9].*//' | sort | uniq -d)
    if [ -n "$names" ]; then
        echo "$names" | while read -r n; do
            warn "可能重复的 Mod: $n"
            ls "$GAME_DIR/mods"/${n}-* 2>/dev/null | xargs -I{} basename {} | sed 's/^/  /'
        done
        ((issues++))
    fi

    ls "$GAME_DIR/mods"/easyauth-*.jar &>/dev/null || { warn "缺少 EasyAuth 登录认证 mod（离线模式必需）"; ((issues++)); }
    [ "$issues" -eq 0 ] && info "所有检查通过 ✓"
}

# ==================== 日志管理 ====================
cmd_logs() {
    case "${1:-tail}" in
        tail)   logs_tail ;;
        search) shift; logs_search "$@" ;;
        crash)  logs_crash ;;
        *)      echo "用法: mc.sh logs <tail|search <关键词>|crash>" ;;
    esac
}

logs_tail() {
    [ ! -f "$GAME_DIR/logs/latest.log" ] && { error "日志文件不存在"; return; }
    info "实时日志 (Ctrl+C 退出)"
    tail -f "$GAME_DIR/logs/latest.log"
}

logs_search() {
    [ -z "$1" ] && { echo "用法: mc.sh logs search <关键词>"; return; }
    info "搜索日志: $*"
    grep -rni --color=auto "$*" "$GAME_DIR/logs/latest.log" 2>/dev/null | tail -50
    echo "---"
    echo "共 $(grep -ci "$*" "$GAME_DIR/logs/latest.log" 2>/dev/null || echo 0) 条匹配"
}

logs_crash() {
    echo -e "${CYAN}=== 崩溃报告 ===${NC}"
    local crash_dir="$GAME_DIR/crash-reports"
    if [ ! -d "$crash_dir" ] || [ -z "$(ls "$crash_dir"/*.txt 2>/dev/null)" ]; then
        info "暂无崩溃报告"; return
    fi
    echo "最近的崩溃报告:"
    ls -t "$crash_dir"/*.txt 2>/dev/null | head -10 | while read -r f; do echo "  $(basename "$f")"; done
    echo ""
    local latest
    latest=$(ls -t "$crash_dir"/*.txt 2>/dev/null | head -1)
    [ -n "$latest" ] && { info "最新崩溃报告 ($(basename "$latest")):"; head -30 "$latest"; }
}

# ==================== 监控 ====================
cmd_monitor() {
    echo -e "${CYAN}=== 服务器监控面板 ===${NC}"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    cmd_status
    echo ""

    echo -e "${CYAN}--- 备份信息 ---${NC}"
    local latest_cold
    latest_cold=$(ls -t "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | head -1)
    if [ -n "$latest_cold" ]; then
        echo "  最近冷备份: $(basename "$latest_cold") ($(stat -c '%y' "$latest_cold" 2>/dev/null | cut -d. -f1))"
    else
        echo "  最近冷备份: 无"
    fi

    echo ""
    echo -e "${CYAN}--- 最近错误日志 ---${NC}"
    if [ -f "$GAME_DIR/logs/latest.log" ]; then
        grep -i 'error\|exception\|crash' "$GAME_DIR/logs/latest.log" 2>/dev/null | tail -5 | sed 's/^/  /'
        local err_count
        err_count=$(grep -ci 'error\|exception' "$GAME_DIR/logs/latest.log" 2>/dev/null || echo 0)
        echo "  (共 $err_count 条错误/异常)"
    else
        echo "  无日志文件"
    fi
}
