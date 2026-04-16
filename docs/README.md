# MickeyMiao's Minecraft Server

MC 1.21.5 + Fabric 0.16.14 | 离线模式 | 生存服

## 前置要求

- Linux 系统（Ubuntu/Debian/CentOS）
- Java 21+
- tmux
- python3（解析配置文件）
- 8GB+ 内存（服务器分配 6-8GB）

## 一键部署

```bash
cd MC_Server
bash scripts/deploy.sh
```

## 项目结构与脚本说明

```
MC_Server/
├── config.json              # 集中配置文件（所有可调参数）
├── GameFile/                # Minecraft 服务器游戏文件
├── scripts/
│   ├── mc.sh                # 统一管理入口（日常使用这一个即可）
│   ├── deploy.sh            # 一键部署（新服务器上运行一次）
│   ├── install-deps.sh      # 安装系统依赖（Java/tmux/python3/curl）
│   ├── cleanup.sh           # 清理无用文件（部署时自动调用）
│   ├── setup-easyauth.sh    # 下载安装 EasyAuth 登录 mod（部署时自动调用）
│   ├── install-service.sh   # 安装 systemd 服务和 cron 定时任务（需 sudo）
│   ├── mc-restart.sh        # 定时重启+冷备份（由 cron 自动调用，无需手动运行）
│   └── mc-server.service    # systemd 服务模板（由 install-service.sh 自动生成）
├── backups/                 # 冷备份存放目录
└── docs/
    ├── README.md            # 本文档
    └── EASYAUTH_GUIDE.md    # EasyAuth 登录认证使用指南
```

各脚本详细说明：

| 脚本 | 用途 | 何时运行 |
|------|------|----------|
| `mc.sh` | 服务器管理的统一入口，包含启停、备份、监控、玩家管理、mod管理、日志查看等所有功能。每次执行自动进行环境和配置预检查。 | 日常管理时手动运行 |
| `deploy.sh` | 一键部署脚本。依次调用 install-deps.sh → cleanup.sh → setup-easyauth.sh → 可选安装 systemd 服务。 | 新服务器上运行一次 |
| `install-deps.sh` | 安装系统依赖（Java 21+、tmux、python3、curl），自动检测包管理器（apt/yum/pacman）。 | 部署时由 deploy.sh 自动调用，也可单独运行 |
| `cleanup.sh` | 清理从旧服务器带过来的无用文件（转换工具、旧日志、旧崩溃报告、临时文件、已卸载mod的残留配置），不会动任何玩家/地图/背包数据。 | 部署时由 deploy.sh 自动调用 |
| `setup-easyauth.sh` | 从 Modrinth 下载 EasyAuth 登录认证 mod 到 mods 目录。离线模式必需，防止玩家身份被冒充。 | 部署时由 deploy.sh 自动调用 |
| `install-service.sh` | 读取 config.json，自动创建系统用户、生成 systemd service 文件、注册 cron 定时重启任务、设置文件权限。需要 sudo。 | 部署时运行一次，改配置后重新运行 |
| `mc-restart.sh` | 定时重启脚本。游戏内倒计时警告 → 优雅关服 → 创建冷备份（含空间检查）→ 清理旧备份 → 重新启动。 | 由 cron 每天自动调用，无需手动 |

## 配置文件 config.json

所有可调参数集中在项目根目录的 `config.json`：

```json
{
    "server": {
        "user": "minecraft",
        "session_name": "mc",
        "fabric_jar": "fabric-server-mc.1.21.5-loader.0.16.14-launcher.1.0.3.jar",
        "java_opts": "-Xms6G -Xmx8G",
        "port": 25565,
        "stop_countdown": 10
    },
    "backup": {
        "keep_days": 7,
        "min_keep": 1,
        "rsync_dest": "",
        "exclude": ["./logs", "./crash-reports", "./.fabric/remappedJars"]
    },
    "restart": {
        "cron": "0 5 * * *",
        "warn_minutes": 5
    },
    "check": {
        "disk_warn_mb": 5120,
        "require_easyauth": true
    }
}
```

各字段说明：

| 字段 | 说明 |
|------|------|
| `server.user` | 运行服务器的系统用户 |
| `server.session_name` | tmux 会话名 |
| `server.fabric_jar` | Fabric 服务端 jar 文件名 |
| `server.java_opts` | JVM 参数（内存分配等） |
| `server.port` | 服务器端口 |
| `server.stop_countdown` | 关服前倒计时秒数 |
| `backup.keep_days` | 冷备份保留天数 |
| `backup.min_keep` | 最少保留备份份数（防止全部被清理） |
| `backup.rsync_dest` | 远程同步目标（留空不同步） |
| `backup.exclude` | 备份时排除的目录 |
| `restart.cron` | 定时重启 cron 表达式 |
| `restart.warn_minutes` | 重启前游戏内警告时间（分钟） |
| `check.disk_warn_mb` | 磁盘空间告警阈值（MB） |
| `check.require_easyauth` | 预检查是否要求 EasyAuth 已安装 |

修改后无需重启，下次执行 `mc.sh` 时自动生效。
修改 cron 或 systemd 相关配置后需重新运行 `sudo bash scripts/install-service.sh`。

> **注意：** 所有脚本基于自身路径自动检测项目位置，项目可放在任意目录。
> 但 `install-service.sh` 会将当前路径写入 systemd 和 cron，因此请先将项目放到最终位置再运行它。
> 如果之后移动了项目目录，需重新运行 `sudo bash scripts/install-service.sh`。

## mc.sh 命令速查表

### 服务器管理
| 命令 | 说明 |
|------|------|
| `mc.sh start` | 启动服务器（含环境预检查） |
| `mc.sh stop` | 优雅关闭（10秒倒计时） |
| `mc.sh restart` | 重启 |
| `mc.sh status` | 查看状态/内存/运行时间 |
| `mc.sh console` | 进入服务器控制台（Ctrl+B D 退出） |
| `mc.sh monitor` | 监控面板 |
| `mc.sh check` | 仅运行环境检查 |

### 备份管理
| 命令 | 说明 |
|------|------|
| `mc.sh backup create` | 创建冷备份 |
| `mc.sh backup list` | 列出所有备份 |
| `mc.sh backup clean [天数]` | 清理旧备份 |

### 玩家管理
| 命令 | 说明 |
|------|------|
| `mc.sh player list` | 列出所有历史玩家 |
| `mc.sh player op/deop <名字>` | 管理OP权限 |
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

## 备份策略

| 类型 | 工具 | 频率 | 保留 |
|------|------|------|------|
| 热备份 | textile_backup mod | 每6小时 | 24份/7天 |
| 冷备份 | mc-restart.sh | 每天凌晨（config.json 配置） | config.json 配置 |

## 常见问题

**Q: 启动失败？**
`mc.sh check` 检查环境，查看 `GameFile/logs/latest.log`

**Q: 玩家忘记密码？**
`mc.sh player cmd "auth update 玩家名 新密码"`

**Q: 修改内存/端口/重启时间？**
编辑 `config.json`，systemd/cron 相关改动需重新运行 `install-service.sh`

**Q: 启用远程备份？**
`config.json` 中设置 `backup.rsync_dest` 为 `user@host:/path/`
