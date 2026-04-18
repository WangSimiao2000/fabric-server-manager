#!/bin/bash
# 测试 Bug 修复：tmux 启动时关闭 fd 200，防止 flock 锁被继承
# 背景：mc-restart.sh 持有 flock(fd 200)，调用 mc.sh start 启动 tmux，
#       如果 tmux 继承了 fd 200，锁永远不会释放，下次 mc-restart 无法获取锁。
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT
LOCK_FILE="$TMP_DIR/.mc.lock"

suite "server.sh tmux 命令带 200>&- 关闭锁 fd"
# tmux new-session 是多行续行命令，用 -A 取后续行一起匹配
line=$(grep -A2 'tmux new-session' "$SCRIPT_DIR/lib/server.sh" | grep -c '200>&-')
assert_eq "$line" "1" "tmux 启动命令包含 200>&-"

suite "子进程关闭 fd 200 后锁可被新进程获取"
# 模拟 mc-restart.sh 场景：
# 1. 父 shell 获取 flock
# 2. 启动子进程时用 200>&- 关闭 fd（模拟 tmux）
# 3. 父 shell 退出，释放自己的 fd
# 4. 新进程应能获取锁（因为子进程没继承 fd）
(
    exec 200>"$LOCK_FILE"
    flock -n 200
    # 模拟 tmux：子进程带 200>&- 启动，在后台存活
    bash -c "sleep 5" 200>&- &
    # 父 shell 退出，关闭自己的 fd 200
)
# 此时只有后台子进程存活，但它没有 fd 200
result=$(
    exec 200>"$LOCK_FILE"
    flock -n 200 && echo "acquired" || echo "blocked"
)
assert_eq "$result" "acquired" "200>&- 后新进程可获取锁"
# 清理后台进程
kill %1 2>/dev/null; wait 2>/dev/null

suite "子进程继承 fd 200 时锁不可获取（对照组）"
(
    exec 200>"$LOCK_FILE"
    flock -n 200
    # 子进程不带 200>&-，继承了 fd 200
    bash -c "sleep 5" &
)
# 父 shell 退出了，但子进程仍持有 fd 200 → 锁未释放
result=$(
    exec 200>"$LOCK_FILE"
    flock -n 200 && echo "acquired" || echo "blocked"
)
assert_eq "$result" "blocked" "不带 200>&- 时锁被子进程继承"
kill %1 2>/dev/null; wait 2>/dev/null

summary
