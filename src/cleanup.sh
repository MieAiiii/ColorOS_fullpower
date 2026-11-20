#!/system/bin/sh
# ============================================================
#  清理逻辑（晕动舒缓显示子功能）
#  来源：oplus-antidizzy-module v7.5 cleanup.sh
#  唯一改动：MODDIR 指向合并后的模块路径。
#
#  两种调用方式：
#   1) 模块内 uninstall.sh 调用（--force）：用户删除模块时立即清理
#   2) 作为「墓碑」被开机执行（/data/adb/service.d/motion_cues_cleanup.sh）：
#      模块还在 → 什么都不做；模块已删 → 清理，成功后自删
#
#  存在的意义：KernelSU 删模块只会删 /data/adb/modules/coloros_fullpower，
#  不会管 APK、Settings、临时文件，更不会停 LSPosed 注入。
#  这个脚本把那些一起带走。
# ============================================================

PKG=com.workbuddy.antidizzybridge
OLD=com.workbuddy.motioncues
MODDIR=${MODDIR:-/data/adb/modules/coloros_fullpower}

FORCE=0
[ "$1" = "--force" ] && FORCE=1

if [ "$FORCE" = "0" ]; then
  # 模块仍然存在 → 说明只是普通开机，不是卸载，直接退出
  [ -f "$MODDIR/module.prop" ] && exit 0
  # 模块没了，等系统起来再动手（pm / settings 依赖 system_server）
  i=0
  while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 120 ]; do
    sleep 1
    i=$((i + 1))
  done
  sleep 5
else
  # 立即卸载时把墓碑也带走，避免卸载后还要等下一次开机自删。
  rm -f /data/adb/service.d/motion_cues_cleanup.sh 2>/dev/null
fi

# ---- 0. 停掉峰值守护，避免它继续写即将删除的日志 ----
PIDF=/data/adb/screenoff_fix/daemon.pid
if [ -f "$PIDF" ]; then
  p=$(cat "$PIDF" 2>/dev/null)
  cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
  case "$cmd" in *peak.sh*daemon*) kill "$p" 2>/dev/null ;; esac
  rm -f "$PIDF" 2>/dev/null
fi

# ---- 1. 停注入：卸载 Xposed 桥接 APK ----
# 这一步最关键。LSPosed 的注入独立于 KernelSU 模块，
# 不卸 APK 的话即使模块删了，功能仍然在跑。
if pm path "$PKG" >/dev/null 2>&1; then
  pm uninstall "$PKG" >/dev/null 2>&1
fi
pm uninstall "$OLD" >/dev/null 2>&1

# ---- 2. 清掉写入的 Settings 键 ----
for k in oplus_customize_antidizzy_enable \
         oplus_customize_antidizzy_mode \
         oplus_customize_antidizzy_force_off \
         motion_cues_gain \
         motion_cues_gain_y \
         motion_cues_gate \
         motion_cues_bridge_test \
         motion_cues_veh_rms \
         motion_cues_veh_stop \
         motion_cues_veh_hold \
         motion_cues_veh_low \
         motion_cues_veh_rot \
         motion_cues_veh_step; do
  settings delete secure "$k" >/dev/null 2>&1
done

# ---- 3. 立即卸掉 bind mount，本轮就恢复原厂文件 ----
# 只卸“顶层是本模块 mc_feat_ 临时文件”的项，避免误删其他模块的层。
is_ours_feature() {
  awk -v t="$1" '$5==t{root=$4} END{print (root ~ /mc_feat_/) ? 1 : 0}' /proc/self/mountinfo 2>/dev/null
}
for f in /system_ext/etc/permissions/com.oplus.features_config.xml \
         /system_ext/etc/permissions/com.oplus.features_ext.xml \
         /system_ext/etc/permissions/com.oplus.features.xml \
         /my_product/etc/permissions/com.oplus.features_config.xml \
         /my_product/etc/permissions/com.oplus.features_ext.xml \
         /my_product/etc/permissions/com.oplus.features.xml \
         /my_product/etc/extension/com.oplus.oplus-feature.xml \
         /system_ext/etc/extension/com.oplus.oplus-feature.xml \
         /product/etc/extension/com.oplus.oplus-feature.xml \
         /odm/etc/permissions/com.oplus.features_config.xml \
         /odm/etc/permissions/com.oplus.features_ext.xml \
         /odm/etc/permissions/com.oplus.features.xml \
         /odm/etc/extension/com.oplus.oplus-feature.xml \
         /vendor/etc/permissions/com.oplus.features_config.xml \
         /vendor/etc/permissions/com.oplus.features_ext.xml \
         /vendor/etc/permissions/com.oplus.features.xml \
         /vendor/etc/extension/com.oplus.oplus-feature.xml; do
  j=0
  while [ "$j" -lt 3 ] && [ "$(is_ours_feature "$f")" = "1" ]; do
    umount "$f" 2>/dev/null || break
    j=$((j+1))
  done
done

# ---- 4. 清临时文件与自适应快充运行数据 ----
rm -f /data/local/tmp/motion_cues_port.log
rm -f /data/local/tmp/AntiDizzyBridge.apk
rm -f /data/local/tmp/MotionCues.apk
rm -f /data/local/tmp/mc_feat_*.xml
rm -rf /data/adb/coloros_fullpower
rm -rf /data/adb/screenoff_fix
rm -f /data/adb/screenoff_fix.log

# ---- 5. 墓碑自毁 ----
# 只有确认 APK 已经不在了才删自己，否则留着下次开机再试。
if [ "$FORCE" = "0" ]; then
  if pm path "$PKG" >/dev/null 2>&1; then
    exit 0
  fi
  rm -f "$0"
fi

exit 0
