#!/system/bin/sh
# ============================================================
#  ColorOS特性补全 10.0 —— 高级显示 / 模糊 / AOD / 游戏增强
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
LOG=/data/local/tmp/coloros_advanced.log
DATA=/data/adb/coloros_fullpower
BAK="$DATA/backup/settings_backup.txt"

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

# 动画/模糊：确保系统材质与模糊开关处于开启状态
set_setting system system_material_blur_enable "$MAT_BLUR"
set_setting system system_material_stroke_enable "$MAT_STROKE"
set_setting system animationBlurrySwitch 1

# 全局动画时长保持 1.0，避免“关闭动画”把动效吃掉
set_setting global animator_duration_scale 1.0
set_setting global transition_animation_scale 1.0
set_setting global window_animation_scale 1.0
set_setting global media_fluid_disable_anim 0

# 分辨率：不写任何档位，交给系统/物理面板决定

# AOD / 锁屏 / 壁纸 / 质感视效
set_setting secure full_screen_aod "$FULL_AOD"
set_setting secure is_desktop_wallpaper_blur_enable "$DESKTOP_BLUR"
set_setting secure oplus_keyguard_charge_anim_show "$AOD_CHARGE"
set_setting secure oplus_keyguard_workshop_aod_support "$AOD_WORKSHOP"
# 不写 oplus_customize_color_ink_enable：它会让护眼模式里的阅读模式自动打开

# 侧滑跟手 / 磁贴动画：Settings 里存在候选键，写入后由对应组件读取
set_setting secure follow_hand "$FOLLOW_HAND"
set_setting secure oplus_page_slide_with_gesture "$FOLLOW_HAND"
set_setting secure oplus_page_slide_against_gesture "$FOLLOW_HAND"
set_setting secure oplus_tile_icon_animation_speed 1

# 游戏显示增强
set_setting secure display_memc_game_enable "$GAME_MEMC"
set_setting system game_color_enhance "$GAME_COLOR"

# HDR10+ adaptive：硬件支持，默认开；WebUI 可关
set_pq persist.vendor.sys.pq.hdr10p_adaptive.en "$HDR10P"

# ---------- 可选开关：默认关闭，由 config.conf 控制 ----------
AOD_ALL_DAY=$(cfg_get ENABLE_ALL_DAY_AOD); [ -z "$AOD_ALL_DAY" ] && AOD_ALL_DAY=0
HDR10_ADAPTIVE=$(cfg_get ENABLE_HDR10_ADAPTIVE); [ -z "$HDR10_ADAPTIVE" ] && HDR10_ADAPTIVE=0
HDRVIVID_ADAPTIVE=$(cfg_get ENABLE_HDRVIVID_ADAPTIVE); [ -z "$HDRVIVID_ADAPTIVE" ] && HDRVIVID_ADAPTIVE=0
ULTRA_RESOLUTION=$(cfg_get ENABLE_ULTRA_RESOLUTION); [ -z "$ULTRA_RESOLUTION" ] && ULTRA_RESOLUTION=0
MML_COLOR=$(cfg_get ENABLE_MML_COLOR_ADAPTIVE); [ -z "$MML_COLOR" ] && MML_COLOR=0
AI_SDR=$(cfg_get ENABLE_AI_SDR_ADAPTIVE); [ -z "$AI_SDR" ] && AI_SDR=0

# 全天全景 AOD：ColorOS 官方默认关闭，打开后可能增加耗电/烧屏风险
set_setting secure oplus_keyguard_panoramic_aod_all_day_support "$AOD_ALL_DAY"

# HDR10 adaptive：硬件支持标记为 0，打开不一定生效
set_pq persist.vendor.sys.pq.hdr10_adaptive.en "$HDR10_ADAPTIVE"

# HDR Vivid adaptive：硬件支持标记为 0，打开不一定生效
set_pq persist.vendor.sys.pq.hdrvivid_adaptive.en "$HDRVIVID_ADAPTIVE"

# 视频超分：硬件超分支持标记为 0；只写 vendor 已有的 ultrares 开关
set_pq persist.vendor.sys.pq.ultrares.en "$ULTRA_RESOLUTION"
set_pq persist.vendor.sys.pq.ultrares.strength "$ULTRA_RESOLUTION"

# MML 色彩自适应：硬件支持标记为 0，打开不一定生效
set_pq persist.vendor.sys.pq.mdp.color.adaptive.en "$MML_COLOR"

# AI SDR→HDR：系统没有独立持久键，只能写已有的 SDR adaptive 开关作为可试入口
set_pq persist.vendor.sys.pq.sdr_adaptive.en "$AI_SDR"

log "---"
log "高级设置完成：AOD/桌面模糊/材质模糊/游戏与 HDR 按 WebUI 开关执行"
log "实验项：全天全景 AOD / HDR10 / HDR Vivid / 视频超分 / MML 色彩 / AI SDR→HDR"
log "只写当前系统存在的 Settings/PQ 键；没有持久键的项不会创建假开关。"
