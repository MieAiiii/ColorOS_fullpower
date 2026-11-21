#!/system/bin/sh
# ============================================================
#  ColorOS特性补全 —— 机型能力探测（被 ctl.sh / advanced.sh source）
#  只读探测，不写任何设置；所有判断按“当前系统实际存在的键”为准。
# ============================================================

ADAPT_ROM_MAJOR=""
ADAPT_LIST_SYSTEM=""
ADAPT_LIST_SECURE=""
ADAPT_LIST_GLOBAL=""
ADAPT_CAPS_READY=0

ADAPT_SUP_MATERIAL_BLUR=0
ADAPT_SUP_MATERIAL_STROKE=0
ADAPT_SUP_DESKTOP_BLUR=0
ADAPT_SUP_FULL_AOD=0
ADAPT_SUP_AOD_CHARGE=0
ADAPT_SUP_AOD_WORKSHOP=0
ADAPT_SUP_ALL_DAY_AOD=0
ADAPT_SUP_FOLLOW_HAND=0
ADAPT_SUP_GAME_MEMC=0
ADAPT_SUP_GAME_COLOR=0
ADAPT_SUP_HDR10P=0
ADAPT_SUP_HDR10=0
ADAPT_SUP_HDRVIVID=0
ADAPT_SUP_ULTRA_RES=0
ADAPT_SUP_MML_COLOR=0
ADAPT_SUP_AI_SDR=0
ADAPT_SUP_LEGACY=0
ADAPT_SUP_MOTION=0

adapt_rom_major() {
  if [ -n "$ADAPT_ROM_MAJOR" ]; then
    echo "$ADAPT_ROM_MAJOR"
    return 0
  fi
  _rom=$(getprop ro.build.version.oplusrom 2>/dev/null)
  [ -n "$_rom" ] || _rom=$(getprop ro.build.version.oplusos 2>/dev/null)
  [ -n "$_rom" ] || _rom=$(getprop ro.build.version.opporom 2>/dev/null)
  _m=$(echo "$_rom" | sed -n 's/^[Vv]\([0-9][0-9]*\).*/\1/p')
  case "$_m" in
    ''|*[!0-9]*) _m=0 ;;
  esac
  ADAPT_ROM_MAJOR=$_m
  echo "$_m"
}

adapt_list_load() {
  _type=$1
  case "$_type" in
    system) [ -n "$ADAPT_LIST_SYSTEM" ] || ADAPT_LIST_SYSTEM=$(settings list system 2>/dev/null) ;;
    secure) [ -n "$ADAPT_LIST_SECURE" ] || ADAPT_LIST_SECURE=$(settings list secure 2>/dev/null) ;;
    global) [ -n "$ADAPT_LIST_GLOBAL" ] || ADAPT_LIST_GLOBAL=$(settings list global 2>/dev/null) ;;
  esac
}

adapt_has_setting() {
  _type=$1; _key=$2
  case "$_type" in system|secure|global) ;; *) return 1 ;; esac
  adapt_list_load "$_type"
  case "$_type" in
    system) _list=$ADAPT_LIST_SYSTEM ;;
    secure) _list=$ADAPT_LIST_SECURE ;;
    global) _list=$ADAPT_LIST_GLOBAL ;;
  esac
  # 不用 grep -q 管道：grep 提前退出会让 printf 收到 SIGPIPE，
  # 个别 busybox/旧 shell 下会卡住；用 read 循环按行精确匹配。
  while IFS='=' read -r _k _v; do
    [ "$_k" = "$_key" ] && return 0
  done <<EOF
$_list
EOF
  _cur=$(settings get "$_type" "$_key" 2>/dev/null | tr -d '\r')
  case "$_cur" in ''|null|NULL) return 1 ;; *) return 0 ;; esac
}

adapt_has_prop() {
  _v=$(getprop "$1" 2>/dev/null)
  [ -n "$_v" ]
}

adapt_pkg_installed() {
  pm path "$1" >/dev/null 2>&1
}

adapt_mode() {
  _cfg=$1
  _mode=""
  [ -f "$_cfg" ] && _mode=$(awk -F= '$1=="ADAPT_MODE"{v=$2} END{print v}' "$_cfg" 2>/dev/null | tr -d ' \r')
  case "$_mode" in
    auto|compat|full) echo "$_mode" ;;
    *) echo auto ;;
  esac
}

adapt_effective_mode() {
  _mode=$1
  _rom=$2
  case "$_mode" in
    compat|full) echo "$_mode"; return 0 ;;
  esac
  # auto：ColorOS 17 且检测到材质模糊/全屏 AOD 键时走 full；其余走 compat
  if [ "$_rom" -ge 17 ] 2>/dev/null \
     && adapt_has_setting system system_material_blur_enable \
     && adapt_has_setting secure full_screen_aod; then
    echo full
  else
    echo compat
  fi
}

