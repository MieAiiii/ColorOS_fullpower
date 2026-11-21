#!/system/bin/sh
# ============================================================
#  ColorOS特性补全 10.1.1 —— 安装期脚本
#  作者：三重 / 酷安@MieAi
#
#  10.1.1：动画/模糊/AOD/游戏显示补全 + 晕动桥接；新增机型能力探测与适配策略。
#  安装时会清掉旧版遗留的 bin/ odm/ webroot/、充电数据与旧配置键。
# ============================================================

ui_print " "
ui_print "=============================================="
ui_print " ColorOS特性补全 10.1.1"
ui_print " 三重 / 酷安@MieAi"
ui_print "=============================================="
ui_print " 设备: $(getprop ro.product.marketname)$(getprop ro.product.model)"
ui_print " 系统: $(getprop ro.build.version.oplusrom) / Android $(getprop ro.build.version.release)"
ui_print " "

if [ -z "$MODPATH" ] || [ ! -d "$MODPATH" ]; then
  abort "! MODPATH 无效，安装中止"
fi

# ---- 冲突检查：只检查会重复注入动画/晕动的模块 ----
CONFLICT=0
if [ -d /data/adb/modules/prop_all_optimize ]; then
  ui_print "! 检测到旧模块 prop_all_optimize（会重复改动画属性）"
  CONFLICT=1
fi
if [ -d /data/adb/modules/motion_cues_port ]; then
  ui_print "! 检测到独立模块 motion_cues_port（晕动舒缓显示）"
  ui_print "! 它已合并进本模块，两者共存会重复注入特性声明"
  CONFLICT=1
fi
if [ "$CONFLICT" = "1" ]; then
  ui_print "! 请先卸载上述模块并重启，再来安装本模块"
  abort "! 安装中止"
fi

# ---- 清掉旧版文件（升级安装时目录里可能还留着）----
rm -rf "$MODPATH/bin" "$MODPATH/odm" "$MODPATH/payload" 2>/dev/null
rm -f "$MODPATH/sys_thermal.log" "$MODPATH/sys_thermal_state.txt" \
      "$MODPATH/module.prop.bak" "$MODPATH/system.prop.bak" \
      "$MODPATH/mount.log" "$MODPATH/last_apply.log" 2>/dev/null

# 旧版运行数据 / 旧快充数据 / 旧墓碑：全部清掉，避免残留。
# 注意：/data/adb/coloros_fullpower/backup 存放本模块的 persist 原始值，
# 它必须放在模块目录之外，KSU 直接删模块目录时才不会把恢复依据一起删掉。
rm -rf /data/adb/coloros_fullpower/charge /data/adb/coloros_fullpower/log \
       /data/adb/coloros_fullpower/payload /data/adb/screenoff_fix 2>/dev/null
rm -f /data/adb/service.d/motion_cues_cleanup.sh 2>/dev/null

# ---- config.conf：保留基础开关 + 所有实验项的单开关 ----
CFG="$MODPATH/config.conf"
OLD_CFG=/data/adb/modules/coloros_fullpower/config.conf
if [ ! -f "$CFG" ] && [ -f "$OLD_CFG" ]; then
  cp -f "$OLD_CFG" "$CFG" 2>/dev/null
