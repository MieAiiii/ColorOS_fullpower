#!/system/bin/sh
# ============================================================
#  ColorOS 满血特性 6.0.2 —— 开机后服务
#  作者：三重 / 酷安@MieAi
#
#  四件事：
#    1) 满血快充：拉起峰值保持守护（若 ENABLE_PEAK=1）
#    2) 系统温控：boot_completed 后再确认一次顶层挂载
#    3) 晕动舒缓：把 UI 默认参数种进 secure 设置，避免
#       Bridge 内置默认值与 WebUI 显示不一致
#    4) 晕动舒缓：安装 LSPosed 桥接 APK
# ============================================================

MODDIR=${0%/*}
CFG="$MODDIR/config.conf"
LOG=/data/local/tmp/motion_cues_port.log
PKG=com.workbuddy.antidizzybridge
APK="$MODDIR/files/AntiDizzyBridge.apk"
TMP=/data/local/tmp/AntiDizzyBridge.apk

cfg_get() {
  [ -f "$CFG" ] || return 0
  awk -F= -v k="$1" '$1==k {v=$2} END {print v}' "$CFG" 2>/dev/null | tr -d ' \r'
}

ENABLE_ANTIDIZZY=$(cfg_get ENABLE_ANTIDIZZY); [ -z "$ENABLE_ANTIDIZZY" ] && ENABLE_ANTIDIZZY=1
ENABLE_SYSTHERMAL=$(cfg_get ENABLE_SYSTHERMAL); [ -z "$ENABLE_SYSTHERMAL" ] && ENABLE_SYSTHERMAL=0
ENABLE_PEAK=$(cfg_get ENABLE_PEAK);             [ -z "$ENABLE_PEAK" ] && ENABLE_PEAK=1

# 等系统起来（pm / settings 依赖 system_server）
for i in $(seq 1 90); do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 1
done
sleep 3

# ---------- 满血快充：峰值保持守护 ----------
if [ "$ENABLE_PEAK" = "1" ]; then
  sh "$MODDIR/bin/peak.sh" start >/dev/null 2>&1
  echo "$(date '+%F %T') service.sh invoked peak.sh start" >> /data/adb/screenoff_fix/log/daemon.log 2>/dev/null
else
  sh "$MODDIR/bin/peak.sh" stop >/dev/null 2>&1
  echo "$(date '+%F %T') service.sh peak disabled by config" >> /data/adb/screenoff_fix/log/daemon.log 2>/dev/null
fi

# ---------- 系统级温控：boot_completed 后再确认顶层 ----------
# post-fs-data 已做首次覆盖；这里再跑一次幂等 on，
# 覆盖「horae / thermal 服务在 post-fs-data 之后才拉起」的情况。
if [ "$ENABLE_SYSTHERMAL" = "1" ]; then
  sh "$MODDIR/bin/tempctl.sh" on >/dev/null 2>&1
  setprop persist.sys.horae.enable 0 2>/dev/null
  setprop ctl.stop horae 2>/dev/null
  setprop ctl.stop thermal-engine 2>/dev/null
  echo "$(date '+%F %T') systhermal: re-assert top layers + stop horae" >> "$MODDIR/sys_thermal.log" 2>/dev/null
else
  # 开关为 0 时也要在开机后确认一次：旧 state 为空时 post-fs-data 不会调用 off，
  # horae 可能仍停在 stopped。off 只卸本模块层，并 restore_services 拉起 horae。
  sh "$MODDIR/bin/tempctl.sh" off >/dev/null 2>&1
  echo "$(date '+%F %T') systhermal: config off, ensure horae restored" >> "$MODDIR/sys_thermal.log" 2>/dev/null
fi

# ---------- 晕动舒缓显示 ----------
[ "$ENABLE_ANTIDIZZY" = "1" ] || exit 0

# 安装「卸载墓碑」：模块被删后，KernelSU 只删模块目录，
# 不管 APK、Settings、LSPosed 注入。墓碑放模块目录之外，
# 下次开机检查模块是否还在：还在 → 什么都不做；不在了 → 清理并自删。
SD=/data/adb/service.d
if [ -d "$SD" ] || mkdir -p "$SD" 2>/dev/null; then
  cp -f "$MODDIR/cleanup.sh" "$SD/motion_cues_cleanup.sh" 2>/dev/null
  chmod 755 "$SD/motion_cues_cleanup.sh" 2>/dev/null
fi

if ! pm path "$PKG" >/dev/null 2>&1; then
  cp -f "$APK" "$TMP"
  chmod 644 "$TMP"
  chcon u:object_r:shell_data_file:s0 "$TMP" 2>/dev/null
  pm install -r -g "$TMP" >> "$LOG" 2>&1
  echo "bridge: installed — 请在 LSPosed 启用『AntiDizzy Bridge』并勾选『系统框架』后重启" >> "$LOG"
else
  # 模块升级时 APK 可能同尺寸（37319 B），不能只比大小；
  # 用模块内 APK 与已安装 base.apk 的 sha256 比较，不同才覆盖安装。
  APK_PATH=$(pm path "$PKG" 2>/dev/null | sed -n 's/^package://p' | head -n 1)
  WANT_SHA=""
  HAVE_SHA=""
  command -v sha256sum >/dev/null 2>&1 && WANT_SHA=$(sha256sum "$APK" 2>/dev/null | awk '{print $1}')
  [ -n "$APK_PATH" ] && command -v sha256sum >/dev/null 2>&1 && HAVE_SHA=$(sha256sum "$APK_PATH" 2>/dev/null | awk '{print $1}')
  if [ -n "$WANT_SHA" ] && [ "$WANT_SHA" != "$HAVE_SHA" ]; then
    cp -f "$APK" "$TMP"
    chmod 644 "$TMP"
    chcon u:object_r:shell_data_file:s0 "$TMP" 2>/dev/null
    pm install -r -g "$TMP" >> "$LOG" 2>&1
    echo "bridge: updated — 重启后新代码生效" >> "$LOG"
  fi
fi

# ---------- 晕动默认参数：先写 secure，再让用户调 ----------
# Bridge 内置默认值与 WebUI 推荐值保持一致（0.12 / 0.55 / 0.12 / 0.45 / 8s）。
# 这里只在键不存在时写入，不覆盖用户已经调过的值；因此首次打开页面前，
# 实际行为与页面显示就是同一套参数。
seed_setting() {
  k=$1; v=$2
  cur=$(settings get secure "$k" 2>/dev/null)
  case "$cur" in
    ''|null) settings put secure "$k" "$v" >/dev/null 2>&1 ;;
  esac
}

if pm path "$PKG" >/dev/null 2>&1; then
  seed_setting motion_cues_gain 1.0
  seed_setting motion_cues_gain_y 2.5
  seed_setting motion_cues_gate 0.08
  seed_setting motion_cues_veh_rms 0.12
  seed_setting motion_cues_veh_low 0.55
  seed_setting motion_cues_veh_rot 0.12
  seed_setting motion_cues_veh_step 0.45
  seed_setting motion_cues_veh_hold 8
  seed_setting motion_cues_bridge_test 0
fi
