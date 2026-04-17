#!/bin/bash
# 测试跨进程锁继承（mc-restart.sh 调用 mc.sh 的场景）
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
echo '{"server":{"session_name":"mc","fabric_jar":"test","java_opts":"","user":"mc","stop_countdown":10,"port":25565},"backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},"check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}' > "$CONFIG_FILE"

suite "环境变量 _MC_LOCK_HELD 不被 common.sh 覆盖"
# 模拟父进程 export _MC_LOCK_HELD=1 后子进程 source common.sh
result=$(
    export _MC_LOCK_HELD=1
    BASE_DIR="$TMP_DIR"
    source "$SCRIPT_DIR/common.sh"
    echo "$_MC_LOCK_HELD"
)
assert_eq "$result" "1" "export _MC_LOCK_HELD=1 在 source common.sh 后保留"

suite "跨进程锁继承：子进程跳过锁获取"
# 父进程持有 flock，子进程通过 _MC_LOCK_HELD=1 跳过
LOCK_FILE="$TMP_DIR/.mc.lock"
(
    # 父进程：获取 flock
    exec 200>"$LOCK_FILE"
    flock -n 200 || exit 99

    # 子进程：继承 _MC_LOCK_HELD=1，应成功跳过锁
    child_result=$(
        export _MC_LOCK_HELD=1
        export BASE_DIR="$TMP_DIR"
        export CONFIG_FILE="$TMP_DIR/config.json"
        bash -c "source '$SCRIPT_DIR/common.sh'; acquire_lock; echo OK" 2>&1
    )
    echo "$child_result"
) > "$TMP_DIR/child_out" 2>&1
assert_contains "$(cat "$TMP_DIR/child_out")" "OK" "子进程继承 _MC_LOCK_HELD=1 后跳过锁"

suite "跨进程锁继承：无环境变量时子进程应被阻止"
# 用独立后台进程持有锁，然后在另一个独立进程中尝试获取
# common.sh 中 LOCK_FILE 固定为 $BASE_DIR/.mc.lock，所以用同一路径
REAL_LOCK="$TMP_DIR/.mc.lock"
bash -c "exec 200>'$REAL_LOCK'; flock -n 200 || exit 1; sleep 2" &
HOLDER=$!
sleep 0.3

# 独立子进程（无 _MC_LOCK_HELD）尝试获取同一把锁，应失败
child_out=$(
    unset _MC_LOCK_HELD
    export BASE_DIR="$TMP_DIR"
    export CONFIG_FILE="$TMP_DIR/config.json"
    bash -c "source '$SCRIPT_DIR/common.sh'; acquire_lock && echo OK" 2>&1
) || true
assert_fail "子进程无 _MC_LOCK_HELD 时被锁阻止" echo "$child_out" \| grep -qF OK
wait $HOLDER 2>/dev/null

summary
