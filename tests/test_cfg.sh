#!/bin/bash
# 测试 cfg() 配置解析
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"
source "$(dirname "$0")/framework.sh"

# 创建临时配置文件
TMP_DIR=$(mktemp -d)
trap "rm -rf '$TMP_DIR'" EXIT
CONFIG_FILE="$TMP_DIR/config.json"
BASE_DIR="$TMP_DIR"

cat > "$CONFIG_FILE" << 'EOF'
{
    "server": {
        "user": "minecraft",
        "session_name": "mc",
        "fabric_jar": "fabric-server-mc.1.21.4-loader.0.16.14-launcher.1.0.3.jar",
        "java_opts": "-Xms4G -Xmx6G",
        "port": 25565,
        "stop_countdown": 10,
        "spawn": { "x": 100, "y": 64, "z": -200 }
    },
    "backup": {
        "keep_days": 7,
        "min_keep": 3,
        "rsync_dest": "",
        "exclude": [".git", "logs"]
    },
    "check": {
        "require_easyauth": true,
        "disk_warn_mb": 5120
    },
    "notify": {
        "enabled": false
    }
}
EOF

# source common.sh（只需要 cfg 函数）
source "$SCRIPT_DIR/common.sh"

suite "cfg() 基本读取"
assert_eq "$(cfg server.user)" "minecraft" "读取字符串"
assert_eq "$(cfg server.port)" "25565" "读取数字"
assert_eq "$(cfg server.session_name)" "mc" "读取短字符串"

suite "cfg() 嵌套 key"
assert_eq "$(cfg server.spawn.x)" "100" "嵌套对象 - 正数"
assert_eq "$(cfg server.spawn.z)" "-200" "嵌套对象 - 负数"

suite "cfg() 布尔值"
assert_eq "$(cfg check.require_easyauth)" "true" "布尔 true 输出小写"
assert_eq "$(cfg notify.enabled)" "false" "布尔 false 输出小写"

suite "cfg() 含空格的值"
assert_eq "$(cfg server.java_opts)" "-Xms4G -Xmx6G" "含空格的字符串"

suite "cfg() 空字符串"
assert_eq "$(cfg backup.rsync_dest)" "" "空字符串返回空"

suite "cfg() 不存在的 key"
assert_eq "$(cfg nonexistent.key)" "" "不存在的 key 返回空"
assert_eq "$(cfg server.nonexistent)" "" "部分路径不存在返回空"

suite "cfg() 注入防护"
# key 中包含单引号不应导致 Python 错误或执行
assert_eq "$(cfg "server.user'; import os; os.system('echo hacked')")" "" "单引号注入返回空"

summary
