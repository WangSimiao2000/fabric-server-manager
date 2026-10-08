#!/bin/bash
# 验证：1) 测试执行 mc-restart.sh 不会写生产维护信号文件
#       2) MC_QQ_SIGNAL 可覆盖目标路径
source "$(dirname "$0")/framework.sh"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

suite "测试期间维护信号不得写入生产路径"
PROD="/home/mickeymiao/Projects/mc-qq-bot/maintenance.signal"
assert_ok "framework.sh 已导出 MC_QQ_SIGNAL" '[ -n "$MC_QQ_SIGNAL" ]'
assert_ok "且不指向生产文件" '[ "$MC_QQ_SIGNAL" != "'"$PROD"'" ]'
assert_contains "$(grep QQ_SIGNAL= "$REPO_DIR/scripts/mc-restart.sh")" 'MC_QQ_SIGNAL:-' \
    "mc-restart.sh 支持 MC_QQ_SIGNAL 覆盖"

suite "覆盖后信号写到指定路径"
TMP=$(mktemp -d); trap "rm -rf '$TMP'" EXIT
export MC_QQ_SIGNAL="$TMP/sig.json"
WARN_MIN=5
# 复现 mc-restart.sh 中的钩子逻辑
QQ_SIGNAL="${MC_QQ_SIGNAL:-$PROD}"
[ -d "$(dirname "$QQ_SIGNAL")" ] && \
  printf '{"until": %s, "warn_minutes": %s}\n' "$(( $(date +%s) + WARN_MIN*60 + 1200 ))" "$WARN_MIN" > "$QQ_SIGNAL"
assert_ok "信号文件写到了临时路径" '[ -f "$TMP/sig.json" ]'
assert_contains "$(cat "$TMP/sig.json")" '"warn_minutes": 5' "内容正确"
assert_fail "生产路径未被创建/改动" '[ "$QQ_SIGNAL" = "'"$PROD"'" ]'

summary
