#!/bin/bash
# Fabric Server Manager - 安装系统依赖
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/common.sh"
load_config

MIN_JAVA_VERSION=$(required_java_version)

install_pkg() {
    if command -v apt &>/dev/null; then
        sudo apt install -y "$1"
    elif command -v yum &>/dev/null; then
        sudo yum install -y "$1"
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm "$1"
    else
        error "无法自动安装 $1，请手动安装"; return 1
    fi
}

echo "=== 安装系统依赖 ==="

# Java
if command -v java &>/dev/null; then
    java_ver=$(java -version 2>&1 | head -1 | grep -oP '"\K[^"]+' | head -1 | cut -d. -f1)
    if [ "$java_ver" -ge "$MIN_JAVA_VERSION" ] 2>/dev/null; then
        info "Java $java_ver 已安装"
    else
        warn "Java 版本 $java_ver < $MIN_JAVA_VERSION，尝试安装..."
        install_pkg "openjdk-${MIN_JAVA_VERSION}-jre-headless" || install_pkg "java-${MIN_JAVA_VERSION}-openjdk-headless"
    fi
else
    warn "Java 未安装，尝试安装..."
    install_pkg "openjdk-${MIN_JAVA_VERSION}-jre-headless" || install_pkg "java-${MIN_JAVA_VERSION}-openjdk-headless"
fi

# tmux
if command -v tmux &>/dev/null; then
    info "tmux 已安装"
else
    warn "tmux 未安装，安装中..."
    install_pkg tmux
fi

# python3
if command -v python3 &>/dev/null; then
    info "python3 已安装"
else
    warn "python3 未安装，安装中..."
    install_pkg python3
fi

# curl
if command -v curl &>/dev/null; then
    info "curl 已安装"
else
    warn "curl 未安装，安装中..."
    install_pkg curl
fi

# tar（备份核心依赖）
if command -v tar &>/dev/null; then
    info "tar 已安装"
else
    warn "tar 未安装，安装中..."
    install_pkg tar
fi

# ss（端口检查，来自 iproute2）
if command -v ss &>/dev/null; then
    info "ss 已安装"
else
    warn "ss 未安装，安装中..."
    install_pkg iproute2 || install_pkg iproute
fi

# flock（并发锁，来自 util-linux）
if command -v flock &>/dev/null; then
    info "flock 已安装"
else
    warn "flock 未安装，安装中..."
    install_pkg util-linux
fi

# pgrep（进程检测，来自 procps）
if command -v pgrep &>/dev/null; then
    info "pgrep 已安装"
else
    warn "pgrep 未安装，安装中..."
    install_pkg procps || install_pkg procps-ng
fi

echo ""
info "所有依赖安装完成"
