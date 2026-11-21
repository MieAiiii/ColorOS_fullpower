# ColorOS 满血特性历史技术档案（v6.0）

> **归档说明（2026-11-22）**：本文档记录 v6.0 时期的快充、温控与旧版 WebUI 实现，相关功能已不在当前 **ColorOS特性补全 10.0** 模块内。当前功能、安装与晕动控制请以 [README.md](README.md) 和 [CHANGELOG.md](CHANGELOG.md) 为准；本文仅保留作技术溯源，避免把旧路径当成现行行为。

> 本文档是项目完整交接文档，供后续对话/开发者接手使用。
> 阅读优先级：§1-§3 必读，§4-§9 按需，§10-§13 是"防翻案"实测档案与操作手册。
> 最后更新：2026-11-20（v6.0 自适应版）

---

## 1. 历史项目概览（v6.0）

**ColorOS 满血特性**（KernelSU 模块，id = `coloros_fullpower`）
作者署名：三重 / 酷安@MieAi（已按要求替换原作者信息）

**历史版本 v6.0；当前模块已更名为 ColorOS特性补全 10.0。**

| 子功能 | 实现位置 | 一句话原理 |
|---|---|---|
| 动画与模糊拉满 | `system.prop`（核心层 6 键） | resetprop 语义注入系统属性 |
| 机型能力补齐 | `post-fs-data.sh`（功能层） | 检测后 setprop 补齐相机/清灰/录屏键 |
| 晕动舒缓显示 | 特性声明 bind mount + LSPosed 桥接 APK | 合并自 `oplus-antidizzy-module v7.5`（原样保留） |
| 满血快充（已移除） | fastchg 温控表叠加 + peak 守护 | 合并自 `息屏快充修复 v1.3.0`；开机探测 fastchg 根/项目/协议段，按本机表生成 |
| 系统级温控（已移除） | `bin/tempctl.sh`（自研） | bind mount 清空/改写用户态温控策略文件 |
| 温度墙（已移除） | `bin/tempwall.sh`（自研） | 按本机表峰值电流与最高温度推导，不写死机型 |
| WebUI（已重构） | `webroot/index.html` 单文件 | 三页合一 + 全局命令队列桥接 |

设计原则（贯穿全部实现）：
1. **只写有代码消费者的属性**（每个键都在设备 dex/so 里验证过消费者）
2. **不写无法验证的键**（如 `ro.oplus.radio.hide_nr_switch` 因 0 命中被移除）
3. **不做机型伪装/安全伪装**（与 Tricky Store/PIF 职责冲突且无实益）
4. **高风险功能默认关闭**（`ENABLE_SYSTHERMAL=0`，UI 标"高风险"红徽标）
5. **所有改动随模块卸载完全复原**（bind mount / settings / 属性三层都有恢复路径）

---

## 2. 环境与设备

### 2.1 设备
- OPPO K15 Pro+（型号 PMG110）
- ColorOS 17.0.0（`ro.build.version.oplusrom=V17.0.0`）/ Android 17（SDK 37）
- SoC：MTK MT6991（天玑 9300 级），GPU Mali-G925 Immortalis MC12
- 屏幕 1272×2772 @ 560dpi，面板支持 165Hz（系统峰值被限制在 120，`persist.oplus.display.vrr=1`）
- 32 位运行时：**不存在**（abilist32 空、无 zygote32）；`ro.sys.oplus_support_app32_version=2` 是**出厂值**（MTK app32 兼容方案，勿再判为有害）

### 2.2 操作环境（重要）
- adb：`C:\Program Files\Oppo Connect\daemon\bin\adb.exe`（系统 PATH 无 adb）
- Git Bash 下**必须** `export MSYS_NO_PATHCONV=1`，否则路径会被 MSYS 转义
- 设备会随机掉线：重连套路 `adb kill-server; sleep 2; adb start-server; sleep 2; adb wait-for-device`
- root 模式统一：`"$ADB" shell "su -c '...'"`

### 2.3 root 与已装模块
- KernelSU（管理器 `me.weishu.kernelsu` v3.3.1，内核 32680；su 上下文 `u:r:ksu:s0`）
- 当前模块列表：`YH_YC`、`coloros_fullpower`、`playintegrityfix`、`tricky_store`、`zygisk_lsposed`、`zygisksu`
- LSPosed 可用，晕动桥接 APK 已启用且工作正常（实测读到运行日志）
- **满血核心（Caelifall_SensorDecoy）已卸载**——曾与本项目在 fastchg 表上按开机挂载顺序随机互踩（485 vs 530 温度墙），勿再装回

