# EasyAuth 登录认证配置指南

## 为什么需要 EasyAuth？

服务器设置为离线模式 (`online-mode=false`) 后，不再通过 Mojang 验证玩家身份。
这意味着任何人可以用任意用户名连接服务器，冒充其他玩家获取其背包和权限。
EasyAuth 要求玩家注册密码并登录，解决这个安全问题。

## 安装

```bash
./scripts/setup-easyauth.sh
```

## 首次启动配置

1. 启动服务器，EasyAuth 会在 `GameFile/config/` 下生成配置文件
2. 服务器内执行以下管理员命令：

```
# 设置登录等待区（可选，玩家登录前会被传送到此处）
/auth setSpawn

# 如果需要设置全局密码（所有新玩家必须知道才能注册）
/auth setGlobalPassword <密码>
```

## 玩家使用

### 首次进服（注册）
```
/register <密码> <密码>
```

### 后续进服（登录）
```
/login <密码>
# 或简写
/l <密码>
```

### 账户管理
```
/account changePassword <旧密码> <新密码>
/account unregister <密码>
```

> 密码格式：单个词 `mypass123`、下划线连接 `my_pass`、或引号包裹 `"my pass"`

## 管理员命令

```
/auth reload                    # 重载配置
/auth list                      # 列出所有已注册玩家
/auth register <玩家名> <密码>   # 为玩家创建账号
/auth remove <玩家名>            # 删除玩家账号
/auth update <玩家名> <密码>     # 重置玩家密码
/auth getPlayerInfo <玩家名>     # 查看玩家信息
/auth getOnlinePlayers           # 查看在线玩家认证状态
/auth setGlobalPassword <密码>   # 设置全局注册密码
/auth setSpawn [维度 x y z]      # 设置登录等待点
```

## LuckPerms 集成

EasyAuth 自动提供两个 LuckPerms context：

- `easyauth:authenticated` — `true` 表示玩家已登录
- `easyauth:online_account` — `true` 表示玩家使用正版账号

可以在 LuckPerms 中基于这些 context 设置权限，例如只允许已登录玩家使用某些命令。

## 建议配置

EasyAuth 首次启动后会生成配置文件，建议关注以下选项：

- 登录超时时间（超时未登录自动踢出）
- 最大密码尝试次数
- 是否允许正版玩家自动登录（`premiumAutoLogin`）
- 用户名限制（防止特殊字符用户名）

详细配置说明参考：https://github.com/NikitaCartes/EasyAuth/wiki/Config