adapt_caps_init() {
  [ "$ADAPT_CAPS_READY" = "1" ] && return 0
  ADAPT_CAPS_READY=1
  _rom=$(adapt_rom_major)

  adapt_list_load system
  adapt_list_load secure
  adapt_list_load global

  adapt_has_setting system system_material_blur_enable && ADAPT_SUP_MATERIAL_BLUR=1
  adapt_has_setting system system_material_stroke_enable && ADAPT_SUP_MATERIAL_STROKE=1
  adapt_has_setting secure is_desktop_wallpaper_blur_enable && ADAPT_SUP_DESKTOP_BLUR=1
  adapt_has_setting secure full_screen_aod && ADAPT_SUP_FULL_AOD=1
  adapt_has_setting secure oplus_keyguard_charge_anim_show && ADAPT_SUP_AOD_CHARGE=1
  adapt_has_setting secure oplus_keyguard_workshop_aod_support && ADAPT_SUP_AOD_WORKSHOP=1
  adapt_has_setting secure oplus_keyguard_panoramic_aod_all_day_support && ADAPT_SUP_ALL_DAY_AOD=1
  adapt_has_setting secure follow_hand && ADAPT_SUP_FOLLOW_HAND=1
  adapt_has_setting secure display_memc_game_enable && ADAPT_SUP_GAME_MEMC=1
  adapt_has_setting system game_color_enhance && ADAPT_SUP_GAME_COLOR=1
  adapt_has_prop persist.vendor.sys.pq.hdr10p_adaptive.en && ADAPT_SUP_HDR10P=1
  adapt_has_prop persist.vendor.sys.pq.hdr10_adaptive.en && ADAPT_SUP_HDR10=1
  adapt_has_prop persist.vendor.sys.pq.hdrvivid_adaptive.en && ADAPT_SUP_HDRVIVID=1
  adapt_has_prop persist.vendor.sys.pq.ultrares.en && ADAPT_SUP_ULTRA_RES=1
  adapt_has_prop persist.vendor.sys.pq.mdp.color.adaptive.en && ADAPT_SUP_MML_COLOR=1
  adapt_has_prop persist.vendor.sys.pq.sdr_adaptive.en && ADAPT_SUP_AI_SDR=1

  if [ "$_rom" -gt 0 ] && [ "$_rom" -le 16 ] 2>/dev/null; then
    ADAPT_SUP_LEGACY=1
  elif adapt_has_prop ro.oplus.gaussianlevel; then
    ADAPT_SUP_LEGACY=1
  fi

  adapt_pkg_installed com.workbuddy.antidizzybridge && ADAPT_SUP_MOTION=1
}

adapt_support() {
  adapt_caps_init
  case "$1" in
    MATERIAL_BLUR) [ "$ADAPT_SUP_MATERIAL_BLUR" = "1" ] ;;
    MATERIAL_STROKE) [ "$ADAPT_SUP_MATERIAL_STROKE" = "1" ] ;;
    DESKTOP_BLUR) [ "$ADAPT_SUP_DESKTOP_BLUR" = "1" ] ;;
    FULL_AOD) [ "$ADAPT_SUP_FULL_AOD" = "1" ] ;;
    AOD_CHARGE) [ "$ADAPT_SUP_AOD_CHARGE" = "1" ] ;;
    AOD_WORKSHOP) [ "$ADAPT_SUP_AOD_WORKSHOP" = "1" ] ;;
    ALL_DAY_AOD) [ "$ADAPT_SUP_ALL_DAY_AOD" = "1" ] ;;
    FOLLOW_HAND) [ "$ADAPT_SUP_FOLLOW_HAND" = "1" ] ;;
    GAME_MEMC) [ "$ADAPT_SUP_GAME_MEMC" = "1" ] ;;
    GAME_COLOR) [ "$ADAPT_SUP_GAME_COLOR" = "1" ] ;;
    HDR10P) [ "$ADAPT_SUP_HDR10P" = "1" ] ;;
    HDR10) [ "$ADAPT_SUP_HDR10" = "1" ] ;;
    HDRVIVID) [ "$ADAPT_SUP_HDRVIVID" = "1" ] ;;
    ULTRA_RES) [ "$ADAPT_SUP_ULTRA_RES" = "1" ] ;;
    MML_COLOR) [ "$ADAPT_SUP_MML_COLOR" = "1" ] ;;
    AI_SDR) [ "$ADAPT_SUP_AI_SDR" = "1" ] ;;
    LEGACY) [ "$ADAPT_SUP_LEGACY" = "1" ] ;;
    MOTION) [ "$ADAPT_SUP_MOTION" = "1" ] ;;
    *) return 1 ;;
  esac
}

adapt_bool() {
  if adapt_support "$1"; then echo 1; else echo 0; fi
}