---

## 3. 模块结构与文件清单

```
/data/adb/modules/coloros_fullpower/     （设备上 279KB）
├── module.prop            id/name/version=6.0/versioncode=600
├── system.prop            核心层 6 键（ksud resetprop 注入）
├── post-fs-data.sh        开机：功能层属性 + 温控挂载 + 快充挂载 + 晕动特性注入
├── service.sh             开机后：peak 守护拉起 + horae 停止兜底 + 桥接 APK 安装
├── customize.sh           安装时：机型检测打印 + config.conf 生成 + chmod
├── uninstall.sh           卸载：全部清理（目标=零残留）
├── cleanup.sh             晕动清理（--force 时 pm uninstall + settings delete + 墓碑自删）
├── config.conf            用户配置（安装时生成，已存在则保留）
├── bin/
│   ├── tempwall.sh        温度墙 get/set/restore
│   ├── tempctl.sh         系统级温控 on/off/status
│   ├── peak.sh            快充峰值守护（daemon/start/stop/set/status/restore）
│   └── cap.sh             电池容量采集（诊断用）
├── payload/               tempctl 运行时生成（empty.bin + high_temp_protect.xml）
├── files/AntiDizzyBridge.apk     晕动桥接 APK（37KB，md5 与原项目一致）
├── odm/firmware/fastchg/  快充温控表（开机探测实际根；default + PROJECT/ 目录）
├── backup/original_backup.txt    安装时 persist 键备份（key<TAB>value）
├── last_boot.log          每次开机覆盖（功能层写入明细）
├── sys_thermal_state.txt  tempctl 幂等凭证（on 时生成、off 时删除）
├── sys_thermal.log        tempctl 操作日志
└── webroot/
    ├── index.html         WebUI 唯一页面（60K，三页合一单文件）
    ├── theme.css          设计令牌层（miuix 规范）
    └── status.sh          快充状态采集（供 WebUI 调用）
```

