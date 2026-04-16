#!/bin/bash
# 测试 required_java_version()
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
BASE_DIR="$TMP_DIR"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
source "$SCRIPT_DIR/common.sh"

suite "required_java_version() Java 21 (MC 1.21+)"
assert_eq "$(required_java_version '1.21')" "21" "MC 1.21"
assert_eq "$(required_java_version '1.21.4')" "21" "MC 1.21.4"
assert_eq "$(required_java_version '1.21.11')" "21" "MC 1.21.11"
assert_eq "$(required_java_version '1.22.0')" "21" "MC 1.22.0"

suite "required_java_version() Java 21 (MC 1.20.5+)"
assert_eq "$(required_java_version '1.20.5')" "21" "MC 1.20.5"
assert_eq "$(required_java_version '1.20.6')" "21" "MC 1.20.6"

suite "required_java_version() Java 17 (MC 1.18-1.20.4)"
assert_eq "$(required_java_version '1.18')" "17" "MC 1.18"
assert_eq "$(required_java_version '1.19.4')" "17" "MC 1.19.4"
assert_eq "$(required_java_version '1.20.4')" "17" "MC 1.20.4"
assert_eq "$(required_java_version '1.20')" "17" "MC 1.20"

suite "required_java_version() Java 16 (MC 1.17)"
assert_eq "$(required_java_version '1.17')" "16" "MC 1.17"
assert_eq "$(required_java_version '1.17.1')" "16" "MC 1.17.1"

suite "required_java_version() Java 8 (MC 1.16 及以下)"
assert_eq "$(required_java_version '1.16.5')" "8" "MC 1.16.5"
assert_eq "$(required_java_version '1.12.2')" "8" "MC 1.12.2"

suite "required_java_version() 从 FABRIC_JAR 推断"
FABRIC_JAR="fabric-server-mc.1.21.4-loader.0.16.14-launcher.1.0.3.jar"
assert_eq "$(required_java_version)" "21" "无参数时从 FABRIC_JAR 推断"

summary
