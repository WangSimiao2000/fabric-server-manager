#!/bin/bash
# 集成测试：backup_create + 恢复往返
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

BASE_DIR="$TMP_DIR"
GAME_DIR="$TMP_DIR/GameFile"
BACKUP_DIR="$TMP_DIR/backups"
CONFIG_FILE="$TMP_DIR/config.json"
LOCK_FILE="$TMP_DIR/.mc.lock"
mkdir -p "$GAME_DIR/world/playerdata" "$GAME_DIR/mods" "$GAME_DIR/config" "$GAME_DIR/EasyAuth" "$BACKUP_DIR"

cat > "$CONFIG_FILE" << 'EOF'
{"server":{"session_name":"mc_test_bk","fabric_jar":"test.jar","java_opts":"","user":"mc","stop_countdown":0,"port":25565},
 "backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},
 "check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}
EOF

echo "level-dat-content" > "$GAME_DIR/world/level.dat"
echo "player1-data" > "$GAME_DIR/world/playerdata/p1.dat"
echo "mod-content" > "$GAME_DIR/mods/fabric-api.jar"
echo "srv-config" > "$GAME_DIR/config/srv.conf"
echo "easyauth-db" > "$GAME_DIR/EasyAuth/db.db"
echo "port=25565" > "$GAME_DIR/server.properties"
for f in ops.json banned-players.json banned-ips.json whitelist.json usercache.json; do
    echo "[]" > "$GAME_DIR/$f"
done

source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/backup.sh"
load_config
is_running() { return 1; }

suite "backup_create 创建有效备份"
backup_create > /dev/null 2>&1
bf=$(ls -t "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | head -1)
assert_ok "备份文件已创建" test -f "$bf"
assert_ok "备份文件非空" test -s "$bf"

suite "备份内容完整"
contents=$(tar -tzf "$bf")
assert_contains "$contents" "world/level.dat" "包含 world"
assert_contains "$contents" "world/playerdata/p1.dat" "包含玩家数据"
assert_contains "$contents" "mods/fabric-api.jar" "包含 mods"
assert_contains "$contents" "config/srv.conf" "包含 config"
assert_contains "$contents" "EasyAuth/db.db" "包含 EasyAuth"
assert_contains "$contents" "server.properties" "包含 server.properties"

suite "恢复往返：修改后恢复"
echo "modified" > "$GAME_DIR/world/level.dat"
echo "new-mod" > "$GAME_DIR/mods/new.jar"
rm -f "$GAME_DIR/config/srv.conf"
tar -xzf "$bf" -C "$GAME_DIR"
assert_eq "$(cat "$GAME_DIR/world/level.dat")" "level-dat-content" "world 已恢复"
assert_eq "$(cat "$GAME_DIR/mods/fabric-api.jar")" "mod-content" "mods 已恢复"
assert_ok "config 已恢复" test -f "$GAME_DIR/config/srv.conf"

suite "backup_create exclude 规则"
cat > "$CONFIG_FILE" << 'EOF'
{"server":{"session_name":"mc_test_bk","fabric_jar":"test.jar","java_opts":"","user":"mc","stop_countdown":0,"port":25565},
 "backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":["world/playerdata"]},
 "check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}
EOF
load_config
backup_create > /dev/null 2>&1
bf2=$(ls -t "$BACKUP_DIR"/mc-backup-*.tar.gz 2>/dev/null | head -1)
c2=$(tar -tzf "$bf2")
assert_contains "$c2" "world/level.dat" "排除规则下仍含 world"
assert_fail "playerdata 被排除" echo "$c2" \| grep -q "playerdata"

summary
