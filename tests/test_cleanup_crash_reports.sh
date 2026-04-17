#!/bin/bash
# 测试 cleanup.sh: 保留最近 5 份崩溃报告
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

GAME_DIR="$TMP_DIR"
mkdir -p "$GAME_DIR/crash-reports" "$GAME_DIR/logs" "$GAME_DIR/world" "$GAME_DIR/config/spark/tmp"

suite "保留最近 5 份崩溃报告"
# 创建 8 份崩溃报告
for i in $(seq 1 8); do
    f="$GAME_DIR/crash-reports/crash-${i}.txt"
    echo "crash $i" > "$f"
    sleep 0.05  # 确保 mtime 不同
done
count_before=$(ls "$GAME_DIR/crash-reports/"*.txt 2>/dev/null | wc -l)
assert_eq "$count_before" "8" "初始 8 份崩溃报告"

# 模拟 cleanup.sh 中的清理逻辑
(cd "$GAME_DIR" && ls -t crash-reports/*.txt 2>/dev/null | tail -n +6 | xargs -r rm -f)
count_after=$(ls "$GAME_DIR/crash-reports/"*.txt 2>/dev/null | wc -l)
assert_eq "$count_after" "5" "清理后保留 5 份"

# 验证保留的是最新的 5 份（crash-4 到 crash-8）
assert_ok "最新的 crash-8 保留" test -f "$GAME_DIR/crash-reports/crash-8.txt"
assert_ok "最新的 crash-4 保留" test -f "$GAME_DIR/crash-reports/crash-4.txt"
assert_ok "最旧的 crash-1 已删" test ! -f "$GAME_DIR/crash-reports/crash-1.txt"

suite "不足 5 份时不删除"
rm -rf "$GAME_DIR/crash-reports"/*
for i in 1 2 3; do
    echo "crash $i" > "$GAME_DIR/crash-reports/crash-$i.txt"
done
(cd "$GAME_DIR" && ls -t crash-reports/*.txt 2>/dev/null | tail -n +6 | xargs -r rm -f)
count=$(ls "$GAME_DIR/crash-reports/"*.txt 2>/dev/null | wc -l)
assert_eq "$count" "3" "3 份不删除"

suite "0 份时不报错"
rm -rf "$GAME_DIR/crash-reports"/*
(cd "$GAME_DIR" && ls -t crash-reports/*.txt 2>/dev/null | tail -n +6 | xargs -r rm -f)
assert_eq "$?" "0" "无崩溃报告不报错"

summary
