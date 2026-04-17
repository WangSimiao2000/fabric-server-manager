#!/bin/bash
# 测试 install-service.sh 的 cron 标记管理
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

suite "MC_SERVER_MANAGED 标记存在于 cron 命令中"
grep -q 'MC_SERVER_MANAGED' "$SCRIPT_DIR/install-service.sh"
assert_eq "$?" "0" "install-service.sh 包含 MC_SERVER_MANAGED 标记"

suite "cron 清理用标记而非文件名"
# 不应再用 grep -v 'mc-restart.sh' 来清理
if grep -q "grep -v 'mc-restart.sh'" "$SCRIPT_DIR/install-service.sh"; then
    assert_fail "不应用文件名清理 cron" true
else
    assert_ok "不再用文件名清理 cron" true
fi

suite "标记精确匹配模拟"
# 模拟 crontab 内容
fake_crontab="0 3 * * * /some/other/job.sh
0 5 * * * /path/mc-restart.sh >> /log 2>&1 # MC_SERVER_MANAGED
* * * * * /path/watchdog.sh >> /log 2>&1 # MC_SERVER_MANAGED
30 2 * * 0 /backup/weekly.sh"

# grep -v 标记应只删除带标记的行
cleaned=$(echo "$fake_crontab" | grep -v '# MC_SERVER_MANAGED')
lines=$(echo "$cleaned" | wc -l)
assert_eq "$lines" "2" "只保留 2 行非标记任务"
assert_contains "$cleaned" "other/job.sh" "保留 other/job.sh"
assert_contains "$cleaned" "weekly.sh" "保留 weekly.sh"

# 旧方式 grep -v 'mc-restart.sh' 会误删含该字符串的其他任务
fake_with_comment="0 3 * * * /some/job.sh # runs before mc-restart.sh
0 5 * * * /path/mc-restart.sh >> /log 2>&1 # MC_SERVER_MANAGED"
cleaned_old=$(echo "$fake_with_comment" | grep -v 'mc-restart.sh')
cleaned_new=$(echo "$fake_with_comment" | grep -v '# MC_SERVER_MANAGED')
old_lines=$(echo "$cleaned_old" | grep -c '.' || true)
new_lines=$(echo "$cleaned_new" | grep -c '.' || true)
assert_eq "$old_lines" "0" "旧方式误删了含 mc-restart.sh 注释的行"
assert_eq "$new_lines" "1" "新方式正确保留了注释行"

summary
