#!/bin/bash
# 轻量级 Bash 测试框架
_PASS=0; _FAIL=0; _CURRENT_SUITE=""

suite() { _CURRENT_SUITE="$1"; echo -e "\n\033[0;36m=== $1 ===\033[0m"; }

assert_eq() {
    local actual="$1" expected="$2" msg="${3:-}"
    if [ "$actual" = "$expected" ]; then
        ((_PASS++)); echo -e "  \033[0;32m✓\033[0m $msg"
    else
        ((_FAIL++)); echo -e "  \033[0;31m✗\033[0m $msg\n    expected: '$expected'\n    actual:   '$actual'"
    fi
}

assert_ok() {
    local msg="${1:-}"
    if eval "${@:2}" >/dev/null 2>&1; then
        ((_PASS++)); echo -e "  \033[0;32m✓\033[0m $msg"
    else
        ((_FAIL++)); echo -e "  \033[0;31m✗\033[0m $msg (exit $?)"
    fi
}

assert_fail() {
    local msg="${1:-}"
    if eval "${@:2}" >/dev/null 2>&1; then
        ((_FAIL++)); echo -e "  \033[0;31m✗\033[0m $msg (expected failure, got success)"
    else
        ((_PASS++)); echo -e "  \033[0;32m✓\033[0m $msg"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if echo "$haystack" | grep -qF "$needle"; then
        ((_PASS++)); echo -e "  \033[0;32m✓\033[0m $msg"
    else
        ((_FAIL++)); echo -e "  \033[0;31m✗\033[0m $msg\n    '$needle' not found in output"
    fi
}

summary() {
    echo -e "\n\033[0;36m=== 结果 ===\033[0m"
    echo -e "  通过: \033[0;32m$_PASS\033[0m  失败: \033[0;31m$_FAIL\033[0m"
    [ "$_FAIL" -eq 0 ] && echo -e "  \033[0;32m全部通过 ✓\033[0m" || echo -e "  \033[0;31m存在失败 ✗\033[0m"
    return "$_FAIL"
}
