#!/system/bin/sh
# ============================================================
#  ColorOS 满血特性 6.0.2 —— 安装期脚本
#  作者：三重 / 酷安@MieAi
#
#  6.0 起快充表不再内置机型参数：安装时只检查目录是否存在，
#  真正的 PROJECT / 协议段 / 最大电流 / 温度墙在首次开机探测。
# ============================================================

ui_print " "
ui_print "=============================================="
ui_print " ColorOS 满血特性 6.0.2"
ui_print " 三重 / 酷安@MieAi"
ui_print "=============================================="
ui_print " 设备: $(getprop ro.product.marketname)$(getprop ro.product.model)"
ui_print " 系统: $(getprop ro.build.version.oplusrom) / Android $(getprop ro.build.version.release)"
ui_print " "

if [ -z "$MODPATH" ] || [ ! -d "$MODPATH" ]; then
  abort "! MODPATH 无效，安装中止"
fi

# ---- 冲突检查 ----
CONFLICT=0
if [ -d /data/adb/modules/prop_all_optimize ]; then
  ui_print "! 检测到旧模块 prop_all_optimize"
  CONFLICT=1
fi
if [ -d /data/adb/modules/motion_cues_port ]; then
  ui_print "! 检测到独立模块 motion_cues_port（晕动舒缓显示）"
  ui_print "! 它已合并进本模块，两者共存会重复注入特性声明"
  CONFLICT=1
fi
for old in screenoff_fix zz_screenoff_fix zz_chargeboost; do
  if [ -d "/data/adb/modules/$old" ]; then
    ui_print "! 检测到旧快充模块 $old"
    ui_print "! 它们会与本模块重复挂载 /odm/firmware/fastchg"
    CONFLICT=1
  fi
done
if [ "$CONFLICT" = "1" ]; then
  ui_print "! 请先卸载上述模块并重启，再来安装本模块"
  abort "! 安装中止"
fi

# ---- 清理残留 ----
rm -f "$MODPATH/module.prop.bak" "$MODPATH/system.prop.bak" \
      "$MODPATH/mount.log" "$MODPATH/last_apply.log" 2>/dev/null

# ---- 生成 config.conf（已存在则保留用户改动）----
CFG="$MODPATH/config.conf"
OLD_CFG=/data/adb/modules/coloros_fullpower/config.conf
if [ ! -f "$CFG" ] && [ -f "$OLD_CFG" ]; then
  cp -f "$OLD_CFG" "$CFG" 2>/dev/null
  ui_print "- 已继承旧模块的 config.conf"
fi
if [ ! -f "$CFG" ]; then
  cat > "$CFG" <<'CFGEOF'
# ColorOS 满血特性 6.0.2 配置
# 1 = 启用，0 = 关闭。改完重启生效，也可以在 WebUI 里点开关。
# 核心层（动画 / 模糊）在 system.prop 里常驻，不受这里控制。

# 相机类特性补齐（实况照片 / 快捷分享 / Lumo / 延迟拍摄）
ENABLE_CAMERA=1

# 音频类（清灰排水）
ENABLE_AUDIO=1

# 120 帧屏幕录制（仅在检测到高刷设备时生效）
ENABLE_RECORDER=1

# 【实验性】旧版模糊键（gaussianlevel / panoramic_aod 等）
# 只在 ColorOS 16 及以下可能有消费者，17 上已确认无效。
# 默认关闭，不确定就不要开。
ENABLE_LEGACY=0

# 晕动舒缓显示（需要 LSPosed，首次要手动启用桥接并勾选「系统框架」）
ENABLE_ANTIDIZZY=1

# 【高风险】系统级温控：高温不降频、不降亮度刷新率、充电不降速，
# 禁用 horae 与系统温控策略（sys_thermal_control / high_temp_protect）。
# 内核 118.8℃ 熔断与电池温度保护仍保留。默认关闭，想清楚再开。
ENABLE_SYSTHERMAL=0

# 满血快充：开机探测本机 /odm 等固件目录的 PROJECT、协议段、
# 最大电流与 gear 阶梯，按设备自身表生成温度墙；不内置机型/电流/温度。
# 关闭后重启不再叠加，峰值守护也会停止。
ENABLE_PEAK=1