**本地工程**：`D:\满血color\module_v3\`（与设备同步的源）。
`webroot/antidizzy.html`、`webroot/charge.html` 是合并前的旧独立页，**已废弃不再部署**（勿改它们，改了没用）。

外部痕迹（模块目录之外）：
- `/data/adb/screenoff_fix/`（快充数据：log/backup/config.env）+ `/data/adb/screenoff_fix.log`
- `/data/adb/service.d/motion_cues_cleanup.sh`（晕动卸载墓碑，指向 coloros_fullpower）
- APK `com.workbuddy.antidizzybridge` + settings secure 的 12 个晕动键
- 温度墙备份：出厂 fastchg 表备份在模块内 `backup/`

---

## 4. KernelSU 机制实测（全部验证过，勿凭文档想当然）

### 4.1 属性注入双通道
- `system.prop`：ksud 以 **resetprop 语义**写入 → **可覆盖已存在的 `ro.*`**
- `post-fs-data.sh` 的 `setprop`：只能写 `persist.*` 和**此前不存在的** `ro.*`（已存在且值不同时失败，模块选择不强行覆盖并记 FAIL 行，属正常）
- 实测：`setprop ro.bootloader hacktest` 失败；模块覆盖 `ro.bootloader` 成功 → 证明生效的是 system.prop 通道

### 4.2 vendor 前缀属性陷阱
`ro.vendor.*` 经脚本 `setprop` 写入后**普通进程读不到**（只有 root 能读）。凡 `ro.vendor.*` 键必须走 `system.prop`。当前受影响的键：`ro.vendor.oplus.camera.isSupportLumo`（已放 system.prop）。

### 4.3 安装行为
`ksud module install /path/zip`：解压到 `modules_update/` 执行 customize.sh（此时 `$MODPATH` 指向 modules_update），重启后迁移。**customize.sh 检测 `modules_update` 下无 config.conf 就重新生成**——用户此前未改过 config 时无损；若用户改过 config 再装新版可能被重置为默认，升级前应备份 config.conf。

### 4.4 WebUI 打开方式（验证用）
管理器 → 底部"模块" tab（约 x=818,y=2590）→ ColorOS 卡片"打开"按钮（约 x=318,y=551）。
**坑**：管理器 WebView 会恢复上次页面状态（上次打开的层/滚动位置会在下次进入时复现）；Chrome 测 file:// 会复用旧标签。验证 UI 尽量让用户人工验收，agent 不要用截图导航自证（历史教训：目测坐标双坑导致大量浪费）。

---

## 5. 温控架构（设备实测，本模块温控功能的立论基础）

### 5.1 三层架构
| 层 | 实体 | 实测事实 |
|---|---|---|
| 内核熔断 | MTK thermal zones / cooling devices | **全部 trip=118.8℃**（熔断级）；cooling_device cur_state 恒 0 → 内核被动限频形同虚设，**不需要也不应该动** |
| MTK 策略 | `thermal_core`（/vendor/bin，读 `/vendor/etc/thermal/*.conf`） | conf 是**加密格式**不可编辑；进程保留（充电温度监控依赖），策略清空后无可执行动作 |
| OPlus 用户态策略 | `thermal HAL (mediatek)` 之外的全部策略文件 | **真正的降频/降亮度/降刷新刹车**，全部可 bind mount 覆盖 |

进程事实：本机**没有 thermal-engine**（ColorOS 17 已由 thermal_core 取代）；`dumpsys thermalservice` Thermal Status=1（无降级）。

### 5.2 OPlus 策略文件（tempctl 的 4 个目标）
| 文件 | 原厂形态 | 模块覆盖物 |
|---|---|---|
| `/odm/etc/temperature_profile/sys_thermal_control_config.xml` | **加密 182KB** | 0 字节空文件（密文消费者读不懂→策略失效，与满血核心同法） |
| `/odm/etc/temperature_profile/sys_high_temp_protect_*.xml`（文件名可能带项目号，需 glob 探测） | 明文 XML 2431B（ProtectSwitch true、阈值 510/700/相机 420） | 全 false/0 版 payload（34 字段与原厂逐一对齐） |
| `/odm/etc/horae/horae_target.conf` | 二进制/加密 13KB | 空文件 |
| `/system_ext/etc/horae/horae.conf` | 明文/混合 2.6KB | 空文件 |

horae 原厂基线：**running + persist.sys.horae.enable=1**。tempctl on 会 `setprop enable 0 + ctl.stop horae`；off 恢复 enable=1（不主动 ctl.start，服务由 init 管理）。

### 5.3 tempctl.sh 设计要点
- `on`：无条件叠加 bind mount（目标可能已被其他模块挂载，bind mount 允许叠层，顶层=后挂者）；挂载前 `chmod/chown/chcon --reference` 对齐 SELinux 标签；逐目标写 `sys_thermal_state.txt`
- **幂等凭证 = state 文件**：非空时 on 直接回 `already=N` 不叠层
- `off`：按 state 逐行 umount（只卸自己的顶层），恢复 horae enable=1
- `status`：输出 `systhermal/mine/targets/layers/horae/thermal_core/hal/horae_prop`（供 WebUI 解析）
- **mountinfo 回声现象**：本机 `/odm` 与 `/data/adb` 在同一 f2fs 设备 dm-41 的 shared 传播域，bind mount 会在源文件路径产生回声层——**无害**，但 mountinfo 计数会虚高（layers 可能 > mine）

### 5.4 温度墙 tempwall.sh
- 原理：读取 fastchg 温控表的 `*_THERMAL_CONTROL_START/END` 区段，找到最大电流档的温度起点；温度墙上限由本机表最高温推导（`WALL_MAX=min(580, MAX_TABLE_TEMP+110)`），自动墙再按峰值电流抬升 5-21℃，夹到 44.0-WALL_MAX；低电流梯度上限也按本机表推导（`MAX_TABLE_TEMP+160`，夹到 44.0-58.0℃）。电流与阶梯数完全不变。
- 三个子命令：`get`（输出本机 `wall=...`）、`set <0.1℃>`（平移+挂载+备份原厂表）、`restore`（卸载挂载+恢复原厂表，输出 `restored=1`）
- 表位置：`/odm/firmware/fastchg/charging_thermal_config_default.txt`（由 post-fs-data 用模块内表 bind mount）
- 出厂表备份在模块内 `backup/`

---

## 6. 核心层与功能层

### 6.1 system.prop（6 键，全部有消费者验证）
| 键 | 值 | 语义（已查证） |
|---|---|---|
| `persist.sys.oplus.anim_level` | 1 | **增强动效档**（酷安"动效模糊补齐"配方值；Settings/SystemUI/Launcher/Camera/Gallery/UXDesign 全命中，唯一全局动画总开关） |
| `ro.oplus.animationlevel` | 3 | **完整动效**（3=完整；被砍动效机型常为 1/2） |
| `ro.surface_flinger.supports_background_blur` | 1 | SF 窗口背景模糊能力 |
| `ro.oplus.display.disable.volume_blur` | 0 | **disable 键：0=音量条毛玻璃开启**（社区恢复模糊配方值；UI 值显示需反转） |
| `persist.sys.wallpaperanimation.enable` | true | 壁纸切换动效 |
| `ro.vendor.oplus.camera.isSupportLumo` | 1 | Lumo 影像（**必须走 system.prop**，vendor 前缀陷阱） |
| `persist.oplus.flexible.blur_snapshot_enable` | true | 小窗/分屏模糊快照 |

另有一批"出厂已有且同值"的键（defercap、speaker_clean、dual_nr_toggle、ridermode×2）**刻意不写**——写了是无效操作。`ro.oplus.gaussianlevel` 等 5 个旧模糊键在 17 上 0 命中，只放进 `ENABLE_LEGACY` 分支（ColorOS ≤16 才可能有效）。

### 6.2 post-fs-data.sh 流程
1. 读 config.conf（ENABLE_CAMERA/AUDIO/RECORDER/LEGACY/ANTIDIZZY/SYSTHERMAL）
2. **系统温控分支**：`ENABLE_SYSTHERMAL=1` → tempctl on；否则若 state 文件存在 → tempctl off（开机恢复原厂层）
3. 功能层属性（写入器幂等：值相同跳过）：相机 5 键（CAMERA）、清灰 audio 键（AUDIO）、`ro.media.recorder-max-base-layer-fps=120`（RECORDER，仅检测到 `persist.oplus.display.vrr=1` 高刷才写）、LEGACY 分支旧模糊键
4. 晕动特性注入：向 3 个候选 permissions XML 尾部插入 `<oplus-feature name="oplus.hardware.display.motion_sickness"/>` 并 bind mount（逐个探测谁存在补谁；日志 `/data/local/tmp/motion_cues_port.log`）
5. 快充挂载：chcon vendor_configs_file 后 bind mount 两处 fastchg 表 + manifest 留痕

### 6.3 service.sh 流程
boot_completed 后：peak.sh start（快充守护）→ ENABLE_SYSTHERMAL=1 时再次 stop horae/thermal-engine（兜底覆盖 post-fs-data 之后被拉起的情况）→ 晕动：装墓碑 + APK 缺失时安装（提示 LSPosed 勾选）。

### 6.4 config.conf
`ENABLE_CAMERA=1 / ENABLE_AUDIO=1 / ENABLE_RECORDER=1 / ENABLE_LEGACY=0 / ENABLE_ANTIDIZZY=1 / ENABLE_SYSTHERMAL=0`
WebUI 的开关（data-sw）直接 sed 改这个文件（需重启生效）；系统温控/温度墙/晕动参数例外（即时生效）。

---

## 7. 晕动舒缓显示

- **来源**：`D:\晕动视觉\oplus-antidizzy-module` v7.5，合并时 APK 与页面 md5 一致零改动（仅 cleanup.sh 的 MODDIR 路径适配 + post-fs-data 加开关判断）
- **注入**：见 §6.2 第 4 步；特性声明 `oplus.hardware.display.motion_sickness` 让 SystemUI 启用运动补偿路径
- **桥接**：`AntiDizzyBridge.apk`（包名 `com.workbuddy.antidizzybridge`），LSPosed 模块，作用域=系统框架；运行日志在 `/data/adb/lspd/log/modules_*.log` 的 `AntiDizzyBridge: state: veh=... mode=...` 行
- **settings secure 键**（12 个）：`oplus_customize_antidizzy_enable/mode/force_off`、`motion_cues_gain/gain_y/gate/bridge_test/veh_rms/veh_low/veh_rot/veh_step/veh_hold`
  - 默认值：gain 1.0 / gain_y 2.5 / gate 0.08 / veh 0.12/0.55/0.12/0.45/8 / test 0
  - 用户当前调参：mode=2（常驻显示）、gain=2.0、gain_y=4.0、gate=0.10
- **模式**：1=仅车辆运动（判定 veh）、2=常驻显示（不判定）；test 0/1/2/5（关闭/竖持漂移/正弦摆动/模拟走路）
- 墓碑：`/data/adb/service.d/motion_cues_cleanup.sh`（cleanup.sh 复制件；模块被删时下次开机自动清理 APK/settings/挂载并自删）

---

## 8. 满血快充

- **来源**：息屏快充修复 v1.3.0（用户明确要求参数与功能严禁改动，仅路径适配 zz_screenoff_fix → coloros_fullpower）
- **原理**：厂商充电功率按档位阶梯下降（散热保护），杂散因素会触发额外降档致每档跑不满；本功能通过 bind mount 覆盖 fastchg 温控表压制额外降档，**阶梯节奏不变**
- **挂载**：`charging_thermal_config_default.txt`（默认表）+ `PROJECT/`（项目表目录）→ 实际探测到的 fastchg 根；顺序关键：先 chcon 再 mount
- **peak.sh 守护**：充电时把被压低功率顶回档位满血值；到达 TARGET_SOC 自动收手（released）；未充电 IDLE_SLEEP=30 秒低频轮询；日志 `MAX_LOG=512KB` 自动轮转（changes.log/daemon.log/peak.csv/full.csv）
- **config.env**：`/data/adb/screenoff_fix/config.env`（TARGET_SOC=100，用户配置）
- **status.sh**：输出 m_default/m_dir/f_silicon/label/imax/thr/batt_*/usb_*/screen/hal_err/enabled/target/state/cap_* 等 ~28 键（约 0.5s）
- **已知小瑕疵**：status.sh 没有 `sz_silicon` 键 → WebUI"生效表大小"显示 `--`（v1.3.0 原版行为，非回归）

