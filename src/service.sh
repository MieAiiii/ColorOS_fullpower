#!/system/bin/sh
# ============================================================
#  ColorOS特性补全 10.0 —— 开机后一次性服务
#  作者：三重 / 酷安@MieAi
#
#  负责：
#    1) 安装/更新 LSPosed 桥接 APK
#    2) 写入晕动默认 secure 参数（仅键不存在时）
#    3) 应用高级显示层（advanced.sh）
#    4) 放置卸载墓碑，防止 KSU 直接删目录后 APK/设置残留
#
#  没有温控、没有 peak、没有常驻守护；脚本执行完即退出。
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
ENABLE_ADVANCED=$(cfg_get ENABLE_ADVANCED); [ -z "$ENABLE_ADVANCED" ] && ENABLE_ADVANCED=1

# 等系统起来（pm / settings 依赖 system_server）；一次性等待，不循环常驻
for i in $(seq 1 90); do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 1
done
sleep 3

# ---------- 卸载墓碑 ----------
# KSU 删除模块时只删模块目录，不管 APK、Settings、特性声明挂载，
# 也不管 persist 动画属性。墓碑放模块目录之外：
# 模块还在 → 开机什么都不做；模块没了 → 恢复属性并清理，成功后自删。
SD=/data/adb/service.d
if [ -d "$SD" ] || mkdir -p "$SD" 2>/dev/null; then
  cp -f "$MODDIR/cleanup.sh" "$SD/motion_cues_cleanup.sh" 2>/dev/null
  chmod 755 "$SD/motion_cues_cleanup.sh" 2>/dev/null
fi

# 用户显式关闭晕动：卸掉 APK / 设置 / 特性挂载，但保留动画属性与备份，
# 并保留墓碑，防止之后 KSU 直接删模块时动画属性无人恢复。
if [ "$ENABLE_ANTIDIZZY" != "1" ]; then
  [ -f "$MODDIR/cleanup.sh" ] && sh "$MODDIR/cleanup.sh" --motion >/dev/null 2>&1
else
  # ---------- 安装 / 更新桥接 APK ----------
  if ! pm path "$PKG" >/dev/null 2>&1; then
    cp -f "$APK" "$TMP"
    chmod 644 "$TMP"
    chcon u:object_r:shell_data_file:s0 "$TMP" 2>/dev/null
    if pm install -r -g "$TMP" >> "$LOG" 2>&1; then
      echo "bridge: installed — 请在 LSPosed 启用『AntiDizzy Bridge』并勾选『系统框架』后重启" >> "$LOG"
    else
      echo "bridge: install failed — 请手动安装 files/AntiDizzyBridge.apk" >> "$LOG"
    fi
    rm -f "$TMP"
  else
    # 模块升级时 APK 可能同尺寸，不能只比大小；
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
      if pm install -r -g "$TMP" >> "$LOG" 2>&1; then
        echo "bridge: updated — 重启后新代码生效" >> "$LOG"
      else
        echo "bridge: update failed — 旧桥接签名不一致；需卸载旧桥接后重启安装，并在 LSPosed 重新启用作用域" >> "$LOG"
      fi
      rm -f "$TMP"
    fi
  fi

  # ---------- 晕动默认参数：先写 secure，再让用户调 ----------
  # 只在键不存在时写入，不覆盖用户已经调过的值。
  seed_setting() {
    k=$1; v=$2
    cur=$(settings get secure "$k" 2>/dev/null)
    case "$cur" in
      ''|null) settings put secure "$k" "$v" >/dev/null 2>&1 ;;
    esac
  }

  # 首次启用（或升级后首次开机）只提供功能可用性，不自动打开系统里的
  # “晕动舒缓显示”。实际开关由系统设置/本模块 WebUI 的“晕动舒缓显示”控制。
  MOTION_STATE=/data/adb/coloros_fullpower/motion_seeded
  if [ ! -f "$MOTION_STATE" ]; then
    settings put system motion_sickness_relief_switch 0 >/dev/null 2>&1
    settings put secure oplus_customize_antidizzy_enable 0 >/dev/null 2>&1
    mkdir -p /data/adb/coloros_fullpower 2>/dev/null
    : > "$MOTION_STATE"
    echo "motion: seeded off — 请在系统设置或 WebUI 中手动打开晕动舒缓显示" >> "$LOG"
  fi

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
fi

# ---------- 高级显示 / 模糊 / AOD / 游戏 ----------
# 只写 Settings 与显示偏好，不碰温控、快充、CPU/GPU、分区。
if [ "$ENABLE_ADVANCED" = "1" ] && [ -f "$MODDIR/advanced.sh" ]; then
  sh "$MODDIR/advanced.sh" >> "$LOG" 2>&1
  echo "advanced: applied（详见 /data/local/tmp/coloros_advanced.log）" >> "$LOG"
fi
