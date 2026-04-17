#!/bin/bash
# 测试 mc.sh status 输出的 PID/CPU/内存/RSS 合理性
# 防止 get_pid 返回错误进程（如 tmux server）导致指标全为 0
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
MC="$SCRIPT_DIR/mc.sh"

# 仅在服务器运行时测试
if ! "$MC" status 2>/dev/null | grep -q "运行中"; then
    suite "status 指标合理性（跳过：服务器未运行）"
    assert_ok "服务器未运行，跳过测试" true
    summary
    exit 0
fi

out=$("$MC" status 2>&1)

suite "status PID 是 java 进程"
pid=$(echo "$out" | grep -oP 'PID: \K[0-9]+')
assert_ok "PID 非空" test -n "$pid"
comm=$(ps -p "$pid" -o comm= 2>/dev/null)
assert_eq "$comm" "java" "PID $pid 是 java 进程（非 tmux）"

suite "status 内存指标合理"
mem_pct=$(echo "$out" | grep -oP '内存: \K[0-9.]+(?=%)' | head -1)
assert_ok "内存百分比非空" test -n "$mem_pct"
# Java -Xms4G+ 的服务器内存不可能是 0.0%
mem_nonzero=$(echo "$mem_pct" | awk '{print ($1 > 0.0) ? "yes" : "no"}')
assert_eq "$mem_nonzero" "yes" "内存 ${mem_pct}% > 0（排除错误 PID）"

suite "status RSS 合理"
rss=$(echo "$out" | grep -oP 'Java 实际内存: \K[0-9]+')
assert_ok "RSS 非空" test -n "$rss"
# Fabric 服务器 RSS 至少几百 MB
rss_reasonable=$([ "$rss" -gt 100 ] && echo "yes" || echo "no")
assert_eq "$rss_reasonable" "yes" "RSS ${rss}MB > 100MB（排除错误 PID）"

suite "status CPU 格式正确"
cpu=$(echo "$out" | grep -oP 'CPU: \K[0-9.]+')
assert_ok "CPU 非空且为数字" test -n "$cpu"

summary
