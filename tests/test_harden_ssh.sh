#!/bin/bash
# 测试 scripts/harden-ssh.sh 中不需要 root 即可验证的部分
#
# 真正的加固需要 root 且会改动 sshd 配置，不在测试中执行。这里验证：
#   1. 非 root 运行必须拒绝，且不得产生任何改动
#   2. 关键设计不被误改：drop-in 以 00- 开头（须排在 cloud-init 的 50- 之前）、
#      KbdInteractiveAuthentication 一并关闭、使用 reload 而非 restart
#   3. 公钥计数在 grep 无匹配时得到单个 0（曾因 `|| echo 0` 得到 "0\n0"）
source "$(dirname "$0")/framework.sh"
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/scripts/harden-ssh.sh"

suite "非 root 运行被拒绝"
if [ "$(id -u)" -eq 0 ]; then
    assert_eq "skip" "skip" "当前为 root，跳过此用例"
else
    OUT=$(bash "$SCRIPT" 2>&1); RC=$?
    assert_fail "退出码非 0" "[ $RC -eq 0 ]"
    assert_contains "$OUT" "需要 root 权限" "提示需要 root"
    OUT=$(bash "$SCRIPT" --status 2>&1)
    assert_contains "$OUT" "需要 root 权限" "--status 同样要求 root"
fi

suite "关键设计未被误改"
SRC=$(cat "$SCRIPT")
assert_contains "$SRC" 'DROPIN="$DROPDIR/00-hardening.conf"' "drop-in 以 00- 开头"
assert_contains "$SRC" "KbdInteractiveAuthentication no" "一并关闭键盘交互认证"
assert_contains "$SRC" "PasswordAuthentication no" "关闭密码认证"
assert_contains "$SRC" "systemctl reload" "使用 reload"
assert_fail "不使用 restart（会断开会话）" "grep -qE 'systemctl restart (ssh|sshd)' '$SCRIPT'"
assert_contains "$SRC" "sshd -t" "改动后做语法校验"

suite "公钥计数在无匹配时为单个 0"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
: > "$TMP/empty_keys"
n=$(grep -cE '^[[:space:]]*(ssh-|ecdsa-|sk-)' "$TMP/empty_keys" 2>/dev/null || true); n=${n:-0}
assert_eq "$n" "0" "空文件计数为 0"
assert_ok "可参与整数比较" "[ '$n' -eq 0 ]"
printf 'ssh-ed25519 AAAA test\n# comment\nssh-rsa BBBB test2\n' > "$TMP/keys"
n=$(grep -cE '^[[:space:]]*(ssh-|ecdsa-|sk-)' "$TMP/keys" 2>/dev/null || true); n=${n:-0}
assert_eq "$n" "2" "注释行不计入"

summary
