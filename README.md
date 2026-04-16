<p align="center">
  <h1 align="center">🧱 Fabric Server Manager</h1>
  <p align="center">
    轻量级 Bash 工具集，用于管理 Fabric Minecraft 服务器
  </p>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License"></a>
  <img src="https://img.shields.io/badge/Platform-Linux-green" alt="Platform">
  <img src="https://img.shields.io/badge/Shell-Bash-yellow" alt="Shell">
  <img src="https://img.shields.io/badge/Minecraft-Fabric-orange" alt="Fabric">
</p>

---

## 这是什么？

一套纯 Bash 编写的 Minecraft Fabric 服务器管理脚本。通过一个统一入口 `mc.sh` 管理服务器的完整生命周期：启停、备份恢复、玩家管理、Mod 管理、版本升级与回退。

**适用场景：** 在 Linux VPS/云服务器上运行 Fabric 模组服务器的个人或小团队。

## ✨ 功能特性

- **一键部署** — 自动安装依赖、配置服务、设置定时任务
- **服务器管理** — 启动/停止/重启/状态监控，基于 tmux 的后台运行
- **自动备份** — 定时冷备份 + 远程同步，可配置保留策略
- **版本升级** — 自动检测 Mod 兼容性，一键升级 MC 版本 + Fabric + 所有 Modrinth Mod
- **一键回退** — 升级前自动创建快照，随时回退到上一个版本
- **Mod 管理** — 列出已安装 Mod、健康检查、重复检测
- **玩家管理** — OP/封禁/白名单/发送命令
- **EasyAuth 集成** — 离线模式下的登录认证支持
- **崩溃监控** — 自动检测服务器崩溃，邮件通知 + 自动重启，反复崩溃时停止重启并告警

## 📋 前置要求

| 依赖 | 版本 | 说明 |
|------|------|------|
| Linux | - | Ubuntu/Debian/CentOS/Arch |
| Java | 21+ | Minecraft 运行时 |
| tmux | - | 后台会话管理 |
| python3 | 3.6+ | 配置解析 |
| curl | - | 下载和 API 调用 |

> 运行 `bash scripts/install-deps.sh` 可自动安装以上依赖。

## 🚀 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/WangSimiao2000/fabric-server-manager.git
cd fabric-server-manager

# 2. 复制并编辑配置文件
cp config.example.json config.json
# 编辑 config.json，修改 user、java_opts、motd 等

# 3. 一键部署（安装依赖 + 配置服务）
bash scripts/deploy.sh

