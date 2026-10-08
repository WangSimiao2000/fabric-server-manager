#!/bin/bash
# ============================================================
# SSH 加固：关闭密码登录，仅允许公钥认证
#
# 适用场景：服务器的 SSH 暴露在公网（直接暴露或经 frp 等内网穿透映射），
#   长期遭受密码爆破。尤其是经内网穿透时，sshd 看到的来源 IP 往往
#   恒为 127.0.0.1，fail2ban 这类按 IP 封禁的手段会失效（封掉的是
#   localhost 本身），此时只能从认证方式上彻底关闭密码登录。
#
# 做法：在 /etc/ssh/sshd_config.d/ 写入 00-hardening.conf
#   - sshd 对每个关键字取"最先出现"的值，文件名以 00- 开头确保最先读取。
#     Ubuntu 云镜像常带 50-cloud-init.conf 且内含 PasswordAuthentication yes，
#     若命名为 99- 等会被它抢先，修改无效。
#   - 若 00- 仍未生效（例如主配置在 Include 之前就声明了该项），脚本会找出
#     抢先生效的那一行，备份后注释掉。
#   - KbdInteractiveAuthentication 必须一并关闭，否则 PAM 键盘交互仍可走密码。
#
# 安全措施：
#   - 改动前校验所有可登录用户都已配置公钥，否则中止（防止把自己锁在外面）
#   - sshd -t 语法校验不通过则自动撤销
#   - 使用 reload 而非 restart，不断开已建立的会话
#
# 用法：
#   sudo bash scripts/harden-ssh.sh            执行加固
#   sudo bash scripts/harden-ssh.sh --status   只查看现状，不做改动
#   sudo bash scripts/harden-ssh.sh --revert   回滚，重新允许密码登录
#
# 执行后请保持当前会话不要关闭，另开新窗口确认能登录后再退出。
# ============================================================
set -uo pipefail

MAIN=/etc/ssh/sshd_config
DROPDIR=/etc/ssh/sshd_config.d
DROPIN="$DROPDIR/00-hardening.conf"
STAMP=$(date +%Y%m%dT%H%M%S)