---

## 9. WebUI 技术内幕

### 9.1 架构
- **单文件** `index.html`（三页合一：主页 / page-dizzy / page-charge / page-log 全屏层），共享 `theme.css` 令牌
- **无 iframe**：KernelSU WebView 只在主 frame 注入桥接，iframe 子页面永远拿不到接口（血泪教训）
- **懒加载**：dizzyInit()/chargeInit() 只在首次 openPage 时执行；轮询（晕动 3s 日志、快充 3s status）只在对应页面 `.open` 时跑
- **关闭页面**时清掉快充轮询

### 9.2 桥接（受控实验验证，勿改动结构）
```js
findBridge()            // 候选名 ksu/kernelsu/KernelSU/ksuApp/ksuBridge/KSU + parent/top window 探测 + window 枚举
sh(cmd)                 // 全局队列 SH_Q 串行包装
shRaw(cmd)              // WORK_FORM 记忆：callName(三参+回调名) → 800ms 失败 → callFn(两参+函数) → 2200ms 兜底 TIMEOUT
```
- 管理器实际签名：`exec(cmd, "{}", cbName)`，回调收**单对象** `{exitCode, stdout, stderr}`（dex 证据：`javascript: (function(){ try { var err = new Error(); err.exitCode = ...`）
- 回调名必须注册在 **BRIDGE_WIN**（桥接所在的 window）
- **管理器执行通道是单通道**：并发命令必丢回调 → 所有命令必须过 SH_Q 队列
- **管理器对命令无时长限制**（`sleep 1; echo` 实测成功）——"耗时丢回调"是错误归因，真因是并发