# 温度墙（0.1℃）。0 = 按本机表峰值电流、峰值持续温度与表最高温度自动选：
#   峰值越大、原厂允许的满流温度越高，墙越高；范围 44.0℃–本机 wall_max（≤58.0℃）。
#   手动可填 440-wall_max；WebUI 会写回这里。
TEMP_WALL=0
CFGEOF
  ui_print "- 已生成 config.conf（快充表自适应）"
else
  ui_print "- 检测到已有 config.conf，保留你的配置"
fi

# ---- 检查快充目录（没有也不 abort，其他功能仍可用）----
FASTCHG_CANDIDATES="/odm/firmware/fastchg /odm/etc/firmware/fastchg /vendor/firmware/fastchg /vendor/etc/firmware/fastchg /my_odm/firmware/fastchg /my_product/firmware/fastchg /product/firmware/fastchg /system_ext/firmware/fastchg"
FC_FOUND=0
for d in $FASTCHG_CANDIDATES; do [ -d "$d" ] && { FC_FOUND=1; break; }; done
if [ "$FC_FOUND" = "1" ]; then
  ui_print "- 已检测到快充温控目录，首次开机自动识别表结构"
else
  ui_print "! 未检测到快充温控目录：快充表叠加将跳过"
  ui_print "! 相机 / 音频 / 动画 / 晕动 / 系统温控仍可正常使用"
fi

# ---- 备份 persist 原始值 ----
PERSIST_KEYS="persist.sys.oplus.anim_level
persist.sys.wallpaperanimation.enable
persist.oplus.flexible.blur_snapshot_enable
persist.sys.oplus.material_blur_switch"

mkdir -p "$MODPATH/backup"
BAK="$MODPATH/backup/original_backup.txt"
OLD_BAK=/data/adb/modules/coloros_fullpower/backup/original_backup.txt
if [ ! -f "$BAK" ] && [ -f "$OLD_BAK" ]; then
  cp -f "$OLD_BAK" "$BAK" 2>/dev/null
fi
if [ ! -f "$BAK" ]; then
  : > "$BAK"
  COUNT=0
  for key in $PERSIST_KEYS; do
    printf '%s\t%s\n' "$key" "$(getprop "$key")" >> "$BAK"
    COUNT=$((COUNT + 1))
  done
  ui_print "- 已备份 $COUNT 个 persist 属性（卸载时恢复）"
else
  ui_print "- 保留首次安装时的 persist 原始备份（不覆盖）"
fi

# ---- 权限 ----
[ -f "$MODPATH/post-fs-data.sh" ] && chmod 755 "$MODPATH/post-fs-data.sh"
[ -f "$MODPATH/service.sh" ] && chmod 755 "$MODPATH/service.sh"
[ -f "$MODPATH/cleanup.sh" ] && chmod 755 "$MODPATH/cleanup.sh"
[ -f "$MODPATH/uninstall.sh" ] && chmod 755 "$MODPATH/uninstall.sh"
chmod 755 "$MODPATH/bin/peak.sh" "$MODPATH/bin/cap.sh" \
          "$MODPATH/bin/tempwall.sh" "$MODPATH/bin/tempctl.sh" \
          "$MODPATH/webroot/status.sh" 2>/dev/null
chmod 644 "$MODPATH/bin/tablegen.awk" 2>/dev/null

ui_print " "
ui_print "- 核心层（常驻）："
while IFS= read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  ui_print "    $line"
done < "$MODPATH/system.prop"

ui_print " "
ui_print "- WebUI：模块列表 → 本模块 → 打开"
ui_print "- 快充页会显示自动识别到的 PROJECT / 协议段 / 最大电流 / 温度墙"
ui_print "- 晕动舒缓显示需在 LSPosed 中启用『AntiDizzy Bridge』并勾选『系统框架』"
ui_print "- 本模块不含机型伪装与安全伪装"
ui_print " "
ui_print "=============================================="
ui_print " 安装完成，重启生效"
ui_print " 开机异常时：启动阶段连按音量键进入安全模式"
ui_print "=============================================="
ui_print " "
