#!/system/bin/sh
# ============================================================
#  ColorOS特性补全 10.0 —— 卸载恢复
#  作者：三重 / 酷安@MieAi
#
#  顺序：
#    1) cleanup.sh --force 带走 APK / secure 设置 / 特性声明挂载 / 临时文件
#    2) 恢复 persist.* 到安装时备份的原值
#    3) 删除本模块墓碑与旧版运行数据
#
#  本模块不含 fastchg / 温控 / 充电数据，卸载时无需导出或恢复这些层。
# ============================================================

MODPATH=$1
[ -z "$MODPATH" ] && MODPATH=${0%/*}

# ---- 1. 晕动子功能清理 ----
if [ -f "$MODPATH/cleanup.sh" ]; then
  sh "$MODPATH/cleanup.sh" --force
else
  # 兜底：cleanup.sh 已不在时至少把最关键的做掉
  pm uninstall com.workbuddy.antidizzybridge >/dev/null 2>&1
  pm uninstall com.workbuddy.motioncues >/dev/null 2>&1
  for f in /system_ext/etc/permissions/com.oplus.features_config.xml \
           /my_product/etc/permissions/com.oplus.features_config.xml \
           /my_product/etc/extension/com.oplus.oplus-feature.xml; do
    umount "$f" 2>/dev/null
  done
  rm -f /data/local/tmp/motion_cues_port.log /data/local/tmp/AntiDizzyBridge.apk
  rm -f /data/local/tmp/mc_feat_*.xml
fi

# ---- 2. 属性 / Settings 恢复已由 cleanup.sh --force 完成 ----
# cleanup.sh 会按 /data/adb/coloros_fullpower/backup 下的
# original_backup.txt（persist）、ro_backup.txt（ro）、
# settings_backup.txt（secure/system/global）恢复。
# 这里不再重复写，避免空值把已恢复的键又覆盖掉。

# ---- 3. 运行数据 / 墓碑 / 旧版残留 ----
rm -rf /data/adb/coloros_fullpower /data/adb/screenoff_fix 2>/dev/null
rm -f /data/adb/service.d/motion_cues_cleanup.sh 2>/dev/null
rm -f /data/local/tmp/AntiDizzyBridge.apk /data/local/tmp/mc_feat_*.xml 2>/dev/null
rm -f /data/local/tmp/coloros_advanced.log 2>/dev/null