fi
CONFIG_KEYS="ADAPT_MODE ENABLE_LEGACY ENABLE_ANTIDIZZY ENABLE_ADVANCED ENABLE_ALL_DAY_AOD ENABLE_HDR10_ADAPTIVE ENABLE_HDRVIVID_ADAPTIVE ENABLE_ULTRA_RESOLUTION ENABLE_MML_COLOR_ADAPTIVE ENABLE_AI_SDR_ADAPTIVE ENABLE_FULL_AOD ENABLE_AOD_CHARGE ENABLE_AOD_WORKSHOP ENABLE_DESKTOP_BLUR ENABLE_MATERIAL_BLUR ENABLE_MATERIAL_STROKE ENABLE_FOLLOW_HAND ENABLE_GAME_MEMC ENABLE_GAME_COLOR ENABLE_HDR10P_ADAPTIVE"
if [ -f "$CFG" ]; then
  awk -F= -v keys="$CONFIG_KEYS" 'BEGIN{n=split(keys,a," "); for(i=1;i<=n;i++) keep[a[i]]=1} keep[$1]' "$CFG" > "$CFG.tmp" 2>/dev/null \
    && mv -f "$CFG.tmp" "$CFG" 2>/dev/null
  grep -q '^ADAPT_MODE=' "$CFG" 2>/dev/null || echo 'ADAPT_MODE=auto' >> "$CFG"
  grep -q '^ENABLE_LEGACY=' "$CFG" 2>/dev/null || echo 'ENABLE_LEGACY=0' >> "$CFG"
  grep -q '^ENABLE_ANTIDIZZY=' "$CFG" 2>/dev/null || echo 'ENABLE_ANTIDIZZY=1' >> "$CFG"
  grep -q '^ENABLE_ADVANCED=' "$CFG" 2>/dev/null || echo 'ENABLE_ADVANCED=1' >> "$CFG"
  grep -q '^ENABLE_ALL_DAY_AOD=' "$CFG" 2>/dev/null || echo 'ENABLE_ALL_DAY_AOD=0' >> "$CFG"
  grep -q '^ENABLE_HDR10_ADAPTIVE=' "$CFG" 2>/dev/null || echo 'ENABLE_HDR10_ADAPTIVE=0' >> "$CFG"
  grep -q '^ENABLE_HDRVIVID_ADAPTIVE=' "$CFG" 2>/dev/null || echo 'ENABLE_HDRVIVID_ADAPTIVE=0' >> "$CFG"
  grep -q '^ENABLE_ULTRA_RESOLUTION=' "$CFG" 2>/dev/null || echo 'ENABLE_ULTRA_RESOLUTION=0' >> "$CFG"
  grep -q '^ENABLE_MML_COLOR_ADAPTIVE=' "$CFG" 2>/dev/null || echo 'ENABLE_MML_COLOR_ADAPTIVE=0' >> "$CFG"
  grep -q '^ENABLE_AI_SDR_ADAPTIVE=' "$CFG" 2>/dev/null || echo 'ENABLE_AI_SDR_ADAPTIVE=0' >> "$CFG"
  grep -q '^ENABLE_FULL_AOD=' "$CFG" 2>/dev/null || echo 'ENABLE_FULL_AOD=1' >> "$CFG"
  grep -q '^ENABLE_AOD_CHARGE=' "$CFG" 2>/dev/null || echo 'ENABLE_AOD_CHARGE=1' >> "$CFG"
  grep -q '^ENABLE_AOD_WORKSHOP=' "$CFG" 2>/dev/null || echo 'ENABLE_AOD_WORKSHOP=1' >> "$CFG"
  grep -q '^ENABLE_DESKTOP_BLUR=' "$CFG" 2>/dev/null || echo 'ENABLE_DESKTOP_BLUR=1' >> "$CFG"
  grep -q '^ENABLE_MATERIAL_BLUR=' "$CFG" 2>/dev/null || echo 'ENABLE_MATERIAL_BLUR=1' >> "$CFG"
  grep -q '^ENABLE_MATERIAL_STROKE=' "$CFG" 2>/dev/null || echo 'ENABLE_MATERIAL_STROKE=1' >> "$CFG"
  grep -q '^ENABLE_FOLLOW_HAND=' "$CFG" 2>/dev/null || echo 'ENABLE_FOLLOW_HAND=1' >> "$CFG"
  grep -q '^ENABLE_GAME_MEMC=' "$CFG" 2>/dev/null || echo 'ENABLE_GAME_MEMC=1' >> "$CFG"
  grep -q '^ENABLE_GAME_COLOR=' "$CFG" 2>/dev/null || echo 'ENABLE_GAME_COLOR=1' >> "$CFG"
  grep -q '^ENABLE_HDR10P_ADAPTIVE=' "$CFG" 2>/dev/null || echo 'ENABLE_HDR10P_ADAPTIVE=1' >> "$CFG"
  ui_print "- 已保留基础开关和实验项的单开关"
fi
if [ ! -f "$CFG" ]; then
  cat > "$CFG" <<'CFGEOF'
# ColorOS特性补全 10.1.1 配置
# 1 = 启用，0 = 关闭。改完重启生效。
# 动画/模糊核心在 system.prop 常驻，不受这里控制。
# 刷新率与分辨率不在本模块修改，保持系统默认。
# ADAPT_MODE：auto=按机型能力自动，compat=只应用稳定项，full=显示全部（物理不支持仍不写）。

ADAPT_MODE=auto
ENABLE_LEGACY=0
ENABLE_ANTIDIZZY=1
ENABLE_ADVANCED=1

# ---- WebUI 可统一控制的默认项（默认开，可单独关）----
ENABLE_FULL_AOD=1
ENABLE_AOD_CHARGE=1
ENABLE_AOD_WORKSHOP=1
ENABLE_DESKTOP_BLUR=1
ENABLE_MATERIAL_BLUR=1
ENABLE_MATERIAL_STROKE=1
ENABLE_FOLLOW_HAND=1
ENABLE_GAME_MEMC=1
ENABLE_GAME_COLOR=1
ENABLE_HDR10P_ADAPTIVE=1

# ---- 实验项：默认 0，想要就自己改成 1 并重启 ----

# 全天全景 AOD（ColorOS 官方默认关闭；耗电/烧屏风险）
ENABLE_ALL_DAY_AOD=0

