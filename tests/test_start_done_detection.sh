#!/bin/bash
# 测试 cmd_start 的 Done 检测：只匹配新增日志，不匹配上次残留
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

GAME_DIR="$TMP_DIR/GameFile"; mkdir -p "$GAME_DIR/logs"
LOG="$GAME_DIR/logs/latest.log"

suite "tail -c +offset 只检查新增内容"

# 模拟上次启动残留的日志（含 Done）
cat > "$LOG" << 'EOF'
[12:00:00] [Server thread/INFO]: Starting minecraft server
[12:00:05] [Server thread/INFO]: Done (5.123s)! For help, type "help"
[12:00:10] [Server thread/INFO]: Stopping server
EOF
old_size=$(wc -c < "$LOG")

# 没有新增内容时，不应匹配到 Done
result=$(tail -c +"$((old_size + 1))" "$LOG" 2>/dev/null | grep -c "Done (" || true)
assert_eq "$result" "0" "无新增内容时不匹配旧 Done"

# 追加新日志（不含 Done）
echo '[13:00:00] [Server thread/INFO]: Starting minecraft server' >> "$LOG"
result=$(tail -c +"$((old_size + 1))" "$LOG" 2>/dev/null | grep -c "Done (" || true)
assert_eq "$result" "0" "新增内容不含 Done 时不匹配"

# 追加新的 Done
echo '[13:00:05] [Server thread/INFO]: Done (3.456s)! For help, type "help"' >> "$LOG"
result=$(tail -c +"$((old_size + 1))" "$LOG" 2>/dev/null | grep -c "Done (" || true)
assert_eq "$result" "1" "新增内容含 Done 时匹配成功"

suite "Done 匹配精确性"
echo "Something is Done now" > "$LOG"
old_size=$(wc -c < "$LOG")
echo "Done processing" >> "$LOG"
result=$(tail -c +"$((old_size + 1))" "$LOG" 2>/dev/null | grep -c "Done (" || true)
assert_eq "$result" "0" "不匹配不含括号的 Done"

echo 'Done (1.0s)!' >> "$LOG"
result=$(tail -c +"$((old_size + 1))" "$LOG" 2>/dev/null | grep -c "Done (" || true)
assert_eq "$result" "1" "匹配 Done (Xs) 格式"

suite "空日志文件"
> "$LOG"
old_size=0
result=$(tail -c +"$((old_size + 1))" "$LOG" 2>/dev/null | grep -c "Done (" || true)
assert_eq "$result" "0" "空文件不匹配"

suite "日志文件不存在"
rm -f "$LOG"
old_size=0
result=$(tail -c +"$((old_size + 1))" "$LOG" 2>/dev/null | grep -c "Done (" || true)
assert_eq "$result" "0" "文件不存在不报错"

summary
