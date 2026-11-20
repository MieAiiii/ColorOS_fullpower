#!/system/bin/sh
# ============================================================
#  ColorOS 满血特性 6.0 —— 开机注入
#  作者：三重 / 酷安@MieAi
#
#  核心层（动画/模糊）在 system.prop，本脚本不重复。
#  本脚本做四件事：
#    1) 按 config.conf 补齐机型缺失的功能属性
#    2) 晕动舒缓显示：把 motion_sickness 特性声明 bind mount 进系统
#    3) 系统温控：按开关覆盖 / 恢复策略层
#    4) 满血快充：探测本机 /odm 表结构，生成并挂载自适应温度墙表
#
#  ro.* 是「写一次」语义：目标键不存在时 setprop 创建成功；
#  已存在且值不同时 setprop 会失败，此时说明系统已表过态，
#  不强行覆盖（覆盖需要 system.prop 的 resetprop 通道）。
# ============================================================

MODPATH=${0%/*}
LOG="$MODPATH/last_boot.log"
CFG="$MODPATH/config.conf"

ensure_key() {
  k=$1; v=$2
  [ -f "$CFG" ] || : > "$CFG" 2>/dev/null
  grep -q "^$k=" "$CFG" 2>/dev/null || echo "$k=$v" >> "$CFG" 2>/dev/null
}

# 老用户从 5.x 升级时补两个新键，不覆盖已有值。
ensure_key ENABLE_PEAK 1
ensure_key TEMP_WALL 0

# ---------------- 配置（默认值）----------------
ENABLE_CAMERA=1
ENABLE_AUDIO=1
ENABLE_RECORDER=1
ENABLE_LEGACY=0
ENABLE_ANTIDIZZY=1
ENABLE_SYSTHERMAL=0
ENABLE_PEAK=1
TEMP_WALL=0

if [ -f "$CFG" ]; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    k=$(echo "${line%%=*}" | tr -d ' ')
    v=$(echo "${line#*=}" | tr -d ' \r')
    case "$k" in
      ENABLE_CAMERA)    ENABLE_CAMERA=$v ;;
      ENABLE_AUDIO)     ENABLE_AUDIO=$v ;;
      ENABLE_RECORDER)  ENABLE_RECORDER=$v ;;
      ENABLE_LEGACY)    ENABLE_LEGACY=$v ;;
      ENABLE_ANTIDIZZY) ENABLE_ANTIDIZZY=$v ;;
      ENABLE_SYSTHERMAL) ENABLE_SYSTHERMAL=$v ;;
      ENABLE_PEAK)      ENABLE_PEAK=$v ;;
      TEMP_WALL)        TEMP_WALL=$v ;;
    esac
  done < "$CFG"
fi

# ---------------- 环境探测 ----------------
ROMRAW=$(getprop ro.build.version.oplusrom)
ROM_MAJ=$(echo "$ROMRAW" | sed -n 's/^[Vv]\([0-9][0-9]*\).*/\1/p')
[ -z "$ROM_MAJ" ] && ROM_MAJ=$(getprop ro.build.version.release | cut -d. -f1)
case "$ROM_MAJ" in ''|*[!0-9]*) ROM_MAJ=0 ;; esac

MODEL=$(getprop ro.product.marketname)
[ -z "$MODEL" ] && MODEL=$(getprop ro.vendor.oplus.market.name)
[ -z "$MODEL" ] && MODEL=$(getprop ro.product.model)

VRR=$(getprop persist.oplus.display.vrr)

# ---------------- 写入器 ----------------
OK=0; SKIP=0; FAIL=0

apply() {
  k=$1; v=$2
  cur=$(getprop "$k")
  if [ "$cur" = "$v" ]; then
    SKIP=$((SKIP + 1)); return
  fi
  setprop "$k" "$v" 2>/dev/null
  now=$(getprop "$k")
  if [ "$now" = "$v" ]; then
    echo "  SET   $k = $v"; OK=$((OK + 1))
  else
    echo "  FAIL  $k  want=[$v]  got=[$now]"; FAIL=$((FAIL + 1))
  fi
}

