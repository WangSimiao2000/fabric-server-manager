#!/bin/bash
# 服务器启停、状态、控制台、预检查

preflight_check() {
    MIN_JAVA_VERSION=$(required_java_version)
    local errors=0 warnings=0

    echo -e "${CYAN}=== 环境与配置检查 ===${NC}"

    if [ -f "$CONFIG_FILE" ]; then
        info "config.json 已加载 ✓"
    else
        error "config.json 不存在"; ((errors++))
    fi

    if command -v java &>/dev/null; then
        local java_ver
        java_ver=$(java -version 2>&1 | head -1 | grep -oP '"\K[^"]+' | head -1 | cut -d. -f1)
        if [ "$java_ver" -ge "$MIN_JAVA_VERSION" ] 2>/dev/null; then
            info "Java 版本: $java_ver ✓"
        else
            error "Java 版本 $java_ver < $MIN_JAVA_VERSION"; ((errors++))
        fi
    else
        error "Java 未安装"; ((errors++))
    fi

    if command -v tmux &>/dev/null; then
        info "tmux 已安装 ✓"
    else
        error "tmux 未安装"; ((errors++))
    fi

    if [ -d "$GAME_DIR" ]; then
        info "GameFile 目录存在 ✓"
    else
        error "GameFile 目录不存在: $GAME_DIR"; ((errors++))
    fi

    if [ -f "$GAME_DIR/$FABRIC_JAR" ]; then
        info "Fabric 服务端存在 ✓"
    else
        error "Fabric jar 不存在: $FABRIC_JAR"; ((errors++))
    fi

    if grep -q 'eula=true' "$GAME_DIR/eula.txt" 2>/dev/null; then
        info "EULA 已同意 ✓"
    else
        error "EULA 未同意"; ((errors++))
    fi

    if [ -f "$GAME_DIR/server.properties" ]; then
        if grep -q 'online-mode=false' "$GAME_DIR/server.properties"; then
            info "离线模式已启用 ✓"
        else
            warn "online-mode 不是 false"; ((warnings++))
        fi
    else
        error "server.properties 不存在"; ((errors++))
    fi

    if ls "$GAME_DIR/mods"/easyauth-*.jar &>/dev/null; then
        info "EasyAuth 登录认证 mod 已安装 ✓"
    elif [ "$REQUIRE_EASYAUTH" = "true" ]; then
        warn "EasyAuth 未安装！离线模式下任何人可冒充其他玩家"; ((warnings++))
    fi

    local avail_mb
    avail_mb=$(df -m "$GAME_DIR" 2>/dev/null | awk 'NR==2{print $4}')
    if [ -n "$avail_mb" ]; then
        [ "$avail_mb" -lt "$DISK_WARN_MB" ] && { warn "磁盘剩余空间不足: ${avail_mb}MB"; ((warnings++)); } || info "磁盘剩余: ${avail_mb}MB ✓"
    fi

    echo ""
    if [ "$errors" -gt 0 ]; then
        error "发现 $errors 个严重问题，$warnings 个警告"; return 1
    elif [ "$warnings" -gt 0 ]; then
        warn "发现 $warnings 个警告，建议处理"; return 0
    else
        info "所有检查通过 ✓"; return 0
    fi
}

cmd_start() {
    preflight_check || { error "预检查未通过，无法启动"; exit 1; }
    if is_running; then
        warn "服务器已在运行中"; return 1
    fi
    local port
    port=$(cfg server.port)
    if ss -tlnp | grep -q ":${port} "; then
        error "端口 ${port} 已被占用:"; ss -tlnp | grep ":${port} "; return 1
    fi
    info "启动服务器..."

    # 同步 motd 配置到 server.properties 和 MiniMOTD
    python3 "$SCRIPT_DIR/lib/sync_motd.py" "$CONFIG_FILE" "$GAME_DIR" 2>/dev/null || true

    tmux new-session -ds "$SESSION_NAME" -c "$GAME_DIR" \
        "java $JAVA_OPTS -jar $FABRIC_JAR nogui"
    sleep 3  # 等待 tmux 会话和 Java 进程启动
    if is_running; then
        info "服务器已启动 (PID: $(get_pid))"
        # 同步出生点
        local sx sy sz
        sx=$(cfg server.spawn.x 2>/dev/null)
        sy=$(cfg server.spawn.y 2>/dev/null)
        sz=$(cfg server.spawn.z 2>/dev/null)
        if [ -n "$sx" ] && [ -n "$sy" ] && [ -n "$sz" ]; then
            local wait=0 log_size
            log_size=$(wc -c < "$GAME_DIR/logs/latest.log" 2>/dev/null || echo 0)
            # 只检查启动后新增的日志内容，避免匹配上次残留的 "Done"
            while [ $wait -lt 60 ]; do
                if tail -c +"$((log_size + 1))" "$GAME_DIR/logs/latest.log" 2>/dev/null | grep -q "Done ("; then break; fi
                sleep 1; wait=$((wait + 1))
            done
            send_cmd "setworldspawn $sx $sy $sz"
        fi
    else
        error "启动失败，请检查日志: $GAME_DIR/logs/latest.log"
    fi
}

