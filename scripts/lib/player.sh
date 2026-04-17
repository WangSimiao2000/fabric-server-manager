#!/bin/bash
# 玩家管理

cmd_player() {
    case "${1:-help}" in
        list) player_list ;;
        op)
            if [ -z "$2" ]; then echo "用法: mc.sh player op <玩家名>"
            else send_cmd "op $2"; info "已给予 $2 OP 权限"; fi ;;
        deop)
            if [ -z "$2" ]; then echo "用法: mc.sh player deop <玩家名>"
            else send_cmd "deop $2"; info "已移除 $2 OP 权限"; fi ;;
        ban)
            if [ -z "$2" ]; then echo "用法: mc.sh player ban <玩家名> [原因]"
            else send_cmd "ban $2 ${*:3}"; info "已封禁 $2"; fi ;;
        unban)
            if [ -z "$2" ]; then echo "用法: mc.sh player unban <玩家名>"
            else send_cmd "pardon $2"; info "已解封 $2"; fi ;;
        whitelist)
            case "$2" in
                on)  send_cmd "whitelist on"; info "白名单已启用" ;;
                off) send_cmd "whitelist off"; info "白名单已关闭" ;;
                add)
                    if [ -z "$3" ]; then echo "用法: mc.sh player whitelist add <玩家名>"
                    else send_cmd "whitelist add $3"; info "已添加 $3 到白名单"; fi ;;
                remove)
                    if [ -z "$3" ]; then echo "用法: mc.sh player whitelist remove <玩家名>"
                    else send_cmd "whitelist remove $3"; info "已从白名单移除 $3"; fi ;;
                *) echo "用法: mc.sh player whitelist <on|off|add|remove> [玩家名]" ;;
            esac ;;
        cmd)
            if [ -z "$2" ]; then echo "用法: mc.sh player cmd <命令>"
            else send_cmd "${*:2}"; info "已发送命令: ${*:2}"; fi ;;
        *) echo "用法: mc.sh player <list|op|deop|ban|unban|whitelist|cmd>" ;;
    esac
}

player_list() {
    echo -e "${CYAN}=== 玩家列表 ===${NC}"
    [ ! -f "$GAME_DIR/usercache.json" ] && { warn "usercache.json 不存在"; return; }
    printf "%-20s %-40s %s\n" "玩家名" "UUID" "最后登录"
    echo "------------------------------------------------------------------------"
    python3 -c "
import json, sys
with open(sys.argv[1] + '/usercache.json') as f:
    players = json.load(f)
for p in sorted(players, key=lambda x: x.get('expiresOn',''), reverse=True):
    print(f\"{p['name']:<20s} {p['uuid']:<40s} {p.get('expiresOn','N/A')}\")
" "$GAME_DIR" 2>/dev/null || {
        grep -oP '"name"\s*:\s*"\K[^"]+' "$GAME_DIR/usercache.json" | while read -r name; do
            echo "  $name"
        done
    }
}
