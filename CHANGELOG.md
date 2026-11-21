# 更新日志

## v10.1（2026-11-22）

- 新增 `webroot/adapt.sh`：运行时探测 ColorOS 主版本、Settings 键是否存在、PQ 属性是否存在、晕动桥接是否安装
- 新增适配策略 `ADAPT_MODE=auto|compat|full`；`ctl.sh status` 输出 `ROM_MAJOR`、`ADAPT_MODE`、`ADAPT_EFFECTIVE` 与 18 个 `SUP_*`
- `advanced.sh` 改为只写当前系统存在的键：不支持的项记 `N/A`，不创建假 Settings/PQ 键；兼容模式下 6 个实验项强制归零
- WebUI 设备卡后新增“适配策略”卡片，展示当前策略与能力；按 `SUP_*` 动态禁用/隐藏功能，未支持项显示“当前机型未声明支持”
- 能力探测改为单次缓存，避免 `status` 与 `apply` 重复扫 Settings；WebUI 执行超时从 2.4 秒放宽到 5 秒
- `system.prop` 去掉 `ro.sf.blurs_are_expensive=0`、`ro.oplus.panoramic_aod_support=1`、`ro.surface_flinger.media_panel_bg_blur=1` 等硬件能力/性能强声明，交给系统按机型判断
- `customize.sh` 配置模板加入 `ADAPT_MODE=auto`；升级安装自动补键
- 版本提升到 `10.1 / 1001`
- 验证：PC mock 覆盖 ColorOS 17 全量 / ColorOS 16 精简 / ColorOS 17 残缺三套环境；手机已断开，未做 10.1 真机复测

## v10.0（2026-11-22）

- 模块更名为 **ColorOS特性补全**，版本提升到 `10.0 / 1000`
- 晕动桥接重写 SettingsObserver 注册：开机后每 2 秒重试，成功即停；系统里打开/关闭晕动开关不再依赖 30 秒空闲轮询，实测约 1 秒接管、2 秒内停止采样
- 桥接 APK 更换签名并重打包；模块内 `files/AntiDizzyBridge.apk` 同步为新版本
- WebUI 新增“晕动控制”二级页：实际显示开关、桥接状态、强度/纵向增益/触发阈值步进器、柔和/标准/强效预设、恢复默认
- `ctl.sh` 新增 `motionparam`、`motionreset`，`status` 返回三项晕动参数
- 主页晕动项改为二级页入口；删除“已移除：满血快充…”等历史增删文案，删除刷新率只读区
- 重写各功能说明，按“做什么 / 写入什么 / 是否需重启 / 风险”描述；KSU 模块简介同步重写
- README、`module.yaml` 与 Release 工作流同步新名称；Release 资产改为 `ColorOS_Features_v*.zip`
- 升级提示：旧桥接签名不同，若 `pm install -r` 失败需卸载旧桥接后重装，并在 LSPosed 重新勾选“系统框架”

## v9.1.2（2026-11-22）

- WebUI 增加“晕动舒缓显示”实际开关，双写 `motion_sickness_relief_switch` 与 `oplus_customize_antidizzy_enable`
- 模块 `ENABLE_ANTIDIZZY` 只提供功能可用性，首次启用/升级后默认关闭实际显示，不自动拉起
- 关闭实际显示时桥接在 2 秒内注销加速度/陀螺/重力传感器，避免关闭后继续高频采样
- 模块关闭/卸载时把系统晕动开关归零，并清理首次启用标记
- 模块版本提升到 `9.1.2 / 912`

## v9.1.1（2026-11-21）

- 移除 `advanced.sh` 对 `oplus_customize_screen_resolution_adjust` 的固定写入与备份
- WebUI 删除“分辨率固定 QHD+ 档位”的只读项，分辨率完全交回系统/物理面板
- 模块版本提升到 `9.1.1 / 911`

## v6.0.2（2026-11-20）

- 晕动桥接：功能关闭时不再每 2 秒轮询、不再每 5 秒写 LSPosed 状态日志；改用 ContentObserver 即时响应设置变更，空闲轮询降到 30 秒
- 晕动桥接：状态日志仅在功能开启时输出，空闲报告线程降到 60 秒；修复关闭状态下 LSPosed 日志持续增长
- `peak.sh`：满电 `released` 与功能关闭状态由 3 秒轮询改为 30 秒，降低接电源但无需守护时的唤醒
- 模块版本提升到 `6.0.2 / 602`

## v6.0.1（2026-11-20）

- 仓库开启 Release immutability 后重新发布，满足 KernelSU 收录的不可变 Release 要求
- 模块功能与 v6.0 相同；`versionCode` 提升到 `601`
- Release 资产仍为单个 `ColorOS_fullpower_v6.0.1.zip`

## v6.0（2026-11-20）

- 快充参数全自适应：开机探测实际 fastchg 根、`PROJECT`、协议段、峰值电流、表最高温，不再写死 `25061 / 8000mA / 53℃ / PMG110`
- 温度墙由本机表推导：`WALL_MAX = min(580, MAX_TABLE_TEMP + 110)`，自动墙按峰值电流最后温度 + 5..21℃
- 低电流梯度上限按本机表推导（`MAX_TABLE_TEMP + 160`，25061 保持原有 580 表现）
- `ORIG` 原始表缓存增加路径、md5、目录签名、ROM 版本校验，修复跨根与热更新污染
- SELinux 上下文改为显式 `ls -Z + chcon`，修复 toybox 不支持 `--reference` 导致的静默失败
- 每个 bind mount 目标使用独立 payload，修复多个空文件共用 inode 后上下文被最后一次 `chcon` 覆盖
- 系统温控恢复原始 `horae` 属性与状态；修复旧 `0/stopped` 快照导致关闭后 horae 仍然 stopped
- `post-fs-data.sh` 与 `service.sh` 在 `ENABLE_SYSTHERMAL=0` 时都执行一次恢复，覆盖 state 为空的开机路径
- peak 守护改用 `setsid`，PID 判断改为 `/proc/<pid>/cmdline`，避免 `service.sh` 退出时被 Terminated 和 PID 复用误判
- APK 按 sha256 比较后升级，而不是只在缺失时安装
- WebUI 温度墙滑块上限动态读取 `wall_max`，修复 `twMax=440` 时除零
- fastchg 候选根扩展：`/vendor/etc`、`/my_product`、`/product`、`/system_ext`

## v5.0

- 单文件 WebUI，三页合一
- 合并满血核心静态温控等价物
- UI 按 Miuix 规范重写
- 卸载清理 APK、Settings、特性声明层、临时文件

## v4.1

- 增加系统级温控（`tempctl.sh`）
- WebUI 增加温度墙/系统温控卡片

## v4.0

- 合并满血快充 v1.3.0
- Miuix/HyperOS 风格令牌层
- 初步温度墙控制
