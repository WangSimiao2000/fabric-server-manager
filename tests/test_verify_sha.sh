#!/bin/bash
# 测试 verify_sha()
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"
source "$SCRIPT_DIR/common.sh"

# 创建测试文件
TEST_FILE="$TMP_DIR/testfile"
echo -n "hello world" > "$TEST_FILE"
SHA1_CORRECT=$(sha1sum "$TEST_FILE" | cut -d' ' -f1)
SHA512_CORRECT=$(sha512sum "$TEST_FILE" | cut -d' ' -f1)

suite "verify_sha() SHA1"
assert_ok "正确 SHA1 通过" verify_sha "$TEST_FILE" "$SHA1_CORRECT" sha1
assert_fail "错误 SHA1 失败" verify_sha "$TEST_FILE" "0000000000000000000000000000000000000000" sha1

suite "verify_sha() SHA512"
assert_ok "正确 SHA512 通过" verify_sha "$TEST_FILE" "$SHA512_CORRECT" sha512
assert_fail "错误 SHA512 失败" verify_sha "$TEST_FILE" "0000" sha512

suite "verify_sha() 默认算法"
assert_ok "默认使用 SHA1" verify_sha "$TEST_FILE" "$SHA1_CORRECT"

suite "verify_sha() 空 hash 跳过"
assert_ok "空 expected 直接返回成功" verify_sha "$TEST_FILE" ""

summary