### 9.3 设计令牌（miuix 官方源码值，compose-miuix-ui/miuix）
- primary `#3482FF`、error `#E94634`、页面底 surface `#F7F7F7`、卡片白、组标题 `#8C93B0`、分割线 `#E0E0E0`、outline `#D9D9D9`
- 字阶：Title1 32 / Title2 24 / Title3 20 / Title4 18 / Main 17 / Headline 16 / Body 14 / Footnote 13 / Footnote2 11
- HyperOS 2.0 设置实拍特征：灰底 + 白底分区 + 0.5px 灰描边 + 36dp 彩色圆角图标块 + **无行分割线**（已删）
- 液态玻璃仅用于 chrome 层（appbar/pagebar：半透+blur(28px) saturate(180%)+顶边高光）；卡片实色
- 图标块色系：t-blue/t-green/t-orange/t-red/t-purple/t-teal/t-gray（渐变）

### 9.4 滑块规范（miuix Slider，用户验收版）
- **等宽 28px 圆角灰轨**（rgba(0,0,0,.08)）+ 蓝色 28px 粗条 + 白色 28px thumb，蓝条圆心与 thumb 同心包裹
- `THUMB_R=14`（主页温度墙用 `TW_R=14`）；`fill.width = x + THUMB_R`
- `.slider{touch-action:none}` 防滚动抢手势
- **pointercancel 只清状态不跳位**（否则页面滚动抢手势时 clientX=0 → 跳最小值）
- 范围映射：像素 f = (clientX-left-R)/(width-2R)

