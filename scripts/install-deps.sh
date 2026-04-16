#!/bin/bash
# 安装 MC 服务器运行所需的系统依赖
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

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

# Java 21+
if command -v java &>/dev/null; then
    java_ver=$(java -version 2>&1 | head -1 | grep -oP '"\K[^"]+' | cut -d. -f1)
    if [ "$java_ver" -ge 21 ] 2>/dev/null; then
        info "Java $java_ver 已安装"
    else
        warn "Java 版本 $java_ver < 21，尝试安装 Java 21..."
        install_pkg openjdk-21-jre-headless || install_pkg java-21-openjdk-headless
    fi
else
    warn "Java 未安装，尝试安装..."
    install_pkg openjdk-21-jre-headless || install_pkg java-21-openjdk-headless
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

# curl（EasyAuth 下载需要）
if command -v curl &>/dev/null || command -v wget &>/dev/null; then
    info "curl/wget 已安装"
else
    warn "curl 未安装，安装中..."
    install_pkg curl
fi

echo ""
info "所有依赖安装完成"
