#!/bin/bash
# 备份管理：创建/列表/清理/恢复/回退

cmd_backup() {
    case "${1:-help}" in
        create)  backup_create ;;
        list)    backup_list ;;
        clean)   backup_clean "${2:-$BACKUP_KEEP_DAYS}" ;;
        restore) backup_restore "${2:-}" ;;
        *)       echo "用法: mc.sh backup <create|list|clean [天数]|restore [文件名]>" ;;
    esac
}

backup_ensure_space() {
    local needed_mb avail_mb
    needed_mb=$(du -sm "$GAME_DIR/world" 2>/dev/null | awk '{printf "%.0f", $1 / 2}')
    [ -z "$needed_mb" ] && needed_mb=500
    avail_mb=$(df -m "$BACKUP_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    [ -z "$avail_mb" ] && return 0

    while [ "$avail_mb" -lt "$needed_mb" ]; do
        local backup_count oldest
        backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -name 'mc-backup-*.tar.gz' 2>/dev/null | wc -l)
        if [ "$backup_count" -le "$BACKUP_MIN_KEEP" ]; then
            error "磁盘空间不足 (剩余 ${avail_mb}MB，需要 ${needed_mb}MB)，但仅剩 ${backup_count} 份备份(最少保留 ${BACKUP_MIN_KEEP})，拒绝删除"
            return 1
        fi
        oldest=$(ls -t "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | tail -1)
        [ -z "$oldest" ] && return 1
        warn "磁盘空间不足 (剩余 ${avail_mb}MB)，删除最早的备份: $(basename "$oldest")"
        rm -f "$oldest"
        avail_mb=$(df -m "$BACKUP_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    done
    info "磁盘空间充足: 剩余 ${avail_mb}MB，预估需要 ${needed_mb}MB"
}

backup_create() {
    mkdir -p "$BACKUP_DIR"
    backup_ensure_space || return 1

    local timestamp filename running=false
    timestamp=$(date +%Y%m%d_%H%M%S)
    filename="mc-backup-${timestamp}.tar.gz"

    if is_running; then
        running=true
        info "服务器运行中，暂停自动保存..."
        send_cmd "save-off"
        send_cmd "save-all flush"
        sleep 5  # 等待 save-all flush 完成磁盘写入
        # 确保 save-on 在任何退出/中断时恢复（正常返回 + 信号中断）
        _restore_save() { send_cmd "save-on"; info "已恢复自动保存"; trap - RETURN INT TERM; }
        trap '_restore_save' RETURN INT TERM
    fi

    local exclude_args=()
    mapfile -t exclude_args < <(python3 -c "
import json, sys
with open(sys.argv[1]) as f: c = json.load(f)
for e in c['backup']['exclude']:
    print(f'--exclude={e}')
" "$CONFIG_FILE" 2>/dev/null)

    info "创建备份: $filename"
    tar -czf "$BACKUP_DIR/$filename" \
        -C "$GAME_DIR" \
        "${exclude_args[@]}" \
        world server.properties ops.json banned-players.json banned-ips.json \
        whitelist.json usercache.json mods config EasyAuth 2>&1 | grep -v 'file changed as we read it' || true
    if [ ! -s "$BACKUP_DIR/$filename" ]; then
        error "备份失败: $BACKUP_DIR/$filename"
        return 1
    fi

    local size
    size=$(du -h "$BACKUP_DIR/$filename" | cut -f1)
    info "备份完成: $filename ($size)"

    if [ -n "$RSYNC_DEST" ]; then
        info "同步到远程: $RSYNC_DEST"
        rsync -az "$BACKUP_DIR/$filename" "$RSYNC_DEST" && info "远程同步完成" || warn "远程同步失败"
    fi
}

backup_list() {
    echo -e "${CYAN}=== 备份列表 ===${NC}"
    local files=()
    while IFS= read -r f; do
        files+=("$f")
    done < <(ls -t "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null)
    if [ ${#files[@]} -eq 0 ]; then
        warn "暂无备份"; return
    fi
    printf "%-40s %8s  %s\n" "文件名" "大小" "日期"
    echo "---------------------------------------------------------------"
    for f in "${files[@]}"; do
        printf "%-40s %8s  %s\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)" "$(stat -c '%y' "$f" 2>/dev/null | cut -d. -f1)"
    done
}

backup_clean() {
    local days=${1:-$BACKUP_KEEP_DAYS}
    info "清理 $days 天前的备份 (最少保留 $BACKUP_MIN_KEEP 份)..."

    # 收集所有备份（按时间排序，最新在前）
    local all=()
    while IFS= read -r f; do
        all+=("$f")
    done < <(ls -t "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null)
    local total=${#all[@]}

    # 收集过期备份
    local expired=()
    while IFS= read -r f; do
        expired+=("$f")
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name 'mc-backup-*.tar.gz' -mtime +"$days" 2>/dev/null)
    local candidates=${#expired[@]}

    local max_delete=$(( total - BACKUP_MIN_KEEP ))
    [ "$max_delete" -le 0 ] && { info "仅有 $total 份备份，不足最少保留数，跳过清理"; return; }
    local to_delete=$(( candidates < max_delete ? candidates : max_delete ))
    [ "$to_delete" -le 0 ] && { info "没有需要清理的备份"; return; }

    # 从最旧的过期备份开始删除
    local deleted=0
    for (( i=${#all[@]}-1; i>=0 && deleted<to_delete; i-- )); do
        local f="${all[$i]}"
        # 只删除过期的
        for e in "${expired[@]}"; do
            if [ "$f" = "$e" ]; then
                rm -f "$f"
                ((deleted++))
                break
            fi
        done
    done
    info "已删除 $deleted 个旧备份 (保留 $(( total - deleted )) 份)"
}

backup_restore() {
    local target="$1"

    if [ -z "$target" ]; then
        echo -e "${CYAN}=== 选择要恢复的备份 ===${NC}"
        local backups
        backups=$(ls -t "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null)
        [ -z "$backups" ] && { warn "暂无备份"; return 1; }
        local i=1
        while IFS= read -r f; do
            printf "  %d) %s (%s)\n" "$i" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
            ((i++))
        done <<< "$backups"
        echo ""
        read -rp "选择编号 (q 取消): " choice
        [ "$choice" = "q" ] && return 0
        target=$(echo "$backups" | sed -n "${choice}p")
        [ -z "$target" ] && { error "无效选择"; return 1; }
        target=$(basename "$target")
    fi

    local archive="$BACKUP_DIR/$target"
    [ ! -f "$archive" ] && archive="$target"
    [ ! -f "$archive" ] && { error "备份文件不存在: $target"; return 1; }

    warn "这将覆盖当前的: world、mods、config、server.properties 等"
    warn "当前数据会先自动备份一份"
    read -rp "确认恢复？(y/n) " answer
    [ "$answer" != "y" ] && { info "已取消"; return 0; }

    is_running && { info "关闭服务器..."; cmd_stop; sleep 3; }

    info "备份当前状态..."
    backup_create

    info "从备份恢复: $(basename "$archive")"
    tar -xzf "$archive" -C "$GAME_DIR"
    info "恢复完成"

    load_config
    [ ! -f "$GAME_DIR/$FABRIC_JAR" ] && warn "备份中的 Fabric jar ($FABRIC_JAR) 不存在，可能需要手动修复"

    rm -rf "$GAME_DIR/.fabric"
    info "启动服务器..."
    cmd_start
}

cmd_rollback() {
    local snapshots
    snapshots=$(ls -dt "$BACKUP_DIR"/pre-upgrade-* 2>/dev/null)
    [ -z "$snapshots" ] && { error "没有可用的升级快照"; return 1; }

    echo -e "${CYAN}=== 可用的升级快照 ===${NC}"
    local i=1
    while IFS= read -r snap; do
        local ver mod_count
        ver=$(cat "$snap/mc_version.txt" 2>/dev/null || echo "未知")
        mod_count=$(ls "$snap/mods"/*.jar 2>/dev/null | wc -l)
        printf "  %d) %s (MC %s, %d 个 Mod)\n" "$i" "$(basename "$snap")" "$ver" "$mod_count"
        ((i++))
    done <<< "$snapshots"

    echo ""
    read -rp "选择要回退的快照编号 (输入 q 取消): " choice
    [ "$choice" = "q" ] && return 0

    local target
    target=$(echo "$snapshots" | sed -n "${choice}p")
    [ -z "$target" ] || [ ! -d "$target" ] && { error "无效选择"; return 1; }

    local old_ver
    old_ver=$(cat "$target/mc_version.txt" 2>/dev/null || echo "未知")
    warn "将回退到 MC $old_ver ($(basename "$target"))"
    read -rp "确认回退？(y/n) " answer
    [ "$answer" != "y" ] && { info "已取消"; return 0; }

    is_running && { info "关闭服务器..."; cmd_stop; sleep 3; }

    local old_jar
    old_jar=$(ls "$target"/fabric-server-mc.*.jar 2>/dev/null | head -1)
    [ -n "$old_jar" ] && { rm -f "$GAME_DIR"/fabric-server-mc.*.jar; cp "$old_jar" "$GAME_DIR/"; info "已还原 Fabric 服务端"; }

    rm -rf "$GAME_DIR/mods"
    cp -r "$target/mods" "$GAME_DIR/mods"
    rm -rf "$GAME_DIR/mods.disabled"
    cp "$target/config.json" "$CONFIG_FILE"
    load_config
    rm -rf "$GAME_DIR/.fabric"

    [ -f /etc/systemd/system/mc-server.service ] && sudo bash "$SCRIPT_DIR/install-service.sh"

    info "启动服务器..."
    cmd_start
    info "已回退到 MC $old_ver"
}