# HDR10 adaptive（硬件支持标记 0；打开不一定生效）
ENABLE_HDR10_ADAPTIVE=0

# HDR Vivid adaptive（硬件支持标记 0；打开不一定生效）
ENABLE_HDRVIVID_ADAPTIVE=0

# 视频超分（ultrares；硬件支持标记 0；打开不一定生效）
ENABLE_ULTRA_RESOLUTION=0

# MML 色彩自适应（硬件支持标记 0；打开不一定生效）
ENABLE_MML_COLOR_ADAPTIVE=0

# AI SDR→HDR：没有独立持久键，开关写入已有的 SDR adaptive 作为可试入口
ENABLE_AI_SDR_ADAPTIVE=0
CFGEOF
  ui_print "- 已生成 config.conf（基础开关 + 6 个实验项开关）"
fi

# ---- 备份 persist / ro 原始值（卸载/墓碑恢复）----
# 安装时备份；升级安装时只补缺失键，不覆盖第一次安装的原值。
PERSIST_KEYS="persist.sys.oplus.anim_level
persist.sys.wallpaperanimation.enable
persist.oplus.flexible.blur_snapshot_enable
persist.sys.oplus.material_blur_switch
persist.sys.oplus.systemui.dynamic_blur
persist.vendor.sys.pq.hdr10p_adaptive.en
persist.vendor.sys.pq.hdr10_adaptive.en
persist.vendor.sys.pq.hdrvivid_adaptive.en
persist.vendor.sys.pq.ultrares.en
persist.vendor.sys.pq.ultrares.strength
persist.vendor.sys.pq.mdp.color.adaptive.en
persist.vendor.sys.pq.sdr_adaptive.en"

RO_KEYS="ro.oplus.animationlevel
ro.surface_flinger.supports_background_blur
ro.oplus.display.disable.volume_blur
ro.oplus.gaussianlevel
ro.launcher.blur.appLaunch
ro.surface_flinger.media_panel_bg_blur
ro.sf.blurs_are_expensive
ro.oplus.panoramic_aod_support"

DATA=/data/adb/coloros_fullpower
EXT_BAK="$DATA/backup/original_backup.txt"
RO_BAK="$DATA/backup/ro_backup.txt"
BAK="$MODPATH/backup/original_backup.txt"
RO_MOD_BAK="$MODPATH/backup/ro_backup.txt"
mkdir -p "$MODPATH/backup" "$DATA/backup"

backup_props() {
  target=$1; shift
  [ -f "$target" ] || : > "$target"
  for key in "$@"; do
    # 已有该键（哪怕原值为空）就保留第一次安装时的值，不覆盖
    if grep -q "^${key}	" "$target" 2>/dev/null; then
      continue
    fi
    printf '%s\t%s\n' "$key" "$(getprop "$key")" >> "$target"
  done
}

backup_props "$EXT_BAK" $PERSIST_KEYS
backup_props "$RO_BAK" $RO_KEYS

if [ ! -f "$BAK" ]; then
  cp -f "$EXT_BAK" "$BAK" 2>/dev/null
fi
if [ ! -f "$RO_MOD_BAK" ]; then
  cp -f "$RO_BAK" "$RO_MOD_BAK" 2>/dev/null
fi
ui_print "- 已备份 persist / ro 属性到 /data/adb（模块目录被删也能恢复）"

# ---- 权限 ----
for f in post-fs-data.sh service.sh advanced.sh cleanup.sh uninstall.sh; do
  [ -f "$MODPATH/$f" ] && chmod 755 "$MODPATH/$f"
done
[ -f "$MODPATH/webroot/ctl.sh" ] && chmod 755 "$MODPATH/webroot/ctl.sh"

ui_print " "
ui_print "- 常驻层（system.prop）：动画档位 / 壁纸动画 / 背景模糊 / 音量模糊 / 模糊快照 / 材质模糊 / 媒体面板模糊"
ui_print "- 可选层（config.conf）：全屏 AOD、桌面壁纸模糊、材质模糊、游戏 MEMC/HDR、旧版模糊键"
ui_print "- 实验层：全天全景 AOD、HDR10/Vivid、视频超分、MML 色彩、AI SDR→HDR，默认关闭"
ui_print "- 晕动桥接：WebUI 提供显示开关与“晕动控制”二级页（强度 / 纵向增益 / 阈值）"
ui_print "- 晕动舒缓需在 LSPosed 中启用『AntiDizzy Bridge』并勾选『系统框架』"
ui_print "- 本模块只写 Settings 与显示属性，不修改温控、充电、刷新率或分辨率"
ui_print " "
ui_print "=============================================="
ui_print " 安装完成，重启生效"
ui_print " 开机异常时：启动阶段连按音量键进入安全模式"
ui_print "=============================================="
ui_print " "