### 9.5 已踩坑清单（勿重蹈）
1. iframe 方案死路（桥接拿不到）→ 单文件
2. 合并产物 index.html 是唯一真源，改子页文件无效 → **只改 index.html**
3. python 切片补丁曾把 index.html 破坏（execCmd×16）→ 补丁必须 assert 唯一锚点，或整文件重写
4. 页面初始化多路并发丢回调 → SH_Q 队列 + 懒加载
5. 截图导航是 token 黑洞（WebView 状态恢复重开上次页面 + 目测坐标不准）→ 视觉验收交给用户，agent 只做 shell 层受控实验
6. `grep $'\r'` 在 Git Bash 里展开异常，换行检查用 python 按字节
7. Windows python 文本模式写 sh 会 CRLF → 一律 `newline='\n'` 或二进制写；打包后校验 zip 内脚本无 CRLF
8. Chrome `am start -d file://` 复用旧标签 → 页面验证不可信（已放弃该路径）

---

## 10. 实测结论档案（防翻案）

| 结论 | 证据 |
|---|---|
| 应用 UI 已运行 Vulkan HWUI | `ro.hwui.use_vulkan=true`（vendor build.prop 246 行）；清空 `debug.hwui.renderer` 后 gfxinfo 仍 `Pipeline=Skia (Vulkan)` |
| SF 合成层锁死 GLES | `/vendor/build.prop` 88 行 `debug.renderengine.backend=skiagl`；合法值仅 gles/skiavk；skiavk+重启 SF 仍 `RE GLES (Ganesh)`；user 构建忽略 |
| 音量条模糊键 | `disable.volume_blur`，**0=开启**（酷安动效补齐配方 `=0` 用于恢复模糊）；UI 显示已反转 |
| anim_level=1 语义 | 增强动效档（动效补齐配方 `persist.sys.oplus.anim_level=1` 与 `animationlevel=3` 成对出现） |
| app32_version=2 | 出厂值（MTK app32 兼容，同分区有 mtk.app32_boost_support=3），**不是**模块谎报 |
| fastchg 双挂互踩 | 满血核心与本项目同挂 fastchg 表，顶层=后挂者，温度墙 485/530 随机 → 满血核心必须卸载 |
| 165Hz | 面板支持 165（supportedRefreshRates 含），系统 peak 120；别用 prop 硬改（会被 display 服务覆盖），走设置 UI |
| gaussblur_level | `debug.systemui.gaussblur_level` 是 SystemUI 模糊真旋钮（实验性，当前空=自动）；模块从未动它 |

---

## 11. 卸载与残留语义

`uninstall.sh` 覆盖（目标=零残留）：
1. cleanup.sh --force：APK 卸载 + 特性挂载 umount + settings secure 12 键 delete + 墓碑自删
2. tempctl off：温控策略挂载全卸
3. peak stop + fastchg 两处 umount
4. **删除 `/data/adb/screenoff_fix` 与 `/data/adb/screenoff_fix.log`**（v5.0 起；若要取证请卸载前手动备份）
5. persist 键按 backup/original_backup.txt 恢复（ro.* 重启自动回原值）
6. KernelSU 卸载流程本身清模块目录

---

## 12. 已知问题与遗留

| 项 | 状态 |
|---|---|
| 快充页"生效表大小"显示 `--` | status.sh 无 `sz_silicon` 键（v1.3.0 原版行为）；要修可在 status.sh 加一行或 UI 改读 sz_default |
| 动态温控（游戏/日用温度墙） | 满血核心的付费功能（作者服务器校验），**不做**（绕付费墙） |
| 滑块拖动后松手的 toast | 走队列串行，偶有 800ms 延迟，属正常 |
| WebUI 在 Chrome 打开 | 无桥接 → 红色告警条 + 快充页显示演示数据，属预期 |
| LSPosed scope | 桥接正常工作（实测读到运行日志）；APK 重装后需检查勾选 |

