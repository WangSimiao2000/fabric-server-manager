#!/bin/bash
# ============================================================
# Fabric Server Manager - 版本升级脚本
# 升级 Minecraft 版本、Fabric Loader 和所有 Modrinth Mods
# 地图数据完整保留，升级前自动全量备份
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
source "$SCRIPT_DIR/lib/server.sh"
source "$SCRIPT_DIR/lib/backup.sh"
source "$SCRIPT_DIR/lib/notify.sh"
load_config
MODS_DIR="$GAME_DIR/mods"
UA="FabricServerManager/1.0"
LAUNCHER_VERSION="1.0.3"

acquire_lock

step()  { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# ==================== 参数解析 ====================
TARGET_MC_VERSION="${1:-}"
if [ -z "$TARGET_MC_VERSION" ]; then
    echo "用法: upgrade.sh <目标MC版本>"
    echo "示例: upgrade.sh 1.21.6"
    echo ""

    info "正在查找所有 Mod 都兼容的最新 MC 版本..."

    # 收集所有 mod 的 project_id
    mod_ids=()
    unknown_mods=()
    for jar in "$MODS_DIR"/*.jar; do
        [ -f "$jar" ] || continue
        [ -d "$jar" ] && continue
        sha1=$(sha1sum "$jar" | cut -d' ' -f1)
        pid=$(curl -s "https://api.modrinth.com/v2/version_file/$sha1?algorithm=sha1" -H "User-Agent: $UA" \
            | python3 -c "import json,sys; print(json.load(sys.stdin).get('project_id',''))" 2>/dev/null || true)
        if [ -n "$pid" ]; then
            mod_ids+=("$pid")
        else
            unknown_mods+=("$(basename "$jar")")
        fi
    done

    # 获取最新稳定版本列表，逐个检查
    CURRENT_JAR=$(cfg server.fabric_jar)
    CURRENT_MC=$(get_mc_version "$CURRENT_JAR")

    # 收集 mod 名称和 project_id 的映射
    mod_names=()
    for jar in "$MODS_DIR"/*.jar; do
        [ -f "$jar" ] || continue
        [ -d "$jar" ] && continue
        mod_names+=("$(basename "$jar")")
    done

    python3 -c "
import json, sys, urllib.request

ua = sys.argv[1]
mod_ids_raw = sys.argv[2].strip()
mod_names_raw = sys.argv[3].strip()
current = sys.argv[4]
unknown_raw = sys.argv[5].strip()

mod_ids = mod_ids_raw.split('\n') if mod_ids_raw else []
mod_names = mod_names_raw.split('\n') if mod_names_raw else []
unknown = [u for u in (unknown_raw.split('\n') if unknown_raw else []) if u]

# 建立 project_id -> mod名称 的映射（通过索引对应）
# mod_ids 只包含识别到的 mod，需要重建映射
id_to_name = {}
idx = 0
for name in mod_names:
    # unknown mods 没有 id，跳过
    if name in unknown:
        continue
    if idx < len(mod_ids):
        id_to_name[mod_ids[idx]] = name
        idx += 1

# 获取稳定版本
req = urllib.request.Request('https://meta.fabricmc.net/v2/versions/game', headers={'User-Agent': ua})
versions = json.loads(urllib.request.urlopen(req).read())
stable = [v['version'] for v in versions if v['stable']]

def has_loader(ver):
    try:
        req = urllib.request.Request(f'https://meta.fabricmc.net/v2/versions/loader/{ver}', headers={'User-Agent': ua})
        d = json.loads(urllib.request.urlopen(req).read())
        return any(v['loader']['stable'] for v in d)
    except: return False

def check_mods(ver, ids):
    ok, fail = [], []
    for pid in ids:
        try:
            url = f'https://api.modrinth.com/v2/project/{pid}/version?game_versions=%5B%22{ver}%22%5D&loaders=%5B%22fabric%22%5D'
            req = urllib.request.Request(url, headers={'User-Agent': ua})
            d = json.loads(urllib.request.urlopen(req).read())
            if d: ok.append(pid)
            else: fail.append(pid)
        except:
            fail.append(pid)
    return ok, fail

print()
total = len(mod_ids)
best_ver, best_ok, best_fail = None, 0, []

for ver in stable[:10]:
    sys.stdout.write(f'  检查 {ver} ...')
    sys.stdout.flush()
    if not has_loader(ver):
        print(' Fabric 不支持')
        continue
    ok, fail = check_mods(ver, mod_ids)
    n_ok = len(ok)
    if n_ok == total:
        print(f' ✓ 全部 {total} 个 Mod 兼容')
    else:
        fail_names = [id_to_name.get(p, p) for p in fail]
        print(f' {n_ok}/{total} 兼容，不兼容: ' + ', '.join(fail_names))
    if n_ok > best_ok:
        best_ver, best_ok, best_fail = ver, n_ok, fail

print()
if unknown:
    print(f'  ⚠ {len(unknown)} 个 Mod 不在 Modrinth，无法自动检查:')
    for u in unknown: print(f'    ? {u}')
    print()

if best_ver and best_ok == total:
    if best_ver == current:
        print(f'  当前已是最新全兼容版本: MC {current}')
    else:
        print(f'  ✅ 推荐升级到: MC {best_ver} (所有 {total} 个 Mod 均兼容)')
        print(f'  执行: mc.sh upgrade {best_ver}')
elif best_ver:
    fail_names = [id_to_name.get(p, p) for p in best_fail]
    print(f'  最佳版本: MC {best_ver} ({best_ok}/{total} 个 Mod 兼容)')
    print('  不兼容: ' + ', '.join(fail_names))
    if best_ver != current:
        print(f'  如可接受禁用以上 Mod，执行: mc.sh upgrade {best_ver}')
else:
    print(f'  未找到兼容版本')
" "$UA" "$(printf '%s\n' "${mod_ids[@]+"${mod_ids[@]}"}")" "$(printf '%s\n' "${mod_names[@]+"${mod_names[@]}"}")" "$CURRENT_MC" "$(printf '%s\n' "${unknown_mods[@]+"${unknown_mods[@]}"}")"
    exit 0
fi

CURRENT_JAR=$(cfg server.fabric_jar)
CURRENT_MC=$(get_mc_version "$CURRENT_JAR")
info "当前版本: MC $CURRENT_MC"
info "目标版本: MC $TARGET_MC_VERSION"

if [ "$CURRENT_MC" = "$TARGET_MC_VERSION" ]; then
    warn "当前已是 MC $TARGET_MC_VERSION，如需仅更新 Mods 请继续"
    read -rp "是否继续更新 Fabric Loader 和 Mods？(y/n) " answer
    [ "$answer" != "y" ] && exit 0
fi

# ==================== 1. 检查 Fabric 支持 ====================
step "1/7 检查 Fabric 对 MC $TARGET_MC_VERSION 的支持"

loader_json=$(curl -s "https://meta.fabricmc.net/v2/versions/loader/$TARGET_MC_VERSION" -H "User-Agent: $UA" || true)
LOADER_VERSION=$(echo "$loader_json" | python3 -c "
import json,sys
d = json.load(sys.stdin)
stable = [v for v in d if v['loader']['stable']]
if stable: print(stable[0]['loader']['version'])
" 2>/dev/null || true)

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
SNAPSHOT_DIR=""  # 设置后 trap 会自动回滚
_upgrade_cleanup() {
    local exit_code=$?
    set +e  # 回滚过程中不能因命令失败而中断
    rm -f "$MOD_CACHE"
    if [ $exit_code -ne 0 ] && [ -n "$SNAPSHOT_DIR" ] && [ -d "$SNAPSHOT_DIR" ]; then
        echo ""
        error "升级失败 (exit $exit_code)，正在从快照自动回滚..."
        # 还原 Fabric jar
        local old_jar
        old_jar=$(ls "$SNAPSHOT_DIR"/fabric-server-mc.*.jar 2>/dev/null | head -1)
        [ -n "$old_jar" ] && { rm -f "$GAME_DIR"/fabric-server-mc.*.jar; cp "$old_jar" "$GAME_DIR/"; }
        # 还原 mods
        rm -rf "$GAME_DIR/mods"
        cp -r "$SNAPSHOT_DIR/mods" "$GAME_DIR/mods"
        # 还原 config
        cp "$SNAPSHOT_DIR/config.json" "$CONFIG_FILE"
        rm -rf "$GAME_DIR/.fabric"
        info "已自动回滚到 MC $(cat "$SNAPSHOT_DIR/mc_version.txt" 2>/dev/null)"
    fi
}
trap '_upgrade_cleanup' EXIT

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

    project_id=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin).get('project_id',''))" 2>/dev/null || true)
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

    has_it=$(echo "$hv_body" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d else 'no')" 2>/dev/null || true)
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
    for m in "${MODS_FAIL[@]+"${MODS_FAIL[@]}"}"; do echo "  ✗ $m"; done
fi
if [ ${#MODS_UNKNOWN[@]} -gt 0 ]; then
    warn "无法识别 (不在 Modrinth): ${#MODS_UNKNOWN[@]} 个 Mod"
    for m in "${MODS_UNKNOWN[@]+"${MODS_UNKNOWN[@]}"}"; do echo "  ? $m"; done
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

if is_running; then
    info "通知玩家..."
    send_cmd "say §c[升级维护] 服务器即将关闭进行版本升级 ($CURRENT_MC -> $TARGET_MC_VERSION)，请及时下线" 2>/dev/null || true
    sleep 10
    info "关闭服务器..."
    cmd_stop || true
    sleep 5
    # 等待完全停止
    wait_stop 30
fi

# 确保 Java 进程已退出
if pgrep -f "fabric-server-mc" &>/dev/null; then
    warn "旧进程仍在运行，强制终止..."
    pkill -f "fabric-server-mc" || true
    sleep 3
fi
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true

info "执行全量备份..."
backup_create
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
    # 验证下载的 jar 是有效的 zip/jar 文件
    if ! python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1])" "$GAME_DIR/$NEW_JAR" 2>/dev/null; then
        error "下载的 jar 文件无效（非合法 zip/jar），可能下载损坏"
        rm -f "$GAME_DIR/$NEW_JAR"
        exit 1
    fi
    info "下载成功: $(du -h "$GAME_DIR/$NEW_JAR" | cut -f1) (完整性校验通过)"
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
dep_ids=""

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
    print(f.get('hashes',{}).get('sha1',''))
    # 输出 required 依赖的 project_id
    for dep in v.get('dependencies', []):
        if dep.get('dependency_type') == 'required' and dep.get('project_id'):
            print('DEP:' + dep['project_id'])
" 2>/dev/null || true)

    if [ -z "$new_info" ]; then
        warn "不兼容，已禁用: $name"
        mv "$jar" "$MODS_DIR.disabled/"
        fail_count=$((fail_count + 1))
        continue
    fi

    new_url=$(echo "$new_info" | grep -v '^DEP:' | sed -n '1p')
    new_filename=$(echo "$new_info" | grep -v '^DEP:' | sed -n '2p')
    new_version=$(echo "$new_info" | grep -v '^DEP:' | sed -n '3p')
    new_sha1=$(echo "$new_info" | grep -v '^DEP:' | sed -n '4p')

    # 收集依赖
    for dep_id in $(echo "$new_info" | grep '^DEP:' | cut -d: -f2); do
        dep_ids="$dep_ids $dep_id"
    done

    if [ "$name" = "$new_filename" ]; then
        info "已是最新: $name"
        continue
    fi

    if curl -fSL -o "$MODS_DIR/$new_filename" "$new_url" -H "User-Agent: $UA" 2>/dev/null; then
        if [ -n "$new_sha1" ] && ! verify_sha "$MODS_DIR/$new_filename" "$new_sha1" sha1; then
            error "SHA1 校验失败: $new_filename，保留旧版"
            rm -f "$MODS_DIR/$new_filename"
            continue
        fi
        rm -f "$jar"
        info "已更新: $name -> $new_filename"
        update_count=$((update_count + 1))
    else
        warn "下载失败，保留旧版: $name"
    fi
done

# 安装缺失的依赖 mod
if [ -n "$dep_ids" ]; then
    # 去重
    dep_ids=$(echo "$dep_ids" | tr ' ' '\n' | sort -u)
    # 获取已安装 mod 的 project_id 列表
    installed_ids=$(cut -d= -f2 "$MOD_CACHE" 2>/dev/null | sort -u)

    for dep_id in $dep_ids; do
        # 跳过已安装的
        if echo "$installed_ids" | grep -q "^${dep_id}$"; then
            continue
        fi

        # 获取依赖 mod 信息
        dep_title=$(curl -s "https://api.modrinth.com/v2/project/$dep_id" -H "User-Agent: $UA" \
            | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('slug', d.get('title','unknown')))" 2>/dev/null || true)

        # 获取对应版本
        dep_ver=$(curl -s "https://api.modrinth.com/v2/project/$dep_id/version?game_versions=%5B%22$TARGET_MC_VERSION%22%5D&loaders=%5B%22fabric%22%5D" \
            -H "User-Agent: $UA" | python3 -c "
import json,sys
d = json.load(sys.stdin)
releases = [v for v in d if v['version_type'] == 'release']
if not releases: releases = d
if releases:
    v = releases[0]
    f = next((f for f in v['files'] if f['primary']), v['files'][0])
    print(f['url'])
    print(f['filename'])
    print(f.get('hashes',{}).get('sha1',''))
" 2>/dev/null || true)

        if [ -z "$dep_ver" ]; then
            warn "依赖 $dep_title ($dep_id) 无法找到兼容版本"
            continue
        fi

        dep_url=$(echo "$dep_ver" | sed -n '1p')
        dep_filename=$(echo "$dep_ver" | sed -n '2p')
        dep_sha1=$(echo "$dep_ver" | sed -n '3p')

        if [ -f "$MODS_DIR/$dep_filename" ]; then
            continue
        fi

        if curl -fSL -o "$MODS_DIR/$dep_filename" "$dep_url" -H "User-Agent: $UA" 2>/dev/null; then
            if [ -n "$dep_sha1" ] && ! verify_sha "$MODS_DIR/$dep_filename" "$dep_sha1" sha1; then
                error "SHA1 校验失败: $dep_filename"
                rm -f "$MODS_DIR/$dep_filename"
                continue
            fi
            info "已安装依赖: $dep_filename"
            update_count=$((update_count + 1))
        else
            warn "依赖下载失败: $dep_filename"
        fi
    done
fi

# ==================== 7. 更新配置并启动 ====================
step "7/7 更新配置并启动"

# 更新 config.json（原子写入）
python3 -c "
import json, sys, os, tempfile
config_file, new_jar = sys.argv[1], sys.argv[2]
with open(config_file, 'r') as f: c = json.load(f)
c['server']['fabric_jar'] = new_jar
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(config_file))
with os.fdopen(fd, 'w') as f: json.dump(c, f, indent=4, ensure_ascii=False)
os.replace(tmp, config_file)
print('config.json 已更新')
" "$CONFIG_FILE" "$NEW_JAR"

# MiniMOTD 版本号将在 mc.sh start 时从 config.json 自动同步

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
cmd_start

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
echo "  2. 查看日志: mc.sh logs tail"
[ $fail_count -gt 0 ] && echo "  3. 不兼容的 Mod 在 $MODS_DIR.disabled/ 中，待更新后可手动恢复"
