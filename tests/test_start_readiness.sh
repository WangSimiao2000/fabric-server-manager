#!/bin/bash
# 测试 cmd_start 的"就绪判定"
#
# 背景（2026-10-08 实际故障）：
#   1. 旧实现为 `sleep 3 + is_running` 即判定启动成功。当 .fabric 被删除时，
#      fabric-server-*.jar 退化为安装器模式去外网下载，进程可存活数十秒后退出，
#      脚本却已报"服务器已启动"，掩盖真实错误。
#   2. 改为等待日志出现 "Done (" 后，又踩到第二个坑：MC 启动时会轮转
#      latest.log（旧文件压缩归档、新建空文件），启动前记录的字节偏移会超出
#      新文件长度，导致永远读不到 "Done ("，误报"未就绪"。
# 本测试锁定这两种情形，外加"陈旧 Done 不得被误判"与"进程根本没起来"。
source "$(dirname "$0")/framework.sh"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

export GAME_DIR="$TMP_DIR/GameFile"
export SCRIPT_DIR="$REPO_DIR/scripts"
export BASE_DIR="$TMP_DIR"
mkdir -p "$GAME_DIR/logs"
LOG="$GAME_DIR/logs/latest.log"
UP="$TMP_DIR/up"          # 标记文件：存在即视为进程存活
SENT="$TMP_DIR/sent"      # send_cmd 记录（命令替换在子 shell 中，变量会丢）

CONFIG_FILE="$TMP_DIR/config.json"
cat > "$CONFIG_FILE" << 'EOF'
{"server":{"session_name":"mctest","fabric_jar":"test.jar","java_opts":"","user":"mc","stop_countdown":0,"port":25599,
           "spawn":{"x":1,"y":2,"z":3}},
 "backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},
 "restart":{"warn_minutes":0},
 "check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false},
 "watchdog":{"crash_threshold":3,"crash_window_minutes":10}}
EOF

source "$SCRIPT_DIR/common.sh"
load_config
source "$SCRIPT_DIR/lib/server.sh"

export MC_START_READY_TIMEOUT=6   # 缩短超时，避免测试等待 120s

# ---------- 公共桩 ----------
preflight_check() { return 0; }
get_pid() { echo 12345; }
ss() { echo ""; }                                  # 端口未被占用
is_running() { [ -f "$UP" ]; }                     # 有状态：由各场景的 tmux 桩控制
send_cmd() { echo "$1" >> "$SENT"; }
reset() { rm -f "$UP" "$SENT"; : > "$SENT"; }

# ---------- 场景 1：日志被轮转后仍能识别就绪 ----------
suite "场景1 启动时轮转 latest.log，仍应判定就绪"
reset
printf '[old] 上一次运行的内容\n[old] Done (9.99s)! For help, type "help"\n' > "$LOG"
tmux() {
    touch "$UP"
    # 模拟 MC 启动：删除旧日志并新建（inode 变化），2 秒后写入本次的 Done
    ( rm -f "$LOG"
      printf '[new] Starting minecraft server\n' > "$LOG"
      sleep 2
      printf '[new] Done (3.9s)! For help, type "help"\n' >> "$LOG" ) >/dev/null 2>&1 &
}
OUT=$(cmd_start 2>&1); RC=$?
assert_eq "$RC" "0" "返回成功"
assert_contains "$OUT" "服务器已启动" "报告已启动"
assert_contains "$(cat "$SENT")" "setworldspawn 1 2 3" "就绪后同步出生点"

# ---------- 场景 2：进程存活过 3 秒后退出，必须判定失败 ----------
suite "场景2 进程启动后退出，必须报失败而非成功"
reset
printf '[old] 上一次运行的内容\n' > "$LOG"
tmux() {
    touch "$UP"
    # 新日志有启动输出但永不出现 Done；5 秒后进程"退出"（晚于 cmd_start 的 sleep 3）
    ( rm -f "$LOG"
      printf '[new] Downloading Minecraft server\n' > "$LOG"
      sleep 5
      rm -f "$UP" ) >/dev/null 2>&1 &
}
OUT=$(cmd_start 2>&1); RC=$?
assert_fail "返回非 0" "[ $RC -eq 0 ]"
assert_contains "$OUT" "进程已退出" "明确指出进程已退出"
assert_eq "$(cat "$SENT")" "" "失败时不应发送 setworldspawn"

# ---------- 场景 3：上一次的 Done 不得被当作本次就绪 ----------
suite "场景3 陈旧 Done 不得误判为本次就绪"
reset
# 日志不轮转、不新增内容，仅保留上一次的 Done
printf '[old] Done (9.99s)! For help, type "help"\n' > "$LOG"
tmux() { touch "$UP"; }                            # 进程存活但不产生任何新日志
OUT=$(cmd_start 2>&1); RC=$?
assert_fail "返回非 0" "[ $RC -eq 0 ]"
assert_contains "$OUT" "未就绪" "超时后报未就绪"
assert_eq "$(cat "$SENT")" "" "未就绪时不应发送 setworldspawn"

# ---------- 场景 4：进程根本没起来 ----------
suite "场景4 进程在 3 秒内就没起来"
reset
: > "$LOG"
tmux() { :; }                                      # 不 touch UP，is_running 始终为假
OUT=$(cmd_start 2>&1); RC=$?
assert_fail "返回非 0" "[ $RC -eq 0 ]"
assert_contains "$OUT" "启动失败" "报启动失败"
assert_eq "$(cat "$SENT")" "" "失败时不应发送 setworldspawn"

summary