# ---------------- 功能层 ----------------
{
  echo "=== ColorOS 满血特性 6.0  $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo "机型: ${MODEL:-未知}"
  echo "ColorOS: ${ROMRAW:-未知}  (主版本 ${ROM_MAJ})"
  echo "高刷标志 persist.oplus.display.vrr = [${VRR:-空}]"

  # ---- 系统级温控（默认关，WebUI 可开）----
  # 原理与边界见 bin/tempctl.sh 头注释。
  if [ "$ENABLE_SYSTHERMAL" = "1" ]; then
    echo "系统温控: 禁用中…"
    sh "$MODPATH/bin/tempctl.sh" on
  else
    # 用户关了开关：不论上次有没有留下 state，都必须 restore_services。
    # 旧逻辑只在 sys_thermal_state.txt 非空时 off；如果上次 off 已清空 state，
    # 开机就没人把 horae 拉回来，表现为“开关关了但温控还是 stopped”。
    sh "$MODPATH/bin/tempctl.sh" off >/dev/null 2>&1
    echo "系统温控: 按配置保持关闭，已恢复原厂策略"
  fi

  echo "分支: 相机=$ENABLE_CAMERA 音频=$ENABLE_AUDIO 录屏=$ENABLE_RECORDER 旧版=$ENABLE_LEGACY 晕动=$ENABLE_ANTIDIZZY 系统温控=$ENABLE_SYSTHERMAL 快充=$ENABLE_PEAK 温度墙=$TEMP_WALL"
  echo "---"

  if [ "$ENABLE_CAMERA" = "1" ]; then
    apply ro.oplus.camera.livephoto.support 1
    apply ro.oplus.camera.quickshare.support 1
    apply ro.oplus.camera.defercap.support 1
    apply ro.oplus.camera.defercap.all.quick.visible.support 1
    apply ro.oplus.camera.isSupportLumo 1
  fi

  if [ "$ENABLE_AUDIO" = "1" ]; then
    apply ro.oplus.audio.speaker_clean true
  fi

  if [ "$ENABLE_RECORDER" = "1" ]; then
    if [ "$VRR" = "1" ]; then
      apply ro.media.recorder-max-base-layer-fps 120
    else
      echo "  SKIP  录屏 120 帧（未检测到高刷标志）"; SKIP=$((SKIP + 1))
    fi
  fi

  if [ "$ENABLE_LEGACY" = "1" ]; then
    echo "  [实验] 旧版模糊键分支已启用"
    apply ro.oplus.gaussianlevel 3
    apply persist.sys.oplus.material_blur_switch true
    apply ro.launcher.blur.appLaunch 1
    apply ro.oplus.panoramic_aod_support 1
    apply ro.oplus.panoramic_aod_new_style true
  fi

  echo "---"
  echo "结果: 写入 $OK / 跳过 $SKIP / 失败 $FAIL"
  echo "FAIL 通常表示系统已自带该键且值不同，属正常（不强行覆盖）"
} > "$LOG" 2>&1

# 日志上限保护
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 32768 ]; then
  head -c 32768 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi


# ============================================================
#  晕动舒缓显示 —— 特性声明注入
#  来源：oplus-antidizzy-module v7.5（原样保留，仅加开关判断）
#  不同机型/版本把特性声明放在不同文件里，逐个探测，谁存在就补谁。
# ============================================================
if [ "$ENABLE_ANTIDIZZY" = "1" ]; then
  LOG2=/data/local/tmp/motion_cues_port.log
  : > "$LOG2"
  FEATURE=oplus.hardware.display.motion_sickness

  CANDS="/system_ext/etc/permissions/com.oplus.features_config.xml
