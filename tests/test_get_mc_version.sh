#!/bin/bash
# 测试 get_mc_version()
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

# 最小化 source：只需要 get_mc_version 函数
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
source "$SCRIPT_DIR/common.sh"

suite "get_mc_version() 标准格式"
assert_eq "$(get_mc_version 'fabric-server-mc.1.21.4-loader.0.16.14-launcher.1.0.3.jar')" "1.21.4" "三段版本号"
assert_eq "$(get_mc_version 'fabric-server-mc.1.21-loader.0.16.14-launcher.1.0.3.jar')" "1.21" "两段版本号"
assert_eq "$(get_mc_version 'fabric-server-mc.1.20.5-loader.0.15.0-launcher.1.0.3.jar')" "1.20.5" "1.20.5"
assert_eq "$(get_mc_version 'fabric-server-mc.1.17-loader.0.11.0-launcher.1.0.3.jar')" "1.17" "1.17 两段"

suite "get_mc_version() 边界情况"
assert_eq "$(get_mc_version 'fabric-server-mc.1.21.11-loader.0.19.2-launcher.1.0.3.jar')" "1.21.11" "两位 patch 版本"
assert_eq "$(get_mc_version 'no-version-here.jar')" "" "无版本号返回空"

suite "get_mc_version() 从 FABRIC_JAR 变量读取"
FABRIC_JAR="fabric-server-mc.1.21.4-loader.0.16.14-launcher.1.0.3.jar"
assert_eq "$(get_mc_version)" "1.21.4" "无参数时从 FABRIC_JAR 读取"

summary