cmd_stop() {
    if ! is_running; then
        warn "服务器未在运行"; return 1
    fi
    # 标记为正常关闭，避免 watchdog 误报
    mkdir -p "$BASE_DIR/.watchdog"
    local _tmp; _tmp=$(mktemp "$BASE_DIR/.watchdog/state.XXXXXX")
    echo "stopped" > "$_tmp"
    mv -f "$_tmp" "$BASE_DIR/.watchdog/state"
    info "正在关闭服务器 (${STOP_COUNTDOWN}秒倒计时)..."
    send_cmd "say §c服务器将在${STOP_COUNTDOWN}秒后关闭..."
    sleep "$STOP_COUNTDOWN"  # 等待倒计时结束
    send_cmd "stop"
    if wait_stop 30; then  # 最多等待 30 秒让服务器保存世界并退出
        info "服务器已关闭"
    else
        error "服务器未能在30秒内关闭，强制终止..."
        tmux kill-session -t "$SESSION_NAME" 2>/dev/null
    fi
}

cmd_restart() {
    if is_running; then cmd_stop; fi
    sleep 2  # 等待端口释放
    cmd_start
}

cmd_status() {
    echo -e "${CYAN}=== 服务器状态 ===${NC}"
    local mc_ver
    mc_ver=$(get_mc_version)
    [ -n "$mc_ver" ] && echo "  版本: Minecraft $mc_ver (Fabric)"
    if is_running; then
        local pid
        pid=$(get_pid)
        info "状态: 运行中 (PID: $pid)"
        # 用 top 两次采样获取实时 CPU（ps %cpu 是生命周期平均值，长时间运行后趋近 0）
        local cpu mem etime
        cpu=$(top -bn2 -d0.1 -p "$pid" 2>/dev/null | awk -v p="$pid" '$1==p {cpu=$9} END {print cpu}')
        mem=$(ps -p "$pid" -o %mem= 2>/dev/null | xargs)
        etime=$(ps -p "$pid" -o etime= 2>/dev/null | xargs)
        printf "  CPU: %s%%  内存: %s%%  运行时间: %s\n" "${cpu:-?}" "${mem:-?}" "${etime:-?}"
        local rss
        rss=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{printf "%.0f", $1/1024}')
        [ -n "$rss" ] && echo "  Java 实际内存: ${rss}MB"
        # 通过 SLP 协议查询在线玩家
        local ping_json port
        port=$(cfg server.port)
        if ping_json=$(python3 "$SCRIPT_DIR/lib/mc_ping.py" "${port:-25565}" 2>/dev/null); then
            local online max names
            online=$(echo "$ping_json" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['online'])")
            max=$(echo "$ping_json" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['max'])")
            names=$(echo "$ping_json" | python3 -c "import json,sys;d=json.load(sys.stdin);n=d.get('names',[]);print(', '.join(n) if n else '')")
            printf "  在线玩家: %s / %s" "$online" "$max"
            [ -n "$names" ] && printf "  [%s]" "$names"
            echo
        fi
    else
        warn "状态: 未运行"
    fi
    [ -d "$GAME_DIR/world" ] && echo "  世界大小: $(du -sh "$GAME_DIR/world" 2>/dev/null | cut -f1)"
    local mod_count
    mod_count=$(find "$GAME_DIR/mods" -maxdepth 1 -name '*.jar' 2>/dev/null | wc -l)
    echo "  已安装 Mod: ${mod_count} 个"
    df -h "$GAME_DIR" 2>/dev/null | awk 'NR==2{printf "  磁盘: 已用 %s / 总计 %s (剩余 %s)\n", $3, $2, $4}'
}

cmd_console() {
    if ! is_running; then
        error "服务器未在运行"; exit 1
    fi
    info "附加到服务器控制台 (按 Ctrl+B 然后 D 退出)"
    tmux attach -t "$SESSION_NAME"
}
