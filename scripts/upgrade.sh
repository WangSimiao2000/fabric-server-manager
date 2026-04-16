#!/bin/bash
# ============================================================
# MC_Server 版本升级脚本
# 升级 Minecraft 版本、Fabric Loader 和所有 Modrinth Mods
# 地图数据完整保留，升级前自动全量备份
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
GAME_DIR="$BASE_DIR/GameFile"
MODS_DIR="$GAME_DIR/mods"
CONFIG_FILE="$BASE_DIR/config.json"
MC="$SCRIPT_DIR/mc.sh"
UA="MC_Server_Upgrade/1.0"
LAUNCHER_VERSION="1.0.3"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "\n${CYAN}=== $1 ===${NC}"; }

cfg() {
    python3 -c "
import json
with open('$CONFIG_FILE') as f: c = json.load(f)
keys = '$1'.split('.')
v = c
for k in keys: v = v[k]
print(v)
" 2>/dev/null
}

# ==================== 参数解析 ====================
TARGET_MC_VERSION="${1:-}"
if [ -z "$TARGET_MC_VERSION" ]; then
    echo "用法: upgrade.sh <目标MC版本>"
    echo "示例: upgrade.sh 1.21.6"
    echo ""
    echo "可用的最新 Minecraft 版本:"
    curl -s "https://meta.fabricmc.net/v2/versions/game" -H "User-Agent: $UA" \
        | python3 -c "
import json,sys
versions = json.load(sys.stdin)
stable = [v['version'] for v in versions if v['stable']][:10]
for v in stable: print(f'  {v}')
" 2>/dev/null
    exit 1
fi

CURRENT_JAR=$(cfg server.fabric_jar)
CURRENT_MC=$(echo "$CURRENT_JAR" | grep -oP 'mc\.\K[0-9]+\.[0-9]+(\.[0-9]+)?')
info "当前版本: MC $CURRENT_MC"
info "目标版本: MC $TARGET_MC_VERSION"

if [ "$CURRENT_MC" = "$TARGET_MC_VERSION" ]; then
    warn "当前已是 MC $TARGET_MC_VERSION，如需仅更新 Mods 请继续"
    read -rp "是否继续更新 Fabric Loader 和 Mods？(y/n) " answer
    [ "$answer" != "y" ] && exit 0
fi

# ==================== 1. 检查 Fabric 支持 ====================
step "1/7 检查 Fabric 对 MC $TARGET_MC_VERSION 的支持"

