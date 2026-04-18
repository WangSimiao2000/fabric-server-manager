#!/bin/bash
# ShellCheck 静态分析：检查所有脚本无 error 级别问题
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

suite "ShellCheck 已安装"
if ! command -v shellcheck &>/dev/null; then
    assert_eq "shellcheck" "installed" "shellcheck 未安装，跳过"
    summary; exit
fi

suite "ShellCheck 无 error（核心脚本）"
for f in "$SCRIPT_DIR"/common.sh "$SCRIPT_DIR"/mc.sh "$SCRIPT_DIR"/mc-restart.sh \
         "$SCRIPT_DIR"/watchdog.sh "$SCRIPT_DIR"/lib/server.sh "$SCRIPT_DIR"/lib/backup.sh \
         "$SCRIPT_DIR"/lib/player.sh "$SCRIPT_DIR"/lib/notify.sh "$SCRIPT_DIR"/lib/mods.sh; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    errors=$(shellcheck -x -S error "$f" 2>&1)
    assert_eq "$errors" "" "无 error: $name"
done

suite "ShellCheck 无 error（部署与工具脚本）"
for f in "$SCRIPT_DIR"/deploy.sh "$SCRIPT_DIR"/install-deps.sh \
         "$SCRIPT_DIR"/install-service.sh "$SCRIPT_DIR"/upgrade.sh \
         "$SCRIPT_DIR"/cleanup.sh "$SCRIPT_DIR"/setup-easyauth.sh; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    errors=$(shellcheck -x -S error "$f" 2>&1)
    assert_eq "$errors" "" "无 error: $name"
done

summary
