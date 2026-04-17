#!/bin/bash
# Fabric Server Manager - 清理无用文件
# 删除运行时产生的临时文件，保留所有玩家/地图/背包数据
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
GAME_DIR="$BASE_DIR/GameFile"

if [ ! -d "$GAME_DIR" ]; then
    echo "错误: 找不到 GameFile 目录: $GAME_DIR"
    exit 1
fi

cd "$GAME_DIR"
echo "=== 清理无用文件 ==="
echo "游戏目录: $GAME_DIR"
echo ""

# 崩溃报告（保留最近 5 份）
echo "[1/5] 清理旧崩溃报告..."
ls -t crash-reports/*.txt 2>/dev/null | tail -n +6 | xargs -r rm -f

# 旧日志（保留 latest.log）
echo "[2/5] 清理旧日志..."
find logs/ -name '*.log.gz' -delete 2>/dev/null || true

# 世界临时快照文件（保留 level.dat 和 level.dat_old）
echo "[3/5] 删除世界临时快照文件..."
find world/ -maxdepth 1 -regex '.*/level[0-9].*\.dat' -delete 2>/dev/null || true

# spark 临时文件
echo "[4/5] 清理 spark 临时文件..."
rm -rf config/spark/tmp-client/* config/spark/tmp/* 2>/dev/null || true

# 创建运行时目录
echo "[5/5] 确保必要目录存在..."
mkdir -p crash-reports logs

echo ""
echo "=== 清理完成 ==="
echo "已保留: 玩家数据、地图、背包、成就、统计、mods、配置、最近崩溃报告"
echo "已删除: 旧日志、旧崩溃报告、临时文件"
