#!/bin/bash
# 集成测试：preflight_check 各种环境缺失
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

setup_env() {
    rm -rf "$TMP_DIR/game"
    BASE_DIR="$TMP_DIR"; GAME_DIR="$TMP_DIR/game"; BACKUP_DIR="$TMP_DIR/backups"
    CONFIG_FILE="$TMP_DIR/config.json"; LOCK_FILE="$TMP_DIR/.mc.lock"
    mkdir -p "$GAME_DIR/mods" "$BACKUP_DIR"
    cat > "$CONFIG_FILE" << 'CONF'
{"server":{"session_name":"mc_test","fabric_jar":"fabric-server-mc.1.21.4-loader.0.16.14-launcher.1.0.3.jar","java_opts":"","user":"mc","stop_countdown":0,"port":25565},
 "backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},
 "check":{"disk_warn_mb":1,"require_easyauth":false},"notify":{"enabled":false}}
CONF
    source "$SCRIPT_DIR/common.sh"
    source "$SCRIPT_DIR/lib/server.sh"
    load_config
    touch "$GAME_DIR/$FABRIC_JAR"
    echo "eula=true" > "$GAME_DIR/eula.txt"
    echo "online-mode=false" > "$GAME_DIR/server.properties"
}

suite "preflight_check 全部通过"
setup_env
# 需要 java 和 tmux 才能测试完整通过路径
if ! command -v java &>/dev/null || ! command -v tmux &>/dev/null; then
    echo "  (跳过: 需要 java 和 tmux)"
else
    out=$(preflight_check 2>&1); ret=$?
    assert_eq "$ret" "0" "返回 0"
    assert_contains "$out" "所有检查通过" "输出通过信息"
fi

suite "preflight_check 缺少 GameFile"
setup_env; rm -rf "$GAME_DIR"
out=$(preflight_check 2>&1) || true
assert_contains "$out" "GameFile 目录不存在" "检测到缺失"

suite "preflight_check 缺少 Fabric jar"
setup_env; rm -f "$GAME_DIR/$FABRIC_JAR"
out=$(preflight_check 2>&1) || true
assert_contains "$out" "jar 不存在" "检测到缺失"

suite "preflight_check EULA 未同意"
setup_env; echo "eula=false" > "$GAME_DIR/eula.txt"
out=$(preflight_check 2>&1) || true
assert_contains "$out" "EULA 未同意" "检测到未同意"

suite "preflight_check 缺少 server.properties"
setup_env; rm -f "$GAME_DIR/server.properties"
out=$(preflight_check 2>&1) || true
assert_contains "$out" "server.properties 不存在" "检测到缺失"

suite "preflight_check EasyAuth 缺失警告"
setup_env; REQUIRE_EASYAUTH="true"
out=$(preflight_check 2>&1) || true
assert_contains "$out" "EasyAuth 未安装" "检测到缺失"

suite "preflight_check 多个错误累计"
setup_env; rm -f "$GAME_DIR/$FABRIC_JAR"; echo "eula=false" > "$GAME_DIR/eula.txt"
out=$(preflight_check 2>&1); ret=$?
assert_eq "$ret" "1" "多错误返回 1"
assert_contains "$out" "严重问题" "报告问题数"

summary