die()  { echo "[中止] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }
ok()   { echo "[ OK ] $*"; }
warn() { echo "[警告] $*" >&2; }

[ "$(id -u)" -eq 0 ] || die "需要 root 权限，请用：sudo bash $0"
command -v sshd >/dev/null 2>&1 || die "未找到 sshd"
mkdir -p "$DROPDIR"

reload_sshd() { systemctl reload ssh 2>/dev/null || systemctl reload sshd; }
eff() { sshd -T 2>/dev/null | awk -v k="$1" '$1==k{print $2}'; }

show_effective() {
    sshd -T | grep -iE "^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin|pubkeyauthentication)" \
        | sed 's/^/  /'
}

scan_conflicts() {
    echo "  --- PasswordAuthentication 的所有声明（按 sshd 读取顺序）---"
    grep -inE "^[[:space:]]*(Include|PasswordAuthentication)" "$MAIN" | sed "s|^|    $MAIN:|"
    for f in "$DROPDIR"/*.conf; do
        [ -e "$f" ] || continue
        grep -inE "^[[:space:]]*PasswordAuthentication" "$f" 2>/dev/null | sed "s|^|    $f:|"
    done
    if grep -qiE "^[[:space:]]*Match" "$MAIN" "$DROPDIR"/*.conf 2>/dev/null; then
        warn "检测到 Match 块，其中的设置可能覆盖全局值，请人工确认："
        grep -inE "^[[:space:]]*Match" "$MAIN" "$DROPDIR"/*.conf 2>/dev/null | sed 's/^/    /'
    fi
}

# ---------- 只看现状 ----------
if [ "${1:-}" = "--status" ]; then
    echo "=== 当前生效值 ==="; show_effective
    echo; scan_conflicts
    exit 0
fi

# ---------- 回滚 ----------
if [ "${1:-}" = "--revert" ]; then
    rm -f "$DROPIN"
    for b in "$DROPDIR"/*.hardenbak.* "$MAIN".hardenbak.*; do
        [ -e "$b" ] || continue
        orig="${b%%.hardenbak.*}"
        cp -f "$b" "$orig" && rm -f "$b" && ok "已还原 $orig"
    done
    sshd -t || die "回滚后配置校验失败，请人工检查 /etc/ssh/"
    reload_sshd || die "重载失败"
    ok "已回滚并重载"; show_effective
    exit 0
fi

[ $# -eq 0 ] || die "未知参数: $1（可用：--status / --revert）"

# ---------- 前置安全检查：防止把自己锁在外面 ----------
info "检查所有可登录用户是否已配置公钥…"
MISSING=0
while IFS=: read -r user _ uid _ _ home shell; do
    case "$shell" in */nologin|*/false|"") continue ;; esac
    [ "$uid" -ge 1000 ] || continue
    ak="$home/.ssh/authorized_keys"
    n=0
    if [ -s "$ak" ]; then
        n=$(grep -cE '^[[:space:]]*(ssh-|ecdsa-|sk-)' "$ak" 2>/dev/null || true)
        n=${n:-0}
    fi
    if [ "$n" -gt 0 ]; then ok "$user: $n 把公钥"
    else warn "$user 没有可用公钥（$ak）"; MISSING=1; fi
done < /etc/passwd

if [ "$MISSING" -ne 0 ] && [ "${FORCE:-0}" != "1" ]; then
    die "存在没有公钥的可登录用户，关闭密码登录会使其无法远程登录。
       确认可通过本机控制台登录后，可用 FORCE=1 sudo bash $0 跳过此检查。"
fi

echo; info "改动前的声明情况："; scan_conflicts; echo

# ---------- 写入 drop-in（00- 开头，确保最先被读取） ----------
info "写入 $DROPIN"
cat > "$DROPIN" << 'EOF'
# 由 fabric-server-manager/scripts/harden-ssh.sh 生成：仅允许公钥认证。
# 文件名以 00- 开头：sshd 对每个关键字取"最先出现"的值，须排在
# cloud-init 等生成的 50-*.conf 之前才能生效。
# 回滚：sudo bash scripts/harden-ssh.sh --revert
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
chmod 644 "$DROPIN"

sshd -t || { rm -f "$DROPIN"; die "配置语法错误，已移除 drop-in，未做任何改动"; }
reload_sshd || die "重载失败，请检查：systemctl status ssh"
ok "已写入并重载（reload 不会断开已有连接）"

# ---------- 若仍未生效，注释掉抢先生效的声明 ----------
if [ "$(eff passwordauthentication)" != "no" ]; then
    warn "00- 命名仍未生效，查找抢先声明的文件…"
    FIXED=0
    for f in "$DROPDIR"/*.conf "$MAIN"; do
        [ -e "$f" ] || continue
        [ "$f" = "$DROPIN" ] && continue
        if grep -qiE "^[[:space:]]*PasswordAuthentication[[:space:]]+yes" "$f"; then
            cp -p "$f" "$f.hardenbak.$STAMP"
            sed -i -E "s|^([[:space:]]*PasswordAuthentication[[:space:]]+yes)|# \1  # 由 harden-ssh.sh 注释|I" "$f"
            ok "已注释 $f 中的 PasswordAuthentication yes（备份 $f.hardenbak.$STAMP）"
            FIXED=1
        fi
    done
    [ "$FIXED" -eq 1 ] || die "未找到可注释的声明，请用 --status 查看并人工检查 Match 块"
    sshd -t || die "注释后语法校验失败，请用 --revert 回滚"
    reload_sshd || die "重载失败"
fi

# ---------- 结果确认 ----------
echo; echo "=== 生效后的实际取值 ==="; show_effective

PA=$(eff passwordauthentication)
KB=$(eff kbdinteractiveauthentication)
if [ "$PA" = "no" ] && [ "$KB" = "no" ]; then
    echo
    ok "密码登录已关闭。请保持当前会话不要关闭，"
    echo "       另开一个新窗口确认能正常登录后再退出。"
    echo "       若新窗口登录失败，在当前会话执行：sudo bash $0 --revert"
else
    die "预期 passwordauthentication=no / kbdinteractiveauthentication=no，实际为 '$PA' / '$KB'"
fi
