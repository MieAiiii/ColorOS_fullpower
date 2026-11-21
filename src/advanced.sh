#!/system/bin/sh
# ============================================================
#  ColorOS特性补全 10.1 —— 高级显示 / 模糊 / AOD / 游戏增强
#  作者：三重 / 酷安@MieAi
#
#  只在 ENABLE_ADVANCED=1 时执行；首次执行会备份原始 Settings，
#  卸载/墓碑用 settings_backup.txt 恢复。
#
#  这里只写实机验证过、不会改动温控/快充/分区的设置：
#    - 不修改刷新率；系统刷新率策略保持默认
#    - 全屏 AOD / 锁屏充电动画 / AOD 工坊
#    - 桌面壁纸模糊 / 材质模糊 / 模糊快照（不碰护眼/阅读模式）
#    - 侧滑跟手相关候选键、磁贴动画速度
#    - 游戏 MEMC / 色彩增强 / HDR10+ adaptive
#    - 未开项目由 config.conf 的 ENABLE_* 开关单独控制
#
#  不碰：thermal、fastchg、cpu、gpu、分区、selinux。
# ============================================================

MODDIR=${0%/*}
CFG="$MODDIR/config.conf"
LOG=${LOG:-/data/local/tmp/coloros_advanced.log}
DATA=${DATA:-/data/adb/coloros_fullpower}
BAK="$DATA/backup/settings_backup.txt"
[ -f "$MODDIR/webroot/adapt.sh" ] && . "$MODDIR/webroot/adapt.sh"

cfg_get() {
  [ -f "$CFG" ] || return 0
  awk -F= -v k="$1" '$1==k {v=$2} END {print v}' "$CFG" 2>/dev/null | tr -d ' \r'
}

ENABLE_ADVANCED=$(cfg_get ENABLE_ADVANCED)
[ -z "$ENABLE_ADVANCED" ] && ENABLE_ADVANCED=1
[ "$ENABLE_ADVANCED" = "1" ] || exit 0

mkdir -p "$DATA/backup" 2>/dev/null
: > "$LOG"

log() { echo "$*" >> "$LOG"; }

# ---------- 备份 ----------
# 文件格式：type<TAB>key<TAB>value
# value 为空表示原值为 null/不存在，恢复时用 settings delete。
backup_setting() {
  type=$1; key=$2
  [ -f "$BAK" ] || : > "$BAK"
  if grep -q "^${type}	${key}	" "$BAK" 2>/dev/null; then
    return 0
  fi
  cur=$(settings get "$type" "$key" 2>/dev/null | tr -d '\r')
  case "$cur" in null) cur="" ;; esac
  printf '%s\t%s\t%s\n' "$type" "$key" "$cur" >> "$BAK"
}

backup_all() {
  backup_setting secure full_screen_aod
  backup_setting secure is_desktop_wallpaper_blur_enable
  backup_setting secure oplus_keyguard_charge_anim_show
  backup_setting secure oplus_keyguard_workshop_aod_support
  backup_setting secure oplus_keyguard_panoramic_aod_all_day_support
  backup_setting secure follow_hand
  backup_setting secure oplus_page_slide_with_gesture
  backup_setting secure oplus_page_slide_against_gesture
  backup_setting secure oplus_tile_icon_animation_speed
  backup_setting secure display_memc_game_enable
  backup_setting system game_color_enhance
  backup_setting system system_material_blur_enable
  backup_setting system system_material_stroke_enable
  backup_setting system animationBlurrySwitch
  backup_setting global animator_duration_scale
  backup_setting global transition_animation_scale
  backup_setting global window_animation_scale
  backup_setting global media_fluid_disable_anim
}

# ---------- 写入 ----------
set_setting() {
  type=$1; key=$2; val=$3
  cur=$(settings get "$type" "$key" 2>/dev/null | tr -d '\r')
  case "$cur" in null) cur="" ;; esac
  if [ "$cur" = "$val" ]; then
    log "SKIP  $type/$key = $val"
    return 0
  fi
  settings put "$type" "$key" "$val" >/dev/null 2>&1
  now=$(settings get "$type" "$key" 2>/dev/null | tr -d '\r')
  case "$now" in null) now="" ;; esac
  if [ "$now" = "$val" ]; then
    log "SET   $type/$key = $val"
  else
    log "FAIL  $type/$key want=[$val] got=[$now]"
  fi
}

set_pq() {
  key=$1; val=$2
  cur=$(getprop "$key")
  if [ "$cur" = "$val" ]; then
    log "SKIP  $key = $val"
    return 0
  fi
  setprop "$key" "$val" 2>/dev/null
  now=$(getprop "$key")
  if [ "$now" = "$val" ]; then
    log "SET   $key = $val"
  else
    log "FAIL  $key want=[$val] got=[$now]"
  fi
}

# 只对当前系统声明支持的项写入；不支持的项只记录，不创建假键。
set_optional_setting() {
  type=$1; key=$2; val=$3; feat=$4
  if [ "$(adapt_bool "$feat")" = "1" ]; then
    if adapt_has_setting "$type" "$key"; then
      set_setting "$type" "$key" "$val"
    else
      log "N/A   $type/$key（键不存在，不创建）"
    fi
  else
    log "N/A   $type/$key（当前机型未声明 $feat）"
  fi
}

set_optional_pq() {
  key=$1; val=$2; feat=$3
  _sup=$(adapt_bool "$feat")
  if [ "$_sup" = "1" ] && adapt_has_prop "$key"; then
    set_pq "$key" "$val"
  elif [ "$_sup" = "1" ]; then
    log "N/A   $key（属性不存在，不创建）"
  else
    log "N/A   $key（当前机型未声明 $feat）"
  fi
}

ADAPT_MODE=$(adapt_mode "$CFG")
ROM_MAJOR=$(adapt_rom_major)
ADAPT_EFFECTIVE=$(adapt_effective_mode "$ADAPT_MODE" "$ROM_MAJOR")
# 在父 shell 先算一次能力，后续 $(adapt_bool) 子 shell 直接复用；
# 否则每次判断都会重新扫 settings，低端机上会明显拖慢应用。
adapt_caps_init

backup_all

# 基础可控项：默认开启，WebUI/config.conf 可关
MAT_BLUR=$(cfg_get ENABLE_MATERIAL_BLUR); [ -z "$MAT_BLUR" ] && MAT_BLUR=1
MAT_STROKE=$(cfg_get ENABLE_MATERIAL_STROKE); [ -z "$MAT_STROKE" ] && MAT_STROKE=1
FULL_AOD=$(cfg_get ENABLE_FULL_AOD); [ -z "$FULL_AOD" ] && FULL_AOD=1
AOD_CHARGE=$(cfg_get ENABLE_AOD_CHARGE); [ -z "$AOD_CHARGE" ] && AOD_CHARGE=1
AOD_WORKSHOP=$(cfg_get ENABLE_AOD_WORKSHOP); [ -z "$AOD_WORKSHOP" ] && AOD_WORKSHOP=1
DESKTOP_BLUR=$(cfg_get ENABLE_DESKTOP_BLUR); [ -z "$DESKTOP_BLUR" ] && DESKTOP_BLUR=1
FOLLOW_HAND=$(cfg_get ENABLE_FOLLOW_HAND); [ -z "$FOLLOW_HAND" ] && FOLLOW_HAND=1
GAME_MEMC=$(cfg_get ENABLE_GAME_MEMC); [ -z "$GAME_MEMC" ] && GAME_MEMC=1
GAME_COLOR=$(cfg_get ENABLE_GAME_COLOR); [ -z "$GAME_COLOR" ] && GAME_COLOR=1
HDR10P=$(cfg_get ENABLE_HDR10P_ADAPTIVE); [ -z "$HDR10P" ] && HDR10P=1

# 动画/模糊：只改当前系统存在的材质/模糊键
set_optional_setting system system_material_blur_enable "$MAT_BLUR" MATERIAL_BLUR
set_optional_setting system system_material_stroke_enable "$MAT_STROKE" MATERIAL_STROKE
set_optional_setting system animationBlurrySwitch 1 MATERIAL_BLUR

# 全局动画时长保持 1.0，避免“关闭动画”把动效吃掉；这三项所有 ColorOS 16/17 都存在
set_setting global animator_duration_scale 1.0
set_setting global transition_animation_scale 1.0
set_setting global window_animation_scale 1.0
set_setting global media_fluid_disable_anim 0

# 分辨率：不写任何档位，交给系统/物理面板决定

# AOD / 锁屏 / 壁纸 / 质感视效
set_optional_setting secure full_screen_aod "$FULL_AOD" FULL_AOD
set_optional_setting secure is_desktop_wallpaper_blur_enable "$DESKTOP_BLUR" DESKTOP_BLUR
set_optional_setting secure oplus_keyguard_charge_anim_show "$AOD_CHARGE" AOD_CHARGE
set_optional_setting secure oplus_keyguard_workshop_aod_support "$AOD_WORKSHOP" AOD_WORKSHOP
# 不写 oplus_customize_color_ink_enable：它会让护眼模式里的阅读模式自动打开

# 侧滑跟手 / 磁贴动画：不同机型键名不同，有哪个写哪个
set_optional_setting secure follow_hand "$FOLLOW_HAND" FOLLOW_HAND
set_optional_setting secure oplus_page_slide_with_gesture "$FOLLOW_HAND" FOLLOW_HAND
set_optional_setting secure oplus_page_slide_against_gesture "$FOLLOW_HAND" FOLLOW_HAND
set_optional_setting secure oplus_tile_icon_animation_speed 1 FOLLOW_HAND

# 游戏显示增强
set_optional_setting secure display_memc_game_enable "$GAME_MEMC" GAME_MEMC
set_optional_setting system game_color_enhance "$GAME_COLOR" GAME_COLOR

# HDR10+ adaptive：只有当前系统已有 PQ 开关时才写
set_optional_pq persist.vendor.sys.pq.hdr10p_adaptive.en "$HDR10P" HDR10P

# ---------- 可选开关：默认关闭，由 config.conf 控制 ----------
AOD_ALL_DAY=$(cfg_get ENABLE_ALL_DAY_AOD); [ -z "$AOD_ALL_DAY" ] && AOD_ALL_DAY=0
HDR10_ADAPTIVE=$(cfg_get ENABLE_HDR10_ADAPTIVE); [ -z "$HDR10_ADAPTIVE" ] && HDR10_ADAPTIVE=0
HDRVIVID_ADAPTIVE=$(cfg_get ENABLE_HDRVIVID_ADAPTIVE); [ -z "$HDRVIVID_ADAPTIVE" ] && HDRVIVID_ADAPTIVE=0
ULTRA_RESOLUTION=$(cfg_get ENABLE_ULTRA_RESOLUTION); [ -z "$ULTRA_RESOLUTION" ] && ULTRA_RESOLUTION=0
MML_COLOR=$(cfg_get ENABLE_MML_COLOR_ADAPTIVE); [ -z "$MML_COLOR" ] && MML_COLOR=0
AI_SDR=$(cfg_get ENABLE_AI_SDR_ADAPTIVE); [ -z "$AI_SDR" ] && AI_SDR=0

# 兼容模式只应用 ColorOS 16/17 的稳定项；实验项强制回 0，避免旧机型/低配机被未知 PQ 键拖累。
if [ "$ADAPT_EFFECTIVE" = "full" ]; then
  EXP_OK=1
else
  EXP_OK=0
  AOD_ALL_DAY=0
  HDR10_ADAPTIVE=0
  HDRVIVID_ADAPTIVE=0
  ULTRA_RESOLUTION=0
  MML_COLOR=0
  AI_SDR=0
fi

# 全天全景 AOD：ColorOS 官方默认关闭，打开后可能增加耗电/烧屏风险
set_optional_setting secure oplus_keyguard_panoramic_aod_all_day_support "$AOD_ALL_DAY" ALL_DAY_AOD

# HDR10 adaptive / HDR Vivid / 视频超分 / MML / AI SDR→HDR：只写系统已有的 PQ 开关
set_optional_pq persist.vendor.sys.pq.hdr10_adaptive.en "$HDR10_ADAPTIVE" HDR10
set_optional_pq persist.vendor.sys.pq.hdrvivid_adaptive.en "$HDRVIVID_ADAPTIVE" HDRVIVID
set_optional_pq persist.vendor.sys.pq.ultrares.en "$ULTRA_RESOLUTION" ULTRA_RES
set_optional_pq persist.vendor.sys.pq.ultrares.strength "$ULTRA_RESOLUTION" ULTRA_RES
set_optional_pq persist.vendor.sys.pq.mdp.color.adaptive.en "$MML_COLOR" MML_COLOR
set_optional_pq persist.vendor.sys.pq.sdr_adaptive.en "$AI_SDR" AI_SDR

log "---"
log "适配模式：$ADAPT_MODE → $ADAPT_EFFECTIVE（ColorOS $ROM_MAJOR）"
log "高级设置完成：AOD/桌面模糊/材质模糊/游戏与 HDR 仅按当前机型支持的键执行"
log "实验项：兼容模式强制关闭；全量模式只写系统已有 PQ 键"
log "未声明支持的项不会创建假键，UI 会显示为不可用。"

