#!/bin/bash
# MC_Server 清理脚本 - 删除无用的中间文件，保留所有玩家/地图/背包数据
# 在目标设备上运行一次即可

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
GAME_DIR="$BASE_DIR/GameFile"

if [ ! -d "$GAME_DIR" ]; then
    echo "错误: 找不到 GameFile 目录: $GAME_DIR"
    exit 1
fi

cd "$GAME_DIR"
echo "=== MC_Server 清理脚本 ==="
echo "游戏目录: $GAME_DIR"
echo ""

# 转换工具（已完成使命）
echo "[1/9] 删除离线转换工具..."
rm -f "$SCRIPT_DIR/MinecraftOfflineOnlineConverter_3.jar" "$SCRIPT_DIR/MinecraftOfflineOnlineConverter.log"

# 崩溃报告
echo "[2/9] 清空旧崩溃报告..."
rm -rf crash-reports/*

# 旧日志（保留 latest.log）
echo "[3/9] 清理旧日志..."
find logs/ -name '*.log.gz' -delete 2>/dev/null
rm -f logs/BlossomMods.log

# 世界临时快照文件（保留 level.dat 和 level.dat_old）
echo "[4/9] 删除世界临时快照文件 (level[0-9]*.dat)..."
find world/ -maxdepth 1 -regex '.*/level[0-9].*\.dat' -delete 2>/dev/null

# spark 临时文件
echo "[5/9] 清理 spark 临时文件..."
rm -rf config/spark/tmp-client/*

# 旧热备份
echo "[6/9] 清空旧备份..."
rm -rf backup/world/*

# 空目录
echo "[7/9] 删除空目录..."
rm -rf audioplayer_uploads

# 残留配置（对应 mod 已移除）
echo "[8/9] 删除已卸载 mod 的残留配置..."
rm -rf config/voicechat config/audioplayer
rm -f config/DistantHorizons.toml config/spawnanimations.json config/doubledoors.json5 config/nethermap.toml

# 创建运行时目录
echo "[9/9] 确保必要目录存在..."
mkdir -p crash-reports logs backup

echo ""
echo "=== 清理完成 ==="
echo "已保留: 玩家数据、地图、背包、成就、统计、mods、配置"
echo "已删除: 转换工具、旧日志、旧崩溃报告、临时文件、残留配置"
