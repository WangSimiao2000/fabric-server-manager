#!/bin/bash
# 测试 acquire_lock 并发锁
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"

suite "acquire_lock 互斥"

# 测试：第一个进程持有锁时，第二个进程应失败
LOCK_FILE="$TMP_DIR/test.lock"

# 子 shell 中获取锁并持有 2 秒
(
    exec 200>"$LOCK_FILE"
    flock -n 200 || exit 1
    sleep 2
) &
HOLDER_PID=$!
sleep 0.2  # 等待锁被获取

# 尝试获取同一把锁，应失败
(
    exec 200>"$LOCK_FILE"
    flock -n 200
)
SECOND_EXIT=$?
assert_eq "$SECOND_EXIT" "1" "第二个进程获取锁失败 (exit 1)"

# 等待持有者释放
wait $HOLDER_PID 2>/dev/null

# 锁释放后应能获取
(
    exec 200>"$LOCK_FILE"
    flock -n 200
)
THIRD_EXIT=$?
assert_eq "$THIRD_EXIT" "0" "锁释放后可以获取 (exit 0)"

suite "acquire_lock 锁文件创建"
BASE_DIR="$TMP_DIR"
LOCK_FILE="$TMP_DIR/.mc.lock"
source "$SCRIPT_DIR/common.sh"
# 在子 shell 中调用 acquire_lock 避免影响当前进程
(acquire_lock) 2>/dev/null
assert_ok "锁文件被创建" test -f "$LOCK_FILE"

suite "acquire_lock 幂等性"
# 同一进程中连续调用两次不应死锁
result=$( (
    BASE_DIR="$TMP_DIR"
    LOCK_FILE="$TMP_DIR/.mc.lock"
    _MC_LOCK_HELD=0
    source "$SCRIPT_DIR/common.sh"
    acquire_lock
    acquire_lock  # 第二次应直接跳过
    echo "OK"
) 2>&1)
assert_contains "$result" "OK" "连续两次 acquire_lock 不死锁"

summary
