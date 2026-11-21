#!/system/bin/sh
# ============================================================
#  晕动舒缓显示 —— 清理脚本
#  来源：oplus-antidizzy-module v7.5 cleanup.sh
#  唯一改动：MODDIR 指向本模块路径；移除充电/温控相关注释与数据。
#
#  三种调用方式：
#   1) 模块内 uninstall.sh 调用（--force）：用户删除模块时立即清理
#   2) service.sh 关闭晕动时调用（--motion）：只撤晕动，保留属性备份
#   3) 作为「墓碑」被开机执行（/data/adb/service.d/motion_cues_cleanup.sh）：
#      模块还在 → 什么都不做；模块已删 → 恢复属性并清理，成功后自删
#
#  存在的意义：KernelSU 删模块只会删 /data/adb/modules/coloros_fullpower，
#  不会管 APK、Settings、临时文件，更不会停 LSPosed 注入。
#  这个脚本把那些一起带走。
# ============================================================

PKG=com.workbuddy.antidizzybridge
OLD=com.workbuddy.motioncues
MODDIR=${MODDIR:-/data/adb/modules/coloros_fullpower}

FORCE=0
MOTION=0
case "$1" in
  --force)  FORCE=1 ;;
  --motion) FORCE=1; MOTION=1 ;;
esac

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
  # 卸载时把墓碑也带走；仅关闭晕动时保留墓碑，动画属性仍需它兜底。
  [ "$MOTION" = "0" ] && rm -f /data/adb/service.d/motion_cues_cleanup.sh 2>/dev/null
fi

# 模块目录被 KSU 直接删掉时，模块内的 backup 也会一起消失。
# 因此 persist/ro 原始值与 Settings 原始值另存一份在 /data/adb/coloros_fullpower/backup；
# 墓碑（FORCE=0）与卸载（--force）先恢复，再清运行数据。
PROP_BAK=/data/adb/coloros_fullpower/backup/original_backup.txt
RO_BAK=/data/adb/coloros_fullpower/backup/ro_backup.txt
SET_BAK=/data/adb/coloros_fullpower/backup/settings_backup.txt

del_prop() {
  key=$1
  if command -v resetprop >/dev/null 2>&1; then
    resetprop --delete "$key" >/dev/null 2>&1 || setprop "$key" "" 2>/dev/null
  else
    setprop "$key" "" 2>/dev/null
  fi
}

restore_props() {
  [ -f "$PROP_BAK" ] || return 0
  echo "===== 恢复 persist 属性 ====="
  while IFS="$(printf '\t')" read -r key val; do
    [ -z "$key" ] && continue
    if [ -z "$val" ]; then
      del_prop "$key"
      echo "  清除 $key"
    else
      setprop "$key" "$val"
      echo "  恢复 $key = $val"
    fi
  done < "$PROP_BAK"
}

restore_ro() {
  [ -f "$RO_BAK" ] || return 0
  echo "===== 恢复 ro 属性（重启后彻底回原值）====="
  while IFS="$(printf '\t')" read -r key val; do
    [ -z "$key" ] && continue
    if command -v resetprop >/dev/null 2>&1; then
      if [ -z "$val" ]; then
        resetprop --delete "$key" >/dev/null 2>&1
        echo "  清除 $key"
      else
        resetprop "$key" "$val" >/dev/null 2>&1
        echo "  恢复 $key = $val"
      fi
    fi
  done < "$RO_BAK"
}

restore_settings() {
  [ -f "$SET_BAK" ] || return 0
  echo "===== 恢复 Settings ====="
  while IFS="$(printf '\t')" read -r type key val; do
    [ -z "$type" ] || [ -z "$key" ] && continue
    case "$type" in
      secure|system|global) ;;
      *) continue ;;
    esac
    if [ -z "$val" ] || [ "$val" = "null" ]; then
      settings delete "$type" "$key" >/dev/null 2>&1
      echo "  清除 $type/$key"
    else
      settings put "$type" "$key" "$val" >/dev/null 2>&1
      echo "  恢复 $type/$key = $val"
    fi
  done < "$SET_BAK"
}

RESTORE=0
[ "$FORCE" = "0" ] && RESTORE=1
[ "$FORCE" = "1" ] && [ "$MOTION" = "0" ] && RESTORE=1
if [ "$RESTORE" = "1" ]; then
  restore_settings
  restore_props
  restore_ro
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

# ---- 4. 清临时文件 ----
rm -f /data/local/tmp/motion_cues_port.log
rm -f /data/local/tmp/coloros_advanced.log
rm -f /data/local/tmp/AntiDizzyBridge.apk
rm -f /data/local/tmp/MotionCues.apk
rm -f /data/local/tmp/mc_feat_*.xml
# 旧版满血/充电运行数据（若从旧版升级或残留）
# FORCE=0（墓碑）已经恢复完属性，可以整体删除；
# FORCE=1 可能是“关闭晕动”而非卸载，保留 /data/adb 下的备份给后续卸载用。
if [ "$FORCE" = "0" ]; then
  rm -rf /data/adb/coloros_fullpower /data/adb/screenoff_fix
else
  if [ "$MOTION" = "0" ]; then
    rm -rf /data/adb/coloros_fullpower/charge /data/adb/coloros_fullpower/log \
           /data/adb/coloros_fullpower/payload /data/adb/screenoff_fix
  fi
fi

# 模块关闭/卸载前先把系统里的“晕动舒缓显示”归零：桥接即使还没被
# 卸载/注销，也会在下一轮刷新时看到 enable=0 并注销传感器采样。
settings put system motion_sickness_relief_switch 0 >/dev/null 2>&1
settings put secure oplus_customize_antidizzy_enable 0 >/dev/null 2>&1
rm -f /data/adb/coloros_fullpower/motion_seeded

# ---- 5. 墓碑自毁 ----
# 只有确认 APK 已经不在了才删自己，否则留着下次开机再试。
if [ "$FORCE" = "0" ]; then
  if pm path "$PKG" >/dev/null 2>&1; then
    exit 0
  fi
  rm -f "$0"
fi

exit 0