/system_ext/etc/permissions/com.oplus.features_ext.xml
/system_ext/etc/permissions/com.oplus.features.xml
/my_product/etc/permissions/com.oplus.features_config.xml
/my_product/etc/permissions/com.oplus.features_ext.xml
/my_product/etc/permissions/com.oplus.features.xml
/my_product/etc/extension/com.oplus.oplus-feature.xml
/system_ext/etc/extension/com.oplus.oplus-feature.xml
/product/etc/extension/com.oplus.oplus-feature.xml
/odm/etc/permissions/com.oplus.features_config.xml
/odm/etc/permissions/com.oplus.features_ext.xml
/odm/etc/permissions/com.oplus.features.xml
/odm/etc/extension/com.oplus.oplus-feature.xml
/vendor/etc/permissions/com.oplus.features_config.xml
/vendor/etc/permissions/com.oplus.features_ext.xml
/vendor/etc/permissions/com.oplus.features.xml
/vendor/etc/extension/com.oplus.oplus-feature.xml"

  rm -f /data/local/tmp/mc_feat_*.xml 2>/dev/null

  i=0
  found=0
  for TGT in $CANDS; do
    [ -f "$TGT" ] || continue
    found=$((found+1))
    if grep -q "$FEATURE" "$TGT" 2>/dev/null; then
      echo "already: $TGT" >> "$LOG2"
      continue
    fi
    i=$((i+1))
    TMP=/data/local/tmp/mc_feat_$i.xml
    awk -v feat="$FEATURE" '
      /<\/oplus-config>/ { printf "\t<oplus-feature name=\"%s\"/>\n", feat }
      { print }
    ' "$TGT" > "$TMP" 2>/dev/null
    if ! grep -q "$FEATURE" "$TMP" 2>/dev/null; then
      awk -v feat="$FEATURE" '{ lines[NR]=$0 } END {
        for (n=1; n<=NR; n++) {
          if (n==NR && lines[n] ~ /^[[:space:]]*$/) continue
          if (n==NR) printf "\t<oplus-feature name=\"%s\"/>\n", feat
          print lines[n]
        }
      }' "$TGT" > "$TMP" 2>/dev/null
    fi
    if ! grep -q "$FEATURE" "$TMP" 2>/dev/null; then
      echo "inject-failed: $TGT" >> "$LOG2"
      rm -f "$TMP"
      continue
    fi
    # Toybox 的 chmod/chown/chcon 没有 --reference；必须显式取目标上下文。
    ctx=$(ls -Z "$TGT" 2>/dev/null | awk '{print $1}')
    case "$ctx" in
      u:object_r:*) ;;
      *) case "$TGT" in
           /odm/*|/vendor/*) ctx=u:object_r:vendor_configs_file:s0 ;;
           *) ctx=u:object_r:system_file:s0 ;;
         esac ;;
    esac
    chcon "$ctx" "$TMP" 2>/dev/null || echo "chcon-failed: $TGT" >> "$LOG2"
    chmod 644 "$TMP" 2>/dev/null
    chown 0:0 "$TMP" 2>/dev/null
    if mount --bind "$TMP" "$TGT"; then
      echo "patched: $TGT" >> "$LOG2"
    else
      echo "mount-failed: $TGT" >> "$LOG2"
    fi
  done

  [ "$found" = "0" ] && echo "no candidate config found (unsupported rom?)" >> "$LOG2"
  echo "model=$(getprop ro.product.name) rom=$(getprop ro.build.version.oplusrom) done" >> "$LOG2"
fi


# ============================================================
#  满血快充 —— 自适应温控表叠加
#
#  不写死机型、项目号、峰值电流或温度墙。流程：
#    tempwall.sh prepare 探测 /odm/firmware/fastchg 的
#    PROJECT、协议段、最大电流和 gear 阶梯 → 生成 stage 表
#    → 读 profile.env → 按实际路径 bind mount。
#
#  真实 /odm 分区不写入；只挂载 /data/adb/coloros_fullpower/stage。
# ============================================================
LOG3=/data/adb/coloros_fullpower/log/fastchg.log
mkdir -p "$(dirname "$LOG3")" 2>/dev/null

if [ "$ENABLE_PEAK" = "1" ]; then
  sh "$MODPATH/bin/tempwall.sh" prepare >> "$LOG3" 2>&1
  P=/data/adb/coloros_fullpower/profile.env

  if [ -f "$P" ]; then
    . "$P"
    echo "$(date '+%F %T') fastchg: supported=$SUPPORTED project=$PROJECT max=${MAX_CURRENT}mA sections=$SECTIONS wall=$WALL auto=$AUTO" >> "$LOG3"

    if [ "$SUPPORTED" = "1" ]; then
      # 顺序关键：先改 SELinux 标签再挂载，否则 HAL 域读不到。
      if chcon -R u:object_r:vendor_configs_file:s0 "$STAGE_ROOT" 2>>"$LOG3"; then
        echo "$(date '+%F %T') chcon ok: $STAGE_ROOT" >> "$LOG3"
      else
        echo "$(date '+%F %T') chcon FAILED: $STAGE_ROOT" >> "$LOG3"
      fi

      if [ "$HAS_DEFAULT" = "1" ] && [ -f "$DEFAULT_SRC" ] && [ -f "$DEFAULT_TGT" ]; then
        if mount -o bind "$DEFAULT_SRC" "$DEFAULT_TGT" 2>>"$LOG3"; then
          echo "$(date '+%F %T') mount default ok: $DEFAULT_TGT" >> "$LOG3"
          echo "$(date '+%F %T')   src=$(wc -c < "$DEFAULT_SRC") dst=$(wc -c < "$DEFAULT_TGT")" >> "$LOG3"
        else
          echo "$(date '+%F %T') mount default FAIL: $DEFAULT_TGT" >> "$LOG3"
        fi
      fi

      if [ "$HAS_FOLD" = "1" ] && [ -f "$FOLD_SRC" ] && [ -f "$FOLD_TGT" ]; then
        if mount -o bind "$FOLD_SRC" "$FOLD_TGT" 2>>"$LOG3"; then
          echo "$(date '+%F %T') mount fold ok: $FOLD_TGT" >> "$LOG3"
        else
          echo "$(date '+%F %T') mount fold FAIL: $FOLD_TGT" >> "$LOG3"
        fi
      fi

      if [ "$HAS_DIR" = "1" ] && [ -d "$DIR_SRC" ] && [ -d "$DIR_TGT" ]; then
        if mount -o bind "$DIR_SRC" "$DIR_TGT" 2>>"$LOG3"; then
          echo "$(date '+%F %T') mount dir ok: $DIR_TGT (project=$PROJECT)" >> "$LOG3"
          echo "$(date '+%F %T')   src_files=$(ls "$DIR_SRC" 2>/dev/null | wc -l) dst_files=$(ls "$DIR_TGT" 2>/dev/null | wc -l)" >> "$LOG3"
        else
          echo "$(date '+%F %T') mount dir FAIL: $DIR_TGT" >> "$LOG3"
        fi
      fi
    else
      echo "$(date '+%F %T') fastchg: unsupported table format or no table, skip overlay" >> "$LOG3"
    fi
  else
    echo "$(date '+%F %T') fastchg: profile.env missing, skip overlay" >> "$LOG3"
  fi
else
  echo "$(date '+%F %T') fastchg: ENABLE_PEAK=0, skip overlay" >> "$LOG3"
fi

# 留痕：只记录本模块叠加物的指纹与恢复路径。
# 不复制"上一层"的文件——上游模块启动时会重写自己的表，复制到的内容不可信。
md5_of() { [ -f "$1" ] && md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
MAN=/data/adb/screenoff_fix/backup/manifest.txt
if [ ! -f "$MAN" ]; then
  mkdir -p /data/adb/screenoff_fix/backup 2>/dev/null
  {
    echo "module=coloros_fullpower"
    echo "captured_at=$(date '+%F %T')"
    echo "real_odm_written=no"
    echo "fastchg_supported=${SUPPORTED:-0}"
    echo "fastchg_project=${PROJECT:-?}"
    echo "fastchg_max_current=${MAX_CURRENT:-0}"
    echo "fastchg_active_section=${ACTIVE_SECTION:-}"
    echo "fastchg_sections=${SECTIONS:-}"
    echo "fastchg_wall=${WALL:-0}"
    echo "fastchg_auto=${AUTO:-1}"
    echo "fastchg_default_name=${DEFAULT_NAME:-}"
    echo "fastchg_primary_hyper=${PRIMARY_HYPER:-}"
    echo "overlay_default_md5=$(md5_of "$DEFAULT_SRC")"
    echo "overlay_silicon_md5=$(md5_of "$SILICON_SRC")"
    echo "overlay_hyper_md5=$(md5_of "$HYPER_SRC")"
    echo "original_default_md5=$(md5_of "$ORIG/default/$DEFAULT_NAME")"
    echo "original_hyper_md5=$(md5_of "$ORIG/proj/$PROJECT/$PRIMARY_HYPER")"
    echo "restore=卸载模块+重启；真实 /odm 从未写入，原厂文件始终在分区上"
    echo "note=上一层模块的表由该模块自身在启动时覆盖，无法逐字备份"
  } > "$MAN"
  echo "$(date '+%F %T') manifest -> $MAN" >> "$LOG3"
fi
