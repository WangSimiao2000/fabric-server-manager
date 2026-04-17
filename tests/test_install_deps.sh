#!/bin/bash
# 测试 install-deps.sh 覆盖了所有项目依赖
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

# 从脚本中实际使用的外部命令（非 coreutils）
REQUIRED_CMDS=(java tmux python3 curl tar ss flock pgrep)

suite "install-deps.sh 覆盖所有必需依赖"
for cmd in "${REQUIRED_CMDS[@]}"; do
    assert_ok "检查了 $cmd" grep -q "command -v $cmd" "$SCRIPT_DIR/install-deps.sh"
done

suite "install-deps.sh 对缺失依赖有安装逻辑"
for cmd in "${REQUIRED_CMDS[@]}"; do
    assert_ok "$cmd 缺失时调用 install_pkg" grep -A3 "command -v $cmd" "$SCRIPT_DIR/install-deps.sh" \| grep -q "install_pkg"
done

suite "脚本中使用的外部命令都在 install-deps.sh 中"
# 扫描所有脚本中的外部命令调用，确认 install-deps.sh 覆盖了
missing=()
for cmd in "${REQUIRED_CMDS[@]}"; do
    # 确认项目中确实用到了这个命令
    if grep -rq "\b${cmd}\b" "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/lib/*.sh 2>/dev/null; then
        if ! grep -q "command -v $cmd" "$SCRIPT_DIR/install-deps.sh"; then
            missing+=("$cmd")
        fi
    fi
done
assert_eq "${#missing[@]}" "0" "无遗漏依赖 (遗漏: ${missing[*]:-无})"

summary
