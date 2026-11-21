#!/system/bin/sh
# ============================================================
#  ColorOS特性补全 10.0 —— 开机注入
#  作者：三重 / 酷安@MieAi
#
#  仅做两件事：
#    1) 按 config.conf 补可选旧版模糊键（动画/模糊核心在 system.prop）
#    2) 晕动舒缓显示：把 motion_sickness 特性声明 bind mount 进系统
#
#  没有 fastchg、没有 peak、没有 tempctl、没有 thermal。
#  没有常驻进程；本脚本执行完即退出。
# ============================================================

MODPATH=${0%/*}
LOG="$MODPATH/last_boot.log"
CFG="$MODPATH/config.conf"

# ---------------- 配置（默认值）----------------
ENABLE_LEGACY=0
ENABLE_ANTIDIZZY=1

if [ -f "$CFG" ]; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    k=$(echo "${line%%=*}" | tr -d ' ')
    v=$(echo "${line#*=}" | tr -d ' \r')
    case "$k" in
      ENABLE_LEGACY)    ENABLE_LEGACY=$v ;;
      ENABLE_ANTIDIZZY) ENABLE_ANTIDIZZY=$v ;;
    esac
  done < "$CFG"
fi

# ---------------- 环境信息 ----------------
ROMRAW=$(getprop ro.build.version.oplusrom)
MODEL=$(getprop ro.product.marketname)
[ -z "$MODEL" ] && MODEL=$(getprop ro.vendor.oplus.market.name)
[ -z "$MODEL" ] && MODEL=$(getprop ro.product.model)

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

{
  echo "=== ColorOS特性补全 10.0  $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo "机型: ${MODEL:-未知}"
  echo "ColorOS: ${ROMRAW:-未知}"
  echo "分支: 旧版模糊=$ENABLE_LEGACY 晕动=$ENABLE_ANTIDIZZY"
  echo "---"

  if [ "$ENABLE_LEGACY" = "1" ]; then
    echo "  [可选] 旧版模糊键已启用"
    apply ro.oplus.gaussianlevel 3
    apply persist.sys.oplus.material_blur_switch true
    apply ro.launcher.blur.appLaunch 1
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
    # 两种根节点：<oplus-config> 用 <oplus-feature>；
    # 标准 <permissions> 用 <feature>。必须在对应闭合标签前插入，
    # 否则 XML 非法，PackageManager 会直接忽略整个文件。
    awk -v feat="$FEATURE" '
      /<\/oplus-config>/ { printf "\t<oplus-feature name=\"%s\"/>\n", feat }
      /<\/permissions>/ { printf "\t<feature name=\"%s\"/>\n", feat }
      { print }
    ' "$TGT" > "$TMP" 2>/dev/null
    if ! grep -q "$FEATURE" "$TMP" 2>/dev/null; then
      echo "inject-failed: $TGT (no closing tag)" >> "$LOG2"
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
