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
MODS_JSON="$GAME_DIR/mods.json"
UA="FabricServerManager/1.0"
LAUNCHER_VERSION="1.0.3"

acquire_lock

# ==================== 参数解析 ====================
TARGET_MC_VERSION="${1:-}"
if [ -z "$TARGET_MC_VERSION" ]; then
    echo "用法: upgrade.sh <目标MC版本>"
    echo "示例: upgrade.sh 1.21.6"
    echo ""

    info "正在查找所有 Mod 都兼容的最新 MC 版本..."

    CURRENT_JAR=$(cfg server.fabric_jar)
    CURRENT_MC=$(get_mc_version "$CURRENT_JAR")

    python3 -c "
import json, sys, urllib.request, fnmatch

ua = sys.argv[1]
mods_json = sys.argv[2]
current = sys.argv[3]

with open(mods_json) as f:
    mods = json.load(f)['mods']

modrinth_mods = [m for m in mods if m['source'] == 'modrinth']
github_mods = [m for m in mods if m['source'] == 'github']

def has_loader(ver):
    try:
        req = urllib.request.Request(f'https://meta.fabricmc.net/v2/versions/loader/{ver}', headers={'User-Agent': ua})
        d = json.loads(urllib.request.urlopen(req).read())
        return any(v['loader']['stable'] for v in d)
    except: return False

def check_modrinth(ver, mods):
    ok, fail = [], []
    for m in mods:
        try:
            url = f'https://api.modrinth.com/v2/project/{m[\"project_id\"]}/version?game_versions=%5B%22{ver}%22%5D&loaders=%5B%22fabric%22%5D'
            req = urllib.request.Request(url, headers={'User-Agent': ua})
            d = json.loads(urllib.request.urlopen(req).read())
            if d: ok.append(m['name'])
            else: fail.append(m['name'])
        except:
            fail.append(m['name'])
    return ok, fail

def check_github(ver, mods):
    ok, fail = [], []
    for m in mods:
        try:
            url = f'https://api.github.com/repos/{m[\"repo\"]}/releases'
            req = urllib.request.Request(url, headers={'User-Agent': ua})
            releases = json.loads(urllib.request.urlopen(req).read())
            pattern = m['asset_pattern'].replace('{mc_version}', ver)
            found = False
            for rel in releases:
                for asset in rel.get('assets', []):
                    if fnmatch.fnmatch(asset['name'], pattern):
                        found = True; break
                if found: break
            if found: ok.append(m['name'])
            else: fail.append(m['name'])
        except:
            fail.append(m['name'])
    return ok, fail

# 获取稳定版本
req = urllib.request.Request('https://meta.fabricmc.net/v2/versions/game', headers={'User-Agent': ua})
versions = json.loads(urllib.request.urlopen(req).read())
stable = [v['version'] for v in versions if v['stable']]

total = len(mods)
best_ver, best_ok, best_fail = None, 0, []
print()

for ver in stable[:10]:
    sys.stdout.write(f'  检查 {ver} ...')
    sys.stdout.flush()
    if not has_loader(ver):
        print(' Fabric 不支持')
        continue
    mr_ok, mr_fail = check_modrinth(ver, modrinth_mods)
    gh_ok, gh_fail = check_github(ver, github_mods)
    n_ok = len(mr_ok) + len(gh_ok)
    all_fail = mr_fail + gh_fail
    if n_ok == total:
        print(f' ✓ 全部 {total} 个 Mod 兼容')
    else:
        print(f' {n_ok}/{total} 兼容，不兼容: ' + ', '.join(all_fail))
    if n_ok > best_ok:
        best_ver, best_ok, best_fail = ver, n_ok, all_fail
    if n_ok == total:
        break

print()
if best_ver and best_ok == total:
    if best_ver == current:
        print(f'  当前已是最新全兼容版本: MC {current}')
    else:
        print(f'  ✅ 推荐升级到: MC {best_ver} (所有 {total} 个 Mod 均兼容)')
        print(f'  执行: mc.sh upgrade {best_ver}')
elif best_ver:
    print(f'  最佳版本: MC {best_ver} ({best_ok}/{total} 个 Mod 兼容)')
    print('  不兼容: ' + ', '.join(best_fail))
    if best_ver != current:
        print(f'  如可接受禁用以上 Mod，执行: mc.sh upgrade {best_ver}')
else:
    print(f'  未找到兼容版本')
" "$UA" "$MODS_JSON" "$CURRENT_MC"
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

# 缓存兼容性检查结果，供步骤6使用
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

