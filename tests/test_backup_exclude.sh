#!/bin/bash
# 测试 backup.sh: .get 处理缺失 exclude 字段
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

suite "有 exclude 字段时正常输出"
CONFIG_FILE="$TMP_DIR/config_with.json"
cat > "$CONFIG_FILE" << 'EOF'
{"backup": {"exclude": [".git", "logs", "*.tmp"]}}
EOF
out=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f: c = json.load(f)
for e in c.get('backup', {}).get('exclude', []):
    print(f'--exclude={e}')
" "$CONFIG_FILE" 2>&1)
assert_contains "$out" "exclude=.git" "输出 .git"
assert_contains "$out" "exclude=logs" "输出 logs"
assert_contains "$out" "exclude=*.tmp" "输出 *.tmp"
lines=$(echo "$out" | wc -l)
assert_eq "$lines" "3" "3 个 exclude 项"

suite "无 exclude 字段时不报错"
CONFIG_FILE="$TMP_DIR/config_without.json"
echo '{"backup": {"keep_days": 7}}' > "$CONFIG_FILE"
out=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f: c = json.load(f)
for e in c.get('backup', {}).get('exclude', []):
    print(f'--exclude={e}')
" "$CONFIG_FILE" 2>&1)
ret=$?
assert_eq "$ret" "0" "exit 0"
assert_eq "$out" "" "无输出"

suite "无 backup 字段时不报错"
CONFIG_FILE="$TMP_DIR/config_nobackup.json"
echo '{"server": {"user": "mc"}}' > "$CONFIG_FILE"
out=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f: c = json.load(f)
for e in c.get('backup', {}).get('exclude', []):
    print(f'--exclude={e}')
" "$CONFIG_FILE" 2>&1)
ret=$?
assert_eq "$ret" "0" "exit 0"
assert_eq "$out" "" "无输出"

suite "backup.sh 源码使用 .get"
grep -q "\.get('backup'" "$SCRIPT_DIR/lib/backup.sh"
assert_eq "$?" "0" "backup.sh 使用 .get('backup')"
grep -q "\.get('exclude'" "$SCRIPT_DIR/lib/backup.sh"
assert_eq "$?" "0" "backup.sh 使用 .get('exclude')"

summary
