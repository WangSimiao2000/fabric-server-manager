#!/bin/bash
# 运行所有测试
cd "$(dirname "$0")"

TOTAL_PASS=0; TOTAL_FAIL=0

for test_file in test_*.sh; do
    echo -e "\n\033[1;35m>>> $test_file\033[0m"
    output=$(bash "$test_file" 2>&1) || true
    echo "$output"
    pass=$(echo "$output" | grep -oP '通过: \033\[0;32m\K[0-9]+' || echo 0)
    fail=$(echo "$output" | grep -oP '失败: \033\[0;31m\K[0-9]+' || echo 0)
    TOTAL_PASS=$((TOTAL_PASS + pass))
    TOTAL_FAIL=$((TOTAL_FAIL + fail))
done

echo -e "\n\033[1;35m============================\033[0m"
echo -e "\033[1;35m总计: 通过 $TOTAL_PASS  失败 $TOTAL_FAIL\033[0m"
[ "$TOTAL_FAIL" -eq 0 ] && echo -e "\033[0;32m全部通过 ✓\033[0m" || { echo -e "\033[0;31m存在失败 ✗\033[0m"; exit 1; }
