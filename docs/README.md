# MickeyMiao's Minecraft Server

MC 1.21.11 + Fabric 0.19.2 | 离线模式 | 生存服

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

## 项目结构

```
MC_Server/
├── config.json              # 集中配置文件（所有可调参数）
├── GameFile/                # Minecraft 服务器游戏文件
├── scripts/
│   ├── mc.sh                # 统一管理入口（日常使用这一个即可）
│   ├── common.sh            # 公共函数库（cfg/日志/tmux辅助）
│   ├── lib/
│   │   ├── server.sh        # 启停、状态、控制台、预检查
│   │   ├── backup.sh        # 备份、恢复、清理、回退
│   │   ├── player.sh        # 玩家管理
│   │   └── mods.sh          # Mod管理、日志、监控
│   ├── upgrade.sh           # 版本升级（自动更新 Fabric + Mods + 依赖）
│   ├── deploy.sh            # 一键部署（新服务器上运行一次）
│   ├── install-deps.sh      # 安装系统依赖
│   ├── install-service.sh   # 安装 systemd 服务和 cron 定时任务
│   ├── mc-restart.sh        # 定时重启+冷备份（由 cron 自动调用）
│   ├── cleanup.sh           # 清理无用文件
│   └── setup-easyauth.sh    # 安装 EasyAuth 登录 mod
├── backups/                 # 冷备份 + 升级快照
└── docs/
    ├── README.md            # 本文档
    └── EASYAUTH_GUIDE.md    # EasyAuth 使用指南
```

## mc.sh 命令速查表

### 服务器管理
| 命令 | 说明 |
|------|------|
| `mc.sh start` | 启动服务器（含环境预检查） |
| `mc.sh stop` | 优雅关闭（倒计时通知玩家） |
| `mc.sh restart` | 重启 |
| `mc.sh status` | 查看状态/内存/运行时间 |
| `mc.sh console` | 进入服务器控制台（Ctrl+B D 退出） |
| `mc.sh monitor` | 监控面板 |
| `mc.sh check` | 仅运行环境检查 |

### 版本升级与回退
| 命令 | 说明 |
|------|------|
| `mc.sh upgrade` | 查找所有 Mod 都兼容的最新版本 |
| `mc.sh upgrade <版本>` | 升级到指定版本（如 `mc.sh upgrade 26.1`） |
| `mc.sh rollback` | 回退到升级前的版本 |

升级流程：检查兼容性 → 确认 → 关服 → 全量备份 + 快照 → 下载 Fabric → 更新 Mods + 自动安装依赖 → 更新 MOTD → 启动

### 备份管理
| 命令 | 说明 |
|------|------|
| `mc.sh backup create` | 创建冷备份 |
| `mc.sh backup list` | 列出所有备份 |
| `mc.sh backup clean [天数]` | 清理旧备份 |
| `mc.sh backup restore` | 从冷备份一键恢复 |

备份内容：world（含玩家背包/成就/统计）、mods、config、server.properties、EasyAuth 登录数据库

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

## 配置文件 config.json

所有可调参数集中在项目根目录的 `config.json`：

| 字段 | 说明 |
|------|------|
| `server.user` | 运行服务器的系统用户 |
| `server.session_name` | tmux 会话名 |
| `server.fabric_jar` | Fabric 服务端 jar 文件名（升级时自动更新） |
| `server.java_opts` | JVM 参数（内存分配等） |
| `server.port` | 服务器端口 |
| `server.stop_countdown` | 关服前倒计时秒数 |
| `backup.keep_days` | 冷备份保留天数 |
| `backup.min_keep` | 最少保留备份份数 |
| `backup.rsync_dest` | 远程同步目标（留空不同步） |
| `restart.cron` | 定时重启 cron 表达式（默认每天凌晨 5 点） |
| `restart.warn_minutes` | 重启前游戏内警告时间（分钟） |
| `check.disk_warn_mb` | 磁盘空间告警阈值（MB） |
| `check.require_easyauth` | 预检查是否要求 EasyAuth 已安装 |

修改后无需重启，下次执行 `mc.sh` 时自动生效。
修改 cron 或 systemd 相关配置后需重新运行 `sudo bash scripts/install-service.sh`。

## 备份策略

| 类型 | 触发方式 | 说明 |
|------|----------|------|
| 定时冷备份 | cron 每天凌晨自动执行 | 关服 → 备份 → 重启 |
| 手动冷备份 | `mc.sh backup create` | 运行中也可备份（暂停自动保存） |
| 升级快照 | 升级时自动创建 | 保存 Fabric jar + Mods + config，用于 rollback |

## 常见问题

**Q: 启动失败？**
运行 `mc.sh check` 检查环境，查看 `mc.sh logs tail`

**Q: 升级后启动失败？**
运行 `mc.sh rollback` 回退到升级前的版本

**Q: 玩家忘记密码？**
`mc.sh player cmd "auth update 玩家名 新密码"`

**Q: 修改内存/端口/重启时间？**
编辑 `config.json`，systemd/cron 相关改动需重新运行 `sudo bash scripts/install-service.sh`

**Q: 启用远程备份？**
`config.json` 中设置 `backup.rsync_dest` 为 `user@host:/path/`