---

## 13. 快速验证手册（接手后直接用）

```bash
# 环境变量（每次会话都要）
export MSYS_NO_PATHCONV=1
export ADB="/c/Program Files/Oppo Connect/daemon/bin/adb.exe"

# 1. 设备在线 + 模块健康
"$ADB" shell "su -c 'ls -1 /data/adb/modules/; sh /data/adb/modules/coloros_fullpower/bin/tempctl.sh status; tail -6 /data/adb/modules/coloros_fullpower/last_boot.log'"

# 2. 温控 on/off 链路
"$ADB" shell "su -c 'sh /data/adb/modules/coloros_fullpower/bin/tempctl.sh on; sh /data/adb/modules/coloros_fullpower/bin/tempctl.sh off'"

# 3. 温度墙
"$ADB" shell "su -c 'sh /data/adb/modules/coloros_fullpower/bin/tempwall.sh get'"

# 4. 快充挂载 + 守护
"$ADB" shell "su -c 'tail -3 /data/adb/screenoff_fix.log; ps -A -o ARGS | grep peak.sh | grep -v grep'"

# 5. 晕动桥接
"$ADB" shell "settings get secure oplus_customize_antidizzy_mode; settings get secure motion_cues_gain"

# 6. WebUI 数据源
"$ADB" shell "su -c 'sh /data/adb/modules/coloros_fullpower/webroot/status.sh | head -12'"

# 7. 部署 WebUI 改动
cd /d/满血color/module_v3/webroot
"$ADB" push index.html /data/local/tmp/w_i
"$ADB" shell "su -c 'cat /data/local/tmp/w_i > /data/adb/modules/coloros_fullpower/webroot/index.html; rm -f /data/local/tmp/w_i'"
# 然后让用户在管理器里重新打开 WebUI 验收（force-stop 管理器后重进）

# 8. 打包
cd /d/满血color && python - <<'PY'
# 排除 webroot/antidizzy.html 与 webroot/charge.html（废弃文件）
# 校验：zip 内脚本无 CRLF、JS node --check 通过
PY
```

---

## 14. 版本历史

| 版本 | 内容 |
|---|---|
| 原始 prop_all_optimize | 19 键，含死键/32 位误判/skiavk 无效值（已弃） |
| 1.0 | 修正版 11 键，单通道注入 |
| 2.0 | 三层分层（核心 7 + 功能 7 + 兼容 5），按 ColorOS 版本/高刷分支；发现 vendor 前缀属性陷阱 |
| 3.0 | 合并晕动 v7.5 + KernelSU WebUI（三态自适应桥接雏形） |
| 4.0 | 合并满血快充 v1.3.0 + HyperOS 风格重构（theme.css 令牌层）+ 温度墙 |
| 4.1 | + 系统级温控（tempctl.sh）；WebUI 温度墙/系统温控卡 |
| **5.0** | **单文件 WebUI（三页合一+队列桥接+懒加载）；合并满血核心静态温控等价物（tempctl 已有）；全部 UI 按 miuix 规范重写；卸载改零残留**；bug 修复轮（滑块规范/跳左/文案语义/箭头重叠/seg 溢出/无分割线） |
| **6.0** | **快充全自适应：开机探测实际 fastchg 根 / PROJECT / 协议段 / 峰值电流 / 表最高温，温度墙与梯度上限按本机表推导；ORIG 缓存加路径+md5+目录签名；SELinux 上下文显式 chcon（不再依赖 toybox 不支持的 --reference）；系统温控原始状态快照恢复；peak 守护 setsid 逃逸 + PID cmdline 校验；APK 按 sha256 升级；WebUI 温度墙滑块动态上限** |

---

## 15. 用户偏好（对话级）

- 语言：简体中文，直接、技术流、不绕弯
- 痛恨：反复试错的 token 浪费、把简单事做复杂、改 A 文件影响 B 文件却不告知
- 喜欢的验证方式：**视觉改动让用户自己验收**，agent 用 shell 层受控实验验证逻辑
- 模块作者署名必须保持：三重 / 酷安@MieAi
- 满血核心（Caelifall_SensorDecoy）与动态温控：用户已了解取舍，勿再主动建议安装