# 4. 启动服务器
./scripts/mc.sh start
```

## 📖 命令速查

```
用法: mc.sh <命令> [参数]
```

### 服务器管理

| 命令 | 说明 |
|------|------|
| `mc.sh start` | 启动服务器（含环境预检查） |
| `mc.sh stop` | 优雅关闭（倒计时通知玩家） |
| `mc.sh restart` | 重启 |
| `mc.sh status` | 查看状态 / CPU / 内存 / 运行时间 |
| `mc.sh console` | 进入服务器控制台（Ctrl+B D 退出） |
| `mc.sh monitor` | 监控面板 |
| `mc.sh check` | 仅运行环境检查 |

### 版本升级与回退

| 命令 | 说明 |
|------|------|
| `mc.sh upgrade` | 查找所有 Mod 都兼容的最新版本 |
| `mc.sh upgrade <版本>` | 升级到指定版本 |
| `mc.sh rollback` | 回退到升级前的版本 |

升级流程：检查兼容性 → 确认 → 关服 → 全量备份 + 快照 → 下载 Fabric → 更新 Mods + 自动安装依赖 → 启动

### 备份管理

| 命令 | 说明 |
|------|------|
| `mc.sh backup create` | 创建冷备份 |
| `mc.sh backup list` | 列出所有备份 |
| `mc.sh backup clean [天数]` | 清理旧备份 |
| `mc.sh backup restore` | 从冷备份一键恢复 |

### 玩家管理

| 命令 | 说明 |
|------|------|
| `mc.sh player list` | 列出所有历史玩家 |
| `mc.sh player op/deop <名字>` | 管理 OP 权限 |
| `mc.sh player ban/unban <名字>` | 封禁/解封 |
| `mc.sh player whitelist on/off` | 开关白名单 |
| `mc.sh player whitelist add/remove <名字>` | 管理白名单 |
| `mc.sh player cmd <命令>` | 发送任意服务器命令 |

### Mod 和日志

| 命令 | 说明 |
|------|------|
| `mc.sh mods list` | 列出已安装 Mod |
| `mc.sh mods check` | Mod 健康检查 |
| `mc.sh logs tail` | 实时查看日志 |
| `mc.sh logs search <关键词>` | 搜索日志 |
| `mc.sh logs crash` | 查看崩溃报告 |

### 通知与监控

| 命令 | 说明 |
|------|------|
| `mc.sh watchdog status` | 查看 watchdog 状态 |
| `mc.sh watchdog test` | 发送测试通知邮件 |
| `mc.sh watchdog reset` | 重置崩溃计数 |

## ⚙️ 配置文件

所有可调参数集中在 `config.json`（从 `config.example.json` 复制）：

```jsonc
{
    "server": {
        "user": "minecraft",          // 运行服务器的系统用户
        "session_name": "mc",         // tmux 会话名
        "fabric_jar": "fabric-server-mc.1.21.11-loader.0.19.2-launcher.1.0.3.jar",
        "java_opts": "-Xms4G -Xmx6G", // JVM 参数
        "port": 25565,
        "stop_countdown": 10,          // 关服前倒计时秒数
        "spawn": { "x": 0, "y": 64, "z": 0 },
        "motd": { ... }
    },
    "backup": {
        "keep_days": 7,               // 备份保留天数
        "min_keep": 3,                // 最少保留份数
        "rsync_dest": ""              // 远程同步目标（留空不同步）
    },
    "restart": {
        "cron": "0 5 * * *",          // 定时重启 cron 表达式
        "warn_minutes": 5
    },
    "check": {
        "disk_warn_mb": 5120,         // 磁盘告警阈值 (MB)
        "require_easyauth": true
    },
    "notify": {
        "enabled": false,             // 是否启用通知
        "method": "email",
        "email": {
            "smtp_host": "smtp.qq.com",
            "smtp_port": 465,         // 465(SSL) 或 587(STARTTLS)
            "from": "发件邮箱",
            "password": "SMTP 授权码",
            "to": "收件邮箱"
        }
    },
    "watchdog": {
        "crash_threshold": 3,         // 窗口内崩溃次数阈值
        "crash_window_minutes": 10    // 崩溃检测时间窗口（分钟）
    }
}
```

修改后无需重启，下次执行 `mc.sh` 时自动生效。  
修改 cron 或 systemd 相关配置后需重新运行 `sudo bash scripts/install-service.sh`。

## 📁 项目结构

```
fabric-server-manager/
├── config.example.json          # 配置模板
├── GameFile/                    # Minecraft 服务器游戏文件
│   └── server.properties.example
├── scripts/
│   ├── mc.sh                    # 统一管理入口
│   ├── common.sh                # 公共函数库
│   ├── lib/
│   │   ├── server.sh            # 启停、状态、预检查
│   │   ├── backup.sh            # 备份、恢复、回退
│   │   ├── player.sh            # 玩家管理
│   │   ├── mods.sh              # Mod 管理、日志、监控
│   │   └── notify.sh            # 邮件通知
│   ├── upgrade.sh               # 版本升级
│   ├── watchdog.sh              # 崩溃监控看门狗
│   ├── deploy.sh                # 一键部署
│   ├── install-deps.sh          # 安装系统依赖
│   ├── install-service.sh       # 安装 systemd + cron
│   ├── mc-restart.sh            # 定时重启脚本
│   ├── cleanup.sh               # 清理临时文件
│   └── setup-easyauth.sh        # 安装 EasyAuth
├── backups/                     # 备份存储
└── docs/
    └── EASYAUTH_GUIDE.md        # EasyAuth 使用指南
```

## 💾 备份策略

| 类型 | 触发方式 | 说明 |
|------|----------|------|
| 定时冷备份 | cron 每天自动执行 | 关服 → 备份 → 重启 |
| 手动冷备份 | `mc.sh backup create` | 运行中也可备份（暂停自动保存） |
| 升级快照 | 升级时自动创建 | 保存 Fabric jar + Mods + config，用于 rollback |

备份内容：world（含玩家背包/成就/统计）、mods、config、server.properties、EasyAuth 数据库

## ❓ 常见问题

**启动失败？**  
运行 `mc.sh check` 检查环境，`mc.sh logs tail` 查看日志。

**升级后启动失败？**  
运行 `mc.sh rollback` 回退到升级前的版本。

**玩家忘记密码？**  
`mc.sh player cmd "auth update 玩家名 新密码"`

**修改内存/端口/重启时间？**  
编辑 `config.json`，systemd/cron 相关改动需重新运行 `sudo bash scripts/install-service.sh`。

**启用远程备份？**  
`config.json` 中设置 `backup.rsync_dest` 为 `user@host:/path/`。

## 📄 License

[MIT License](LICENSE) © 2025 WangSimiao2000
