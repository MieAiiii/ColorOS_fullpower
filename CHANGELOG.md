# 更新日志

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
