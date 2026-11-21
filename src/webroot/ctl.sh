#!/system/bin/sh
# ============================================================
#  ColorOS特性补全 10.0 —— WebUI 控制脚本
#  作者：三重 / 酷安@MieAi
#
#  WebUI 通过 KernelSU 的 exec 调这里：
#    ctl.sh status
#    ctl.sh set KEY 0|1
#    ctl.sh apply
#    ctl.sh reading 0|1
#    ctl.sh motion 0|1              # 系统“晕动舒缓显示”实际开关
#    ctl.sh motionparam KEY VALUE   # gain / gain_y / gate
#    ctl.sh motionreset             # 恢复三条默认参数
# ============================================================

SELF=$0
case "$SELF" in
  /*) ;;
  *) SELF=/data/adb/modules/coloros_fullpower/webroot/ctl.sh ;;
esac
MODDIR=$(cd "${SELF%/*}/.." 2>/dev/null && pwd)
[ -n "$MODDIR" ] || MODDIR=/data/adb/modules/coloros_fullpower
CFG="$MODDIR/config.conf"
ADV="$MODDIR/advanced.sh"
PKG=com.workbuddy.antidizzybridge

cfg_get() {
  [ -f "$CFG" ] || return 0
  awk -F= -v k="$1" '$1==k {v=$2} END {print v}' "$CFG" 2>/dev/null | tr -d ' \r'
}

setting_get() {
  settings get "$1" "$2" 2>/dev/null | tr -d '\r'
}

prop_get() { getprop "$1" 2>/dev/null; }

status() {
  MODEL=$(prop_get ro.product.marketname)
  [ -z "$MODEL" ] && MODEL=$(prop_get ro.vendor.oplus.market.name)
  [ -z "$MODEL" ] && MODEL=$(prop_get ro.product.model)
  ROM=$(prop_get ro.build.version.oplusrom)
  ANDROID=$(prop_get ro.build.version.release)
  VERSION=$(grep '^version=' "$MODDIR/module.prop" 2>/dev/null | head -n1 | cut -d= -f2-)

  echo "MODEL=$MODEL"
  echo "ROM=$ROM"
  echo "ANDROID=$ANDROID"
  echo "VERSION=$VERSION"

  # 核心只读状态
  echo "ANIM_LEVEL=$(prop_get persist.sys.oplus.anim_level)"
  echo "FRAMEWORK_ANIM=$(prop_get ro.oplus.animationlevel)"
  echo "WALLPAPER_ANIM=$(prop_get persist.sys.wallpaperanimation.enable)"
  echo "BLUR_SF=$(prop_get ro.surface_flinger.supports_background_blur)"
  echo "VOLUME_BLUR=$(prop_get ro.oplus.display.disable.volume_blur)"
  echo "BLUR_SNAPSHOT=$(prop_get persist.oplus.flexible.blur_snapshot_enable)"
  echo "MATERIAL_BLUR_PROP=$(prop_get persist.sys.oplus.material_blur_switch)"
  echo "LEGACY_BLUR=$(prop_get ro.oplus.gaussianlevel)"
  echo "MEDIA_BLUR=$(prop_get ro.surface_flinger.media_panel_bg_blur)"
  echo "DYNAMIC_BLUR=$(prop_get persist.sys.oplus.systemui.dynamic_blur)"
  echo "BLUR_COST=$(prop_get ro.sf.blurs_are_expensive)"
  echo "SYS_REFRESH=$(setting_get secure oplus_customize_screen_refresh_rate)"

  # 当前 Settings 实际状态
  echo "FULL_AOD=$(setting_get secure full_screen_aod)"
  echo "AOD_CHARGE=$(setting_get secure oplus_keyguard_charge_anim_show)"
  echo "AOD_WORKSHOP=$(setting_get secure oplus_keyguard_workshop_aod_support)"
  echo "AOD_ALL_DAY=$(setting_get secure oplus_keyguard_panoramic_aod_all_day_support)"
  echo "DESKTOP_BLUR=$(setting_get secure is_desktop_wallpaper_blur_enable)"
  echo "READING_MODE=$(setting_get system oplus_customize_color_ink_enable)"
  echo "MATERIAL_BLUR=$(setting_get system system_material_blur_enable)"
  echo "MATERIAL_STROKE=$(setting_get system system_material_stroke_enable)"
  echo "FOLLOW_HAND=$(setting_get secure follow_hand)"
  echo "GAME_MEMC=$(setting_get secure display_memc_game_enable)"
  echo "GAME_COLOR=$(setting_get system game_color_enhance)"
  echo "MOTION_ACTIVE=$(setting_get secure oplus_customize_antidizzy_enable)"
  echo "MOTION_SWITCH=$(setting_get system motion_sickness_relief_switch)"
  echo "MOTION_GAIN=$(setting_get secure motion_cues_gain)"
  echo "MOTION_GAIN_Y=$(setting_get secure motion_cues_gain_y)"
  echo "MOTION_GATE=$(setting_get secure motion_cues_gate)"
  if pm path "$PKG" >/dev/null 2>&1; then
    echo "MOTION_AVAILABLE=1"
  else
    echo "MOTION_AVAILABLE=0"
  fi
  echo "HDR10P=$(prop_get persist.vendor.sys.pq.hdr10p_adaptive.en)"
  echo "HDR10=$(prop_get persist.vendor.sys.pq.hdr10_adaptive.en)"
  echo "HDRVIVID=$(prop_get persist.vendor.sys.pq.hdrvivid_adaptive.en)"
  echo "ULTRA_RES=$(prop_get persist.vendor.sys.pq.ultrares.en)"
  echo "MML_COLOR=$(prop_get persist.vendor.sys.pq.mdp.color.adaptive.en)"
  echo "SDR_ADAPTIVE=$(prop_get persist.vendor.sys.pq.sdr_adaptive.en)"

  # config.conf 当前值
  for k in ENABLE_ADVANCED ENABLE_ANTIDIZZY ENABLE_LEGACY \
           ENABLE_FULL_AOD ENABLE_AOD_CHARGE ENABLE_AOD_WORKSHOP ENABLE_ALL_DAY_AOD \
           ENABLE_DESKTOP_BLUR ENABLE_MATERIAL_BLUR ENABLE_MATERIAL_STROKE ENABLE_FOLLOW_HAND \
           ENABLE_GAME_MEMC ENABLE_GAME_COLOR \
           ENABLE_HDR10P_ADAPTIVE ENABLE_HDR10_ADAPTIVE ENABLE_HDRVIVID_ADAPTIVE \
           ENABLE_ULTRA_RESOLUTION ENABLE_MML_COLOR_ADAPTIVE ENABLE_AI_SDR_ADAPTIVE; do
    echo "CFG_${k}=$(cfg_get "$k")"
  done
}

set_cfg() {
  KEY=$1; VAL=$2
  case "$KEY" in
    ENABLE_ADVANCED|ENABLE_ANTIDIZZY|ENABLE_LEGACY|\
    ENABLE_FULL_AOD|ENABLE_AOD_CHARGE|ENABLE_AOD_WORKSHOP|ENABLE_ALL_DAY_AOD|\
    ENABLE_DESKTOP_BLUR|ENABLE_MATERIAL_BLUR|ENABLE_MATERIAL_STROKE|ENABLE_FOLLOW_HAND|\
    ENABLE_GAME_MEMC|ENABLE_GAME_COLOR|\
    ENABLE_HDR10P_ADAPTIVE|ENABLE_HDR10_ADAPTIVE|ENABLE_HDRVIVID_ADAPTIVE|\
    ENABLE_ULTRA_RESOLUTION|ENABLE_MML_COLOR_ADAPTIVE|ENABLE_AI_SDR_ADAPTIVE) ;;
    *) echo "ERR=badkey"; exit 1 ;;
  esac
  case "$VAL" in 0|1) ;; *) echo "ERR=badval"; exit 1 ;; esac

  [ -f "$CFG" ] || : > "$CFG"
  TMP="$CFG.tmp.$$"
  awk -F= -v k="$KEY" -v v="$VAL" '
    $1==k { print k"="v; found=1; next }
    { print }
    END { if(!found) print k"="v }
  ' "$CFG" > "$TMP" 2>/dev/null && mv -f "$TMP" "$CFG" 2>/dev/null || {
    rm -f "$TMP"
    echo "ERR=writefail"
    exit 1
  }
  echo "OK=$KEY=$VAL"
}

apply_all() {
  if [ -f "$ADV" ]; then
    sh "$ADV" 2>&1
    echo "APPLY=done"
  else
    echo "ERR=noadv"
    exit 1
  fi
}

motion_set() {
  VAL=$1
  case "$VAL" in 0|1) ;; *) echo "ERR=badval"; exit 1 ;; esac
  [ "$(cfg_get ENABLE_ANTIDIZZY)" = "1" ] || { echo "ERR=motion_off"; exit 1; }
  pm path "$PKG" >/dev/null 2>&1 || { echo "ERR=motion_unavailable"; exit 1; }
  settings put secure oplus_customize_antidizzy_enable "$VAL" >/dev/null 2>&1
  settings put system motion_sickness_relief_switch "$VAL" >/dev/null 2>&1
  echo "MOTION_ACTIVE=$VAL"
}

motion_write() {
  KEY=$1; VAL=$2; LO=$3; HI=$4
  echo "$VAL" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || { echo "ERR=badval"; exit 1; }
  awk -v v="$VAL" -v lo="$LO" -v hi="$HI" 'BEGIN{exit !(v>=lo && v<=hi)}' || {
    echo "ERR=outofrange"
    exit 1
  }
  settings put secure "$KEY" "$VAL" >/dev/null 2>&1
  echo "OK=$KEY=$VAL"
}

motion_param() {
  case "$1" in
    gain|motion_cues_gain) KEY=motion_cues_gain; LO=0.4; HI=2.0 ;;
    gain_y|motion_cues_gain_y) KEY=motion_cues_gain_y; LO=1.0; HI=4.0 ;;
    gate|motion_cues_gate) KEY=motion_cues_gate; LO=0.02; HI=0.20 ;;
    *) echo "ERR=badkey"; exit 1 ;;
  esac
  motion_write "$KEY" "$2" "$LO" "$HI"
}

motion_reset() {
  motion_write motion_cues_gain 1.0 0.4 2.0 || exit 1
  motion_write motion_cues_gain_y 2.5 1.0 4.0 || exit 1
  motion_write motion_cues_gate 0.08 0.02 0.20 || exit 1
  echo "MOTION_RESET=1"
}

case "$1" in
  status) status ;;
  set) shift; set_cfg "$1" "$2" ;;
  apply) apply_all ;;
  motion) motion_set "$2" ;;
  motionparam) shift; motion_param "$1" "$2" ;;
  motionreset) motion_reset ;;
  reading)
    VAL=$2
    case "$VAL" in 0|1) ;; *) echo "ERR=badval"; exit 1 ;; esac
    settings put system oplus_customize_color_ink_enable "$VAL" >/dev/null 2>&1
    echo "READING_MODE=$VAL"
    ;;
  log)
    cat /data/local/tmp/coloros_advanced.log 2>/dev/null | tail -60
    ;;
  *)
    echo "ERR=usage"
    ;;
esac