LOADER_VERSION=$(curl -s "https://meta.fabricmc.net/v2/versions/loader/$TARGET_MC_VERSION" -H "User-Agent: $UA" \
    | python3 -c "
import json,sys
d = json.load(sys.stdin)
stable = [v for v in d if v['loader']['stable']]
if stable: print(stable[0]['loader']['version'])
" 2>/dev/null)

if [ -z "$LOADER_VERSION" ]; then
    error "Fabric 尚不支持 MC $TARGET_MC_VERSION"
    exit 1
fi
info "Fabric Loader: $LOADER_VERSION"

NEW_JAR="fabric-server-mc.${TARGET_MC_VERSION}-loader.${LOADER_VERSION}-launcher.${LAUNCHER_VERSION}.jar"
info "新服务端 jar: $NEW_JAR"

# ==================== 2. 检查 Mods 兼容性 ====================
step "2/7 检查 Mods 对 MC $TARGET_MC_VERSION 的兼容性"

MODS_OK=()
MODS_FAIL=()
MODS_UNKNOWN=()

# 缓存 mod -> project_id 映射，避免步骤6重复调用API
MOD_CACHE=$(mktemp)
trap "rm -f '$MOD_CACHE'" EXIT

for jar in "$MODS_DIR"/*.jar; do
    [ -f "$jar" ] || continue
    [ -d "$jar" ] && continue
    name=$(basename "$jar")

    sha1=$(sha1sum "$jar" | cut -d' ' -f1)
    response=$(curl -s -w "\n%{http_code}" "https://api.modrinth.com/v2/version_file/$sha1?algorithm=sha1" -H "User-Agent: $UA")
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        MODS_UNKNOWN+=("$name")
        continue
    fi

    project_id=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin).get('project_id',''))" 2>/dev/null)
    if [ -z "$project_id" ]; then
        MODS_UNKNOWN+=("$name")
        continue
    fi

    # 缓存映射
    echo "$name=$project_id" >> "$MOD_CACHE"

    # 检查该 mod 是否有目标版本
    has_version=$(curl -s -w "\n%{http_code}" "https://api.modrinth.com/v2/project/$project_id/version?game_versions=%5B%22$TARGET_MC_VERSION%22%5D&loaders=%5B%22fabric%22%5D" \
        -H "User-Agent: $UA")
    hv_code=$(echo "$has_version" | tail -1)
    hv_body=$(echo "$has_version" | sed '$d')

    if [ "$hv_code" != "200" ]; then
        warn "API 查询失败 (HTTP $hv_code): $name"
        MODS_UNKNOWN+=("$name")
        continue
    fi

    has_it=$(echo "$hv_body" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d else 'no')" 2>/dev/null)
    if [ "$has_it" = "yes" ]; then
        MODS_OK+=("$name")
    else
        MODS_FAIL+=("$name")
    fi
done

echo ""
info "兼容 MC $TARGET_MC_VERSION: ${#MODS_OK[@]} 个 Mod"
if [ ${#MODS_FAIL[@]} -gt 0 ]; then
    warn "不兼容 MC $TARGET_MC_VERSION: ${#MODS_FAIL[@]} 个 Mod"
    for m in "${MODS_FAIL[@]}"; do echo "  ✗ $m"; done
fi
if [ ${#MODS_UNKNOWN[@]} -gt 0 ]; then
    warn "无法识别 (不在 Modrinth): ${#MODS_UNKNOWN[@]} 个 Mod"
    for m in "${MODS_UNKNOWN[@]}"; do echo "  ? $m"; done
fi

if [ ${#MODS_FAIL[@]} -gt 0 ]; then
    echo ""
    warn "以上 Mod 在 Modrinth 上没有 MC $TARGET_MC_VERSION 的版本"
    warn "升级后这些 Mod 将被移到 mods.disabled/ 目录"
    read -rp "是否继续升级？(y/n) " answer
    [ "$answer" != "y" ] && { info "已取消"; exit 0; }
fi

# ==================== 3. 确认升级 ====================
step "3/7 升级确认"
echo ""
echo "  MC 版本:      $CURRENT_MC -> $TARGET_MC_VERSION"
echo "  Fabric Loader: $LOADER_VERSION"
echo "  Mods 可更新:   ${#MODS_OK[@]} 个"
echo "  Mods 不兼容:   ${#MODS_FAIL[@]} 个 (将禁用)"
echo "  Mods 未识别:   ${#MODS_UNKNOWN[@]} 个 (保留不动)"
echo ""
echo "  ✓ 地图数据将完整保留"
echo "  ✓ 升级前会执行全量备份"
echo "  ✓ 服务器将先关闭再升级"
echo ""
read -rp "确认开始升级？(y/n) " answer
[ "$answer" != "y" ] && { info "已取消"; exit 0; }

# ==================== 4. 关闭服务器 + 全量备份 ====================
step "4/7 关闭服务器并执行全量备份"

if "$MC" status 2>/dev/null | grep -q "运行中"; then
    info "通知玩家..."
    "$MC" player cmd "say §c[升级维护] 服务器即将关闭进行版本升级 ($CURRENT_MC -> $TARGET_MC_VERSION)，请及时下线" 2>/dev/null || true
    sleep 10
    info "关闭服务器..."
    "$MC" stop || true
    sleep 5
    # 等待完全停止
    timeout=30
    while "$MC" status 2>/dev/null | grep -q "运行中" && [ $timeout -gt 0 ]; do
        sleep 1; timeout=$((timeout - 1))
    done
fi

info "执行全量备份..."
"$MC" backup create
info "备份完成"

# 创建升级快照（用于快速回退）
SNAPSHOT_DIR="$BASE_DIR/backups/pre-upgrade-${CURRENT_MC}-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$SNAPSHOT_DIR"
info "创建升级快照: $(basename "$SNAPSHOT_DIR")"
cp "$GAME_DIR/$CURRENT_JAR" "$SNAPSHOT_DIR/" 2>/dev/null || true
cp -r "$MODS_DIR" "$SNAPSHOT_DIR/mods"
cp "$CONFIG_FILE" "$SNAPSHOT_DIR/config.json"
echo "$CURRENT_MC" > "$SNAPSHOT_DIR/mc_version.txt"
info "快照已保存，可用 mc.sh rollback 回退"

# ==================== 5. 下载新版 Fabric 服务端 ====================
step "5/7 下载 Fabric 服务端"

DOWNLOAD_URL="https://meta.fabricmc.net/v2/versions/loader/$TARGET_MC_VERSION/$LOADER_VERSION/$LAUNCHER_VERSION/server/jar"
info "下载: $NEW_JAR"

if curl -fSL -o "$GAME_DIR/$NEW_JAR" "$DOWNLOAD_URL" -H "User-Agent: $UA"; then
    info "下载成功: $(du -h "$GAME_DIR/$NEW_JAR" | cut -f1)"
else
    error "下载失败！"
    exit 1
fi

# 删除旧 jar（保留备份中有）
if [ "$CURRENT_JAR" != "$NEW_JAR" ] && [ -f "$GAME_DIR/$CURRENT_JAR" ]; then
    rm -f "$GAME_DIR/$CURRENT_JAR"
    info "已删除旧服务端: $CURRENT_JAR"
fi

# ==================== 6. 更新 Mods ====================
step "6/7 更新 Mods"

# 创建禁用目录
mkdir -p "$MODS_DIR.disabled"

update_count=0
fail_count=0

for jar in "$MODS_DIR"/*.jar; do
    [ -f "$jar" ] || continue
    [ -d "$jar" ] && continue
    name=$(basename "$jar")

    # 从缓存读取 project_id
    project_id=$(grep "^${name}=" "$MOD_CACHE" 2>/dev/null | cut -d= -f2)
    if [ -z "$project_id" ]; then
        warn "跳过 (未识别): $name"
        continue
    fi

    # 获取目标版本的最新 release
    response=$(curl -s -w "\n%{http_code}" "https://api.modrinth.com/v2/project/$project_id/version?game_versions=%5B%22$TARGET_MC_VERSION%22%5D&loaders=%5B%22fabric%22%5D" \
        -H "User-Agent: $UA")
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        warn "API 查询失败 (HTTP $http_code)，保留旧版: $name"
        continue
    fi

    new_info=$(echo "$body" | python3 -c "
import json,sys
d = json.load(sys.stdin)
releases = [v for v in d if v['version_type'] == 'release']
if not releases: releases = d
if releases:
    v = releases[0]
    f = next((f for f in v['files'] if f['primary']), v['files'][0])
    print(f['url'])
    print(f['filename'])
    print(v['version_number'])
" 2>/dev/null)

    if [ -z "$new_info" ]; then
        warn "不兼容，已禁用: $name"
        mv "$jar" "$MODS_DIR.disabled/"
        fail_count=$((fail_count + 1))
        continue
    fi

    new_url=$(echo "$new_info" | sed -n '1p')
    new_filename=$(echo "$new_info" | sed -n '2p')
    new_version=$(echo "$new_info" | sed -n '3p')

    if [ "$name" = "$new_filename" ]; then
        info "已是最新: $name"
        continue
    fi

    if curl -fSL -o "$MODS_DIR/$new_filename" "$new_url" -H "User-Agent: $UA" 2>/dev/null; then
        rm -f "$jar"
        info "已更新: $name -> $new_filename"
        update_count=$((update_count + 1))
    else
        warn "下载失败，保留旧版: $name"
    fi
done

# ==================== 7. 更新配置并启动 ====================
step "7/7 更新配置并启动"

# 更新 config.json
python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f: c = json.load(f)
c['server']['fabric_jar'] = '$NEW_JAR'
with open('$CONFIG_FILE', 'w') as f: json.dump(c, f, indent=4, ensure_ascii=False)
print('config.json 已更新')
"

# 更新 systemd 服务文件
if [ -f /etc/systemd/system/mc-server.service ]; then
    info "更新 systemd 服务..."
    sudo bash "$SCRIPT_DIR/install-service.sh"
fi

# 清理 Fabric 缓存（版本变更后需要重新生成）
if [ -d "$GAME_DIR/.fabric" ]; then
    rm -rf "$GAME_DIR/.fabric"
    info "已清理 Fabric 缓存"
fi

# 启动服务器
info "启动服务器..."
"$MC" start

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}升级完成！${NC}                              ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "  MC 版本:     $TARGET_MC_VERSION"
echo "  Fabric:      $LOADER_VERSION"
echo "  Mods 已更新: $update_count 个"
[ $fail_count -gt 0 ] && echo "  Mods 已禁用: $fail_count 个 (见 mods.disabled/)"
echo ""
echo "建议:"
echo "  1. 进入游戏检查地图和 Mod 是否正常"
echo "  2. 查看日志: $MC logs tail"
[ $fail_count -gt 0 ] && echo "  3. 不兼容的 Mod 在 $MODS_DIR.disabled/ 中，待更新后可手动恢复"
