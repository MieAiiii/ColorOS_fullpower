#!/system/bin/sh
# ============================================================
#  ColorOS 满血特性 6.0 —— 卸载恢复
#  作者：三重 / 酷安@MieAi
#
#  顺序：
#    1) 停峰值守护
#    2) 卸系统温控层（只卸本模块顶层）
#    3) 按 profile 卸快充表（动态路径，兼容旧路径）
#    4) cleanup.sh --force 带走 APK / Settings / 特性声明层
#    5) 恢复 persist.* 到安装时备份的原值
#    6) 删除运行数据 / 墓碑
# ==========================================================

MODPATH=$1
[ -z "$MODPATH" ] && MODPATH=${0%/*}
P=/data/adb/coloros_fullpower/profile.env

# ---- 1. 停峰值守护并恢复它改过的 sysfs 运行时标志 ----
if [ -f "$MODPATH/bin/peak.sh" ]; then
  sh "$MODPATH/bin/peak.sh" restore >/dev/null 2>&1
fi

# ---- 2. 系统温控：只卸本模块的层 ----
if [ -f "$MODPATH/bin/tempctl.sh" ]; then
  sh "$MODPATH/bin/tempctl.sh" off >/dev/null 2>&1
fi

# ---- 3. 快充表：动态路径 ----
is_ours_fastchg() {
  awk -v t="$1" '$5==t{root=$4} END{print (root ~ /coloros_fullpower\/(stage|odm)/) ? 1 : 0}' /proc/self/mountinfo 2>/dev/null
}
unmount_one() {
  t=$1
  [ -n "$t" ] || return 0
  i=0
  while [ "$i" -lt 3 ] && [ "$(is_ours_fastchg "$t")" = "1" ]; do
    umount "$t" 2>/dev/null
    i=$((i+1))
  done
}

# 旧版没有 profile 时也不能猜机型：直接扫当前 mountinfo 里
# 所有挂在 ColorOS fastchg 候选根下、来源属于本模块的层。
unmount_legacy_fastchg() {
  awk '$5 ~ /^\/(odm|vendor|my_odm|my_product|product|system_ext)\/(etc\/)?firmware\/fastchg\// && $4 ~ /coloros_fullpower\/(stage|odm)/ {print $5}' \
    /proc/self/mountinfo 2>/dev/null | sort -u | while read -r t; do
      unmount_one "$t"
    done
}

if [ -f "$P" ]; then
  . "$P" 2>/dev/null
  unmount_one "$DIR_TGT"
  unmount_one "$DEFAULT_TGT"
  unmount_one "$FOLD_TGT"
fi
unmount_legacy_fastchg

# ---- 4. 晕动子功能清理（APK / Settings / 特性声明层 / 临时文件）----
if [ -f "$MODPATH/cleanup.sh" ]; then
  sh "$MODPATH/cleanup.sh" --force
else
  # 兜底：cleanup.sh 已不在时至少把最关键的做掉
  pm uninstall com.workbuddy.antidizzybridge >/dev/null 2>&1
  for f in /system_ext/etc/permissions/com.oplus.features_config.xml \
           /my_product/etc/permissions/com.oplus.features_config.xml \
           /my_product/etc/extension/com.oplus.oplus-feature.xml; do
    umount "$f" 2>/dev/null
  done
  rm -f /data/local/tmp/motion_cues_port.log /data/local/tmp/AntiDizzyBridge.apk
fi

# ---- 5. 恢复 persist 属性 ----
BAK="$MODPATH/backup/original_backup.txt"
if [ -f "$BAK" ]; then
  echo "===== 恢复 persist 属性 ====="
  while IFS="$(printf '\t')" read -r key val; do
    [ -z "$key" ] && continue
    if [ -z "$val" ]; then
      setprop "$key" ""
      echo "  清除 $key"
    else
      setprop "$key" "$val"
      echo "  恢复 $key = $val"
    fi
  done < "$BAK"
  echo "===== 完成，重启后 ro.* 自动回原值 ====="
fi

# ---- 6. 运行数据 / 墓碑 ----
rm -rf /data/adb/coloros_fullpower 2>/dev/null
rm -rf /data/adb/screenoff_fix 2>/dev/null
rm -f /data/adb/screenoff_fix.log 2>/dev/null
rm -f /data/adb/service.d/motion_cues_cleanup.sh 2>/dev/null
