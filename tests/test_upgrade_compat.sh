#!/bin/bash
# 集成测试：upgrade.sh 兼容性检查逻辑（mock curl 返回固定 API 响应）
source "$(dirname "$0")/framework.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts"

TMP_DIR=$(mktemp -d); trap "rm -rf '$TMP_DIR'" EXIT

BASE_DIR="$TMP_DIR"; GAME_DIR="$TMP_DIR/GameFile"; BACKUP_DIR="$TMP_DIR/backups"
CONFIG_FILE="$TMP_DIR/config.json"; LOCK_FILE="$TMP_DIR/.mc.lock"
MODS_DIR="$GAME_DIR/mods"
mkdir -p "$MODS_DIR" "$BACKUP_DIR"

cat > "$CONFIG_FILE" << 'EOF'
{"server":{"session_name":"mc_test","fabric_jar":"fabric-server-mc.1.21.4-loader.0.16.14-launcher.1.0.3.jar","java_opts":"","user":"mc","stop_countdown":0,"port":25565},
 "backup":{"keep_days":7,"min_keep":3,"rsync_dest":"","exclude":[]},
 "check":{"disk_warn_mb":5120,"require_easyauth":false},"notify":{"enabled":false}}
EOF

source "$SCRIPT_DIR/common.sh"
load_config

# 创建假 mod 文件
echo "fake-mod-1" > "$MODS_DIR/fabric-api-1.0.jar"
echo "fake-mod-2" > "$MODS_DIR/lithium-1.0.jar"
MOD1_SHA=$(sha1sum "$MODS_DIR/fabric-api-1.0.jar" | cut -d' ' -f1)
MOD2_SHA=$(sha1sum "$MODS_DIR/lithium-1.0.jar" | cut -d' ' -f1)

# mock curl：根据 URL 返回不同的 JSON
MOCK_CURL="$TMP_DIR/curl"
cat > "$MOCK_CURL" << MOCK
#!/bin/bash
url=""
for arg in "\$@"; do
    case "\$arg" in
        http*) url="\$arg" ;;
    esac
done
# Fabric loader 查询
if echo "\$url" | grep -q "meta.fabricmc.net.*versions/loader/1.21.5"; then
    echo '[{"loader":{"version":"0.16.14","stable":true}}]'
# Modrinth version_file（识别 mod）
elif echo "\$url" | grep -q "version_file/$MOD1_SHA"; then
    echo '{"project_id":"P1"}'
elif echo "\$url" | grep -q "version_file/$MOD2_SHA"; then
    echo '{"project_id":"P2"}'
# Modrinth 版本兼容性查询
elif echo "\$url" | grep -q "project/P1/version.*1.21.5"; then
    echo '[{"id":"v1"}]'
elif echo "\$url" | grep -q "project/P2/version.*1.21.5"; then
    echo '[]'
# -w 格式输出 http_code
fi
# 处理 -w 参数（upgrade.sh 用 -w "\n%{http_code}"）
for arg in "\$@"; do
    if [ "\$arg" = '
%{http_code}' ]; then
        echo ""; echo "200"
    fi
done
MOCK
chmod +x "$MOCK_CURL"

suite "Mod 兼容性检查：识别兼容与不兼容"
# 直接测试兼容性检查逻辑片段
MODS_OK=(); MODS_FAIL=(); MODS_UNKNOWN=()
TARGET="1.21.5"
UA="Test/1.0"

for jar in "$MODS_DIR"/*.jar; do
    [ -f "$jar" ] || continue
    name=$(basename "$jar")
    sha1=$(sha1sum "$jar" | cut -d' ' -f1)

    response=$("$MOCK_CURL" -s -w $'\n%{http_code}' \
        "https://api.modrinth.com/v2/version_file/$sha1?algorithm=sha1" \
        -H "User-Agent: $UA")
    body=$(echo "$response" | sed '$d')
    pid=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin).get('project_id',''))" 2>/dev/null || true)
    [ -z "$pid" ] && { MODS_UNKNOWN+=("$name"); continue; }

    has_ver=$("$MOCK_CURL" -s \
        "https://api.modrinth.com/v2/project/$pid/version?game_versions=%5B%22$TARGET%22%5D&loaders=%5B%22fabric%22%5D" \
        -H "User-Agent: $UA")
    has_it=$(echo "$has_ver" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d else 'no')" 2>/dev/null || true)
    [ "$has_it" = "yes" ] && MODS_OK+=("$name") || MODS_FAIL+=("$name")
done

assert_eq "${#MODS_OK[@]}" "1" "1 个 mod 兼容"
assert_contains "${MODS_OK[*]}" "fabric-api" "fabric-api 兼容"
assert_eq "${#MODS_FAIL[@]}" "1" "1 个 mod 不兼容"
assert_contains "${MODS_FAIL[*]}" "lithium" "lithium 不兼容"

suite "Fabric loader 版本解析"
loader_json=$("$MOCK_CURL" -s "https://meta.fabricmc.net/v2/versions/loader/1.21.5")
ver=$(echo "$loader_json" | python3 -c "
import json,sys
d=json.load(sys.stdin)
stable=[v for v in d if v['loader']['stable']]
if stable: print(stable[0]['loader']['version'])
" 2>/dev/null)
assert_eq "$ver" "0.16.14" "解析出 loader 版本"

suite "未识别 mod 归类为 unknown"
echo "unknown-content" > "$MODS_DIR/custom-mod.jar"
UNK_SHA=$(sha1sum "$MODS_DIR/custom-mod.jar" | cut -d' ' -f1)
response=$("$MOCK_CURL" -s "https://api.modrinth.com/v2/version_file/$UNK_SHA?algorithm=sha1")
pid=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('project_id',''))" 2>/dev/null || true)
assert_eq "$pid" "" "未识别 mod 返回空 project_id"

summary