# 从 mods.json 读取配置进行兼容性检查
if [ -f "$MODS_JSON" ]; then
    # Modrinth mods
    while IFS= read -r line; do
        name=$(echo "$line" | cut -d'|' -f1)
        project_id=$(echo "$line" | cut -d'|' -f2)
        # 缓存: name|source|project_id_or_repo
        echo "modrinth|$name|$project_id" >> "$MOD_CACHE"

        has_version=$(curl -s "https://api.modrinth.com/v2/project/$project_id/version?game_versions=%5B%22$TARGET_MC_VERSION%22%5D&loaders=%5B%22fabric%22%5D" \
            -H "User-Agent: $UA" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d else 'no')" 2>/dev/null || true)
        if [ "$has_version" = "yes" ]; then
            MODS_OK+=("$name")
        else
            MODS_FAIL+=("$name")
        fi
    done < <(python3 -c "
import json, sys
with open(sys.argv[1]) as f: mods = json.load(f)['mods']
for m in mods:
    if m['source'] == 'modrinth':
        print(f'{m[\"name\"]}|{m[\"project_id\"]}')
" "$MODS_JSON")

    # GitHub mods
    while IFS= read -r line; do
        name=$(echo "$line" | cut -d'|' -f1)
        repo=$(echo "$line" | cut -d'|' -f2)
        pattern=$(echo "$line" | cut -d'|' -f3)
        echo "github|$name|$repo|$pattern" >> "$MOD_CACHE"

        # 检查 GitHub releases 中是否有匹配目标版本的 asset
        has_version=$(curl -s "https://api.github.com/repos/$repo/releases" -H "User-Agent: $UA" | python3 -c "
import json, sys, fnmatch
releases = json.load(sys.stdin)
pattern = sys.argv[1].replace('{mc_version}', sys.argv[2])
for rel in releases:
    for asset in rel.get('assets', []):
        if fnmatch.fnmatch(asset['name'], pattern):
            print('yes'); sys.exit()
print('no')
" "$pattern" "$TARGET_MC_VERSION" 2>/dev/null || true)
        if [ "$has_version" = "yes" ]; then
            MODS_OK+=("$name")
        else
            MODS_FAIL+=("$name")
        fi
    done < <(python3 -c "
import json, sys
with open(sys.argv[1]) as f: mods = json.load(f)['mods']
for m in mods:
    if m['source'] == 'github':
        print(f'{m[\"name\"]}|{m[\"repo\"]}|{m[\"asset_pattern\"]}')
" "$MODS_JSON")
else
    warn "未找到 $MODS_JSON，使用 SHA1 识别模式"
    # 回退到旧的 SHA1 识别逻辑
    for jar in "$MODS_DIR"/*.jar; do
        [ -f "$jar" ] || continue
        [ -d "$jar" ] && continue
        name=$(basename "$jar")
        sha1=$(sha1sum "$jar" | cut -d' ' -f1)
        response=$(curl -s -w "\n%{http_code}" "https://api.modrinth.com/v2/version_file/$sha1?algorithm=sha1" -H "User-Agent: $UA")
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | sed '$d')
        if [ "$http_code" != "200" ]; then
            MODS_UNKNOWN+=("$name"); continue
        fi
        project_id=$(echo "$body" | python3 -c "import json,sys; print(json.load(sys.stdin).get('project_id',''))" 2>/dev/null || true)
        if [ -z "$project_id" ]; then
            MODS_UNKNOWN+=("$name"); continue
        fi
        echo "modrinth|$name|$project_id" >> "$MOD_CACHE"
        has_it=$(curl -s "https://api.modrinth.com/v2/project/$project_id/version?game_versions=%5B%22$TARGET_MC_VERSION%22%5D&loaders=%5B%22fabric%22%5D" \
            -H "User-Agent: $UA" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if d else 'no')" 2>/dev/null || true)
        if [ "$has_it" = "yes" ]; then MODS_OK+=("$name"); else MODS_FAIL+=("$name"); fi
    done
fi

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
    sleep 10  # 给玩家时间下线
    info "关闭服务器..."
    cmd_stop || true
    sleep 5  # 等待 stop 命令处理完毕
    # 等待完全停止
    wait_stop 30
fi

# 确保 Java 进程已退出
if pgrep -f "fabric-server-mc" &>/dev/null; then
    warn "旧进程仍在运行，强制终止..."
    pkill -f "fabric-server-mc" || true
    sleep 3  # 等待进程退出并释放端口
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

# 从 MOD_CACHE 读取每个 mod 的信息并更新
# 先建立 project_id -> 当前文件名 的映射（批量 SHA1 查询）
declare -A PID_TO_JAR
for jar in "$MODS_DIR"/*.jar; do
    [ -f "$jar" ] || continue
    sha1=$(sha1sum "$jar" | cut -d' ' -f1)
    pid=$(curl -s "https://api.modrinth.com/v2/version_file/$sha1?algorithm=sha1" -H "User-Agent: $UA" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('project_id',''))" 2>/dev/null || true)
    [ -n "$pid" ] && PID_TO_JAR["$pid"]="$jar"
done

while IFS= read -r cache_line; do
    source_type=$(echo "$cache_line" | cut -d'|' -f1)
    mod_name=$(echo "$cache_line" | cut -d'|' -f2)

    if [ "$source_type" = "modrinth" ]; then
        project_id=$(echo "$cache_line" | cut -d'|' -f3)
        current_jar="${PID_TO_JAR[$project_id]:-}"

        # 获取目标版本的最新 release
        response=$(curl -s -w "\n%{http_code}" "https://api.modrinth.com/v2/project/$project_id/version?game_versions=%5B%22$TARGET_MC_VERSION%22%5D&loaders=%5B%22fabric%22%5D" \
            -H "User-Agent: $UA")
        http_code=$(echo "$response" | tail -1)
        body=$(echo "$response" | sed '$d')

        if [ "$http_code" != "200" ]; then
            warn "API 查询失败 (HTTP $http_code)，保留旧版: $mod_name"
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
    for dep in v.get('dependencies', []):
        if dep.get('dependency_type') == 'required' and dep.get('project_id'):
            print('DEP:' + dep['project_id'])
" 2>/dev/null || true)

        if [ -z "$new_info" ]; then
            if [ -n "$current_jar" ]; then
                warn "不兼容，已禁用: $mod_name"
                mv "$current_jar" "$MODS_DIR.disabled/"
                fail_count=$((fail_count + 1))
            fi
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

        if [ -n "$current_jar" ] && [ "$(basename "$current_jar")" = "$new_filename" ]; then
            info "已是最新: $mod_name"
            continue
        fi

        if curl -fSL -o "$MODS_DIR/$new_filename" "$new_url" -H "User-Agent: $UA" 2>/dev/null; then
            if [ -n "$new_sha1" ] && ! verify_sha "$MODS_DIR/$new_filename" "$new_sha1" sha1; then
                error "SHA1 校验失败: $new_filename，保留旧版"
                rm -f "$MODS_DIR/$new_filename"
                continue
            fi
            [ -n "$current_jar" ] && rm -f "$current_jar"
            info "已更新: $mod_name -> $new_filename"
            update_count=$((update_count + 1))
        else
            warn "下载失败，保留旧版: $mod_name"
        fi

    elif [ "$source_type" = "github" ]; then
        repo=$(echo "$cache_line" | cut -d'|' -f3)
        pattern=$(echo "$cache_line" | cut -d'|' -f4)

        # 从 GitHub releases 查找匹配目标版本的 asset
        download_info=$(curl -s "https://api.github.com/repos/$repo/releases" -H "User-Agent: $UA" | python3 -c "
import json, sys, fnmatch
releases = json.load(sys.stdin)
pattern = sys.argv[1].replace('{mc_version}', sys.argv[2])
for rel in releases:
    for asset in rel.get('assets', []):
        if fnmatch.fnmatch(asset['name'], pattern):
            print(asset['browser_download_url'])
            print(asset['name'])
            sys.exit()
" "$pattern" "$TARGET_MC_VERSION" 2>/dev/null || true)

        if [ -z "$download_info" ]; then
            # 找到当前文件并禁用
            current_pattern=$(echo "$pattern" | sed "s/{mc_version}/*/g")
            for jar in "$MODS_DIR"/$current_pattern; do
                [ -f "$jar" ] || continue
                warn "不兼容，已禁用: $(basename "$jar")"
                mv "$jar" "$MODS_DIR.disabled/"
                fail_count=$((fail_count + 1))
                break
            done
            continue
        fi

        new_url=$(echo "$download_info" | sed -n '1p')
        new_filename=$(echo "$download_info" | sed -n '2p')

        # 检查是否已是最新
        if [ -f "$MODS_DIR/$new_filename" ]; then
            info "已是最新: $mod_name"
            continue
        fi

        # 删除旧版本文件
        current_pattern=$(echo "$pattern" | sed "s/{mc_version}/*/g")
        for old_jar in "$MODS_DIR"/$current_pattern; do
            [ -f "$old_jar" ] && rm -f "$old_jar"
        done

        if curl -fSL -o "$MODS_DIR/$new_filename" "$new_url" -H "User-Agent: $UA" 2>/dev/null; then
            info "已更新: $mod_name -> $new_filename"
            update_count=$((update_count + 1))
        else
            warn "下载失败: $mod_name"
        fi
    fi
done < "$MOD_CACHE"

# 安装缺失的依赖 mod
if [ -n "$dep_ids" ]; then
    # 去重
    dep_ids=$(echo "$dep_ids" | tr ' ' '\n' | sort -u)
    # 获取已安装 mod 的 project_id 列表
    installed_ids=$(grep '^modrinth|' "$MOD_CACHE" 2>/dev/null | cut -d'|' -f3 | sort -u)

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
