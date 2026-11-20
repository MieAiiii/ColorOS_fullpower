#!/system/bin/sh
# ============================================================
#  满血快充 · 自适应温度墙控制器（v6.0）
#  作者：三重 / 酷安@MieAi
#
#  这个脚本不内置具体机型、项目号、峰值电流或温度墙数值。
#  每次开机在 post-fs-data 阶段：
#    1) 扫描 /odm、/odm/etc、/vendor、/vendor/etc、/my_odm、
#       /my_product、/product、/system_ext 下的 fastchg 固件目录
#    2) 从原厂表读取 PROJECT、协议段、最大电流、gear 阶梯
#    3) 用 tablegen.awk 按“本机最大电流”生成温度墙表
#    4) 把原始表副本和生成表放在 /data/adb/coloros_fullpower
#    5) 输出 profile.env，由 post-fs-data 按实际路径 bind mount
#
#  set/auto/restore 只改生成目录里的文件本身（原地写），
#  不使用 mv 替换 inode，因此不会出现 //deleted 回声挂载。
#
#  用法：
#    tempwall.sh prepare                 开机探测 + 生成（不挂载）
#    tempwall.sh get                     KV 状态，供 WebUI / status.sh
#    tempwall.sh set <440-WALL_MAX>      应用温度墙（0.1℃）
#    tempwall.sh auto                    恢复按机型自动选墙
#    tempwall.sh restore                 把叠加表恢复为首次读到的原始表
#    tempwall.sh detect                  只探测并打印 profile（调试）
# ============================================================

MODDIR=$(dirname "$0")/..
MODDIR=$(cd "$MODDIR" && pwd)
CFG="$MODDIR/config.conf"
DATA=/data/adb/coloros_fullpower
ORIG="$DATA/orig"
STAGE="$DATA/stage"
PROFILE="$DATA/profile.env"
LOGF="$DATA/log/fastchg.log"

log() { mkdir -p "$DATA/log" 2>/dev/null; echo "$(date '+%F %T') $*" >> "$LOGF" 2>/dev/null; }

config_get() {
  [ -f "$CFG" ] || return 0
  awk -F= -v k="$1" '$1==k {v=$2} END {print v}' "$CFG" 2>/dev/null | tr -d ' \r'
}

config_set() {
  k=$1; v=$2
  [ -f "$CFG" ] || : > "$CFG"
  if grep -q "^$k=" "$CFG" 2>/dev/null; then
    sed -i "s/^$k=.*/$k=$v/" "$CFG" 2>/dev/null
  else
    echo "$k=$v" >> "$CFG"
  fi
  [ "$(config_get "$k")" = "$v" ]
}

# ---------------- 表结构解析 ----------------
# 输出 PROJECT / SECTIONS / MAX_CURRENT / ACTIVE_SECTION / FORMAT
table_meta() {
  awk -F, '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    { sub(/\r$/, "") }
    /^[ \t]*[Pp][Rr][Oo][Jj][Ee][Cc][Tt]:=/ {
      p = $0
      sub(/^[ \t]*[Pp][Rr][Oo][Jj][Ee][Cc][Tt]:=/, "", p)
      sub(/[ \r].*/, "", p)
      project = trim(p)
    }
    /^[ \t]*[A-Za-z0-9_-]+_[Tt][Hh][Ee][Rr][Mm][Aa][Ll]_[Cc][Oo][Nn][Tt][Rr][Oo][Ll]_[Ss][Tt][Aa][Rr][Tt][ \t]*$/ {
      name = trim($0)
      sub(/_[Tt][Hh][Ee][Rr][Mm][Aa][Ll]_[Cc][Oo][Nn][Tt][Rr][Oo][Ll]_[Ss][Tt][Aa][Rr][Tt].*/, "", name)
      sections = (sections == "" ? name : sections "," name)
      insec = 1
      smax = 0
      stemp = 0
      lastname = name
      next
    }
    /^[ \t]*[A-Za-z0-9_-]+_[Tt][Hh][Ee][Rr][Mm][Aa][Ll]_[Cc][Oo][Nn][Tt][Rr][Oo][Ll]_[Ee][Nn][Dd][ \t]*$/ {
      if (smax > max) { max = smax; active = lastname; maxtemp = stemp }
      insec = 0
      next
    }
    insec && /^[ \t]*[0-9]+[ \t]*,[ \t]*[0-9]+/ {
      t = $1 + 0
      if (t > maxtable) maxtable = t
      if (($2 + 0) > smax) { smax = $2 + 0; stemp = t }
      else if (($2 + 0) == smax) { stemp = t }
      next
    }
    END {
      if (insec && smax > max) { max = smax; active = lastname; maxtemp = stemp }
      if (sections == "") fmt = "flat"
      else fmt = "protocol"
      printf "PROJECT=%s\nSECTIONS=%s\nMAX_CURRENT=%d\nMAX_TEMP=%d\nMAX_TABLE_TEMP=%d\nACTIVE_SECTION=%s\nFORMAT=%s\n", project, sections, max, maxtemp, maxtable, active, fmt
    }
  ' "$1" 2>/dev/null
}

meta_get() {
  printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1
}

# ---------------- 探测路径 ----------------
# ColorOS 16/17 不同机型可能把同一套表拆在 /odm、/odm/etc、/vendor、
# /vendor/etc、/my_odm、/my_product、/product、/system_ext 下，也可能
# default 与项目目录不在同一个根。这里保留全部候选根，后面分别找
# default / project，而不是“第一个存在的目录通吃”。
FASTCHG_ROOTS=${FASTCHG_ROOTS:-"/odm/firmware/fastchg /odm/etc/firmware/fastchg /vendor/firmware/fastchg /vendor/etc/firmware/fastchg /my_odm/firmware/fastchg /my_product/firmware/fastchg /product/firmware/fastchg /system_ext/firmware/fastchg"}

find_odm_roots() {
  ODM_ROOTS=""; ODM_ROOT=""
  for d in $FASTCHG_ROOTS; do
    [ -d "$d" ] || continue
    ODM_ROOTS="$ODM_ROOTS $d"
    [ -z "$ODM_ROOT" ] && ODM_ROOT=$d
  done
  [ -n "$ODM_ROOTS" ]
}

dir_has_tables() {
  for f in "$1"/*.txt; do
    [ -f "$f" ] || continue
    grep -qi '_thermal_control_start' "$f" 2>/dev/null && return 0
  done
  return 1
}

any_project_table() {
  for root in $ODM_ROOTS; do
    for d in "$root"/*; do
      [ -d "$d" ] || continue
      dir_has_tables "$d" && return 0
    done
  done
  return 1
}

find_default() {
  DEFAULT_TGT=""; DEFAULT_NAME=""; DEFAULT_ROOT=""
  for root in $ODM_ROOTS; do
    for f in "$root"/charging_thermal_config_default*.txt \
             "$root"/charging_thermal_config.txt \
             "$root"/*thermal*config*default*.txt \
             "$root"/*thermal*config*.txt \
             "$root"/*/*thermal*config*default*.txt; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in *fold*|*hyper*) continue ;; esac
      grep -qi '_thermal_control_start' "$f" 2>/dev/null || continue
      DEFAULT_TGT=$f; DEFAULT_NAME=$(basename "$f"); DEFAULT_ROOT=$root
      [ -z "$ODM_ROOT" ] && ODM_ROOT=$root
      return 0
    done
  done
  return 1
}

find_fold() {
  FOLD_TGT=""; FOLD_NAME=""; FOLD_ROOT=""
  for root in $ODM_ROOTS; do
    for f in "$root"/*fold*.txt "$root"/*/*fold*.txt; do
      [ -f "$f" ] || continue
      grep -qi '_thermal_control_start' "$f" 2>/dev/null || continue
      FOLD_TGT=$f; FOLD_NAME=$(basename "$f"); FOLD_ROOT=$root
      [ -z "$ODM_ROOT" ] && ODM_ROOT=$root
      return 0
    done
  done
  return 1
}

scan_project() {
  best_dir=""; best_root=""; best_max=0; best_hyper=0
  for root in $ODM_ROOTS; do
    for d in "$root"/*; do
      [ -d "$d" ] || continue
      has=0; dmax=0; dhyper=0
      for f in "$d"/*.txt; do
        [ -f "$f" ] || continue
        grep -qi '_thermal_control_start' "$f" 2>/dev/null || continue
        has=1
        m=$(meta_get "$(table_meta "$f")" MAX_CURRENT)
        case "$m" in ''|*[!0-9]*) m=0 ;; esac
        [ "$m" -gt "$dmax" ] 2>/dev/null && dmax=$m
        case "$(basename "$f")" in *hyper*) dhyper=1 ;; esac
      done
      [ "$has" = "1" ] || continue
      if [ "$dmax" -gt "$best_max" ] 2>/dev/null || \
         { [ "$dmax" -eq "$best_max" ] 2>/dev/null && [ "$dhyper" -gt "$best_hyper" ]; }; then
        best_max=$dmax; best_hyper=$dhyper; best_dir=$d; best_root=$root
      fi
    done
  done
  [ -n "$best_dir" ] || return 1
  DIR_TGT=$best_dir; PROJECT_ROOT=$best_root; PROJECT=$(basename "$best_dir")
}

find_project() {
  DIR_TGT=""; PROJECT_ROOT=""; DIR_MAX=0
  # 先信任 default 里声明的 PROJECT：只要该目录下确实有可识别的表，
  # 就不要再按“最大电流”跳到别的项目目录。
  if [ -n "$PROJECT" ] && [ "$PROJECT" != "?" ]; then
    for root in $ODM_ROOTS; do
      d="$root/$PROJECT"
      [ -d "$d" ] || continue
      if dir_has_tables "$d"; then
        DIR_TGT=$d; PROJECT_ROOT=$root
        break
      fi
    done
  fi
  [ -n "$DIR_TGT" ] || scan_project || return 0

  collect_hyper
  # 有些 ROM 的 PROJECT 目录只是固件目录（只有 .bin），真正带表的是另一个目录。
  if [ -z "$HYPER_LIST" ]; then
    oldproj=$PROJECT
    scan_project || return 0
    if [ "$PROJECT" != "$oldproj" ] && [ -n "$PROJECT" ] && [ -n "$DIR_TGT" ]; then
      collect_hyper
    fi
  fi
}

collect_hyper() {
  HYPER_LIST=""; PRIMARY_HYPER=""; PRIMARY_MAX=0; PRIMARY_IS_HYPER=0
  for f in "$DIR_TGT"/*.txt; do
    [ -f "$f" ] || continue
    grep -qi '_thermal_control_start' "$f" 2>/dev/null || continue
    base=$(basename "$f")
    m=$(meta_get "$(table_meta "$f")" MAX_CURRENT)
    case "$m" in ''|*[!0-9]*) m=0 ;; esac
    ish=0
    case "$base" in *hyper*) ish=1 ;; esac
    HYPER_LIST="$HYPER_LIST $base"
    if [ "$m" -gt "$PRIMARY_MAX" ] 2>/dev/null || \
       { [ "$m" -eq "$PRIMARY_MAX" ] 2>/dev/null && [ "$ish" -gt "$PRIMARY_IS_HYPER" ]; }; then
      PRIMARY_MAX=$m; PRIMARY_IS_HYPER=$ish; PRIMARY_HYPER=$base
    fi
  done
  DIR_MAX=$PRIMARY_MAX
}

file_md5() {
  [ -f "$1" ] && md5sum "$1" 2>/dev/null | awk '{print $1}'
}

dir_sig() {
  d=$1
  [ -n "$d" ] && [ -d "$d" ] || { echo ""; return; }
  {
    for f in "$d"/*; do
      [ -f "$f" ] || continue
      md5sum "$f" 2>/dev/null
    done
  } | md5sum 2>/dev/null | awk '{print $1}'
}

# ---------------- 原始表 / 生成目录 ----------------
# ORIG 不能只按 ROM 版本号缓存：同版本下换 fastchg 根、换项目目录、
# 或厂商热更新表，文件名可能相同但内容已经变了。用路径 + 内容签名判断。
capture_orig() {
  ROMVER=$(getprop ro.build.version.oplusrom 2>/dev/null)
  META="$ORIG/meta.env"
  DEF_SIG=$(file_md5 "$DEFAULT_TGT")
  DIR_SIG=$(dir_sig "$DIR_TGT")
  need=0
  if [ -f "$META" ]; then
    . "$META" 2>/dev/null
    [ "${SAVED_DEFAULT_PATH:-}" = "$DEFAULT_TGT" ] || need=1
    [ "${SAVED_DEFAULT_SIG:-}" = "$DEF_SIG" ] || need=1
    [ "${SAVED_DIR_PATH:-}" = "$DIR_TGT" ] || need=1
    [ "${SAVED_DIR_SIG:-}" = "$DIR_SIG" ] || need=1
    [ "${SAVED_ROM:-}" = "$ROMVER" ] || need=1
  else
    need=1
  fi
  if [ "$need" = "1" ]; then
    # ROM 升级 / 路径变化 / 表内容变化：旧 ORIG 不能继续当基准。
    rm -rf "$ORIG" 2>/dev/null
  fi
  mkdir -p "$ORIG/default" "$ORIG/fold" 2>/dev/null
  [ -n "$DEFAULT_TGT" ] && [ ! -f "$ORIG/default/$DEFAULT_NAME" ] && \
    cp -f "$DEFAULT_TGT" "$ORIG/default/$DEFAULT_NAME" 2>/dev/null
  [ -n "$FOLD_TGT" ] && [ ! -f "$ORIG/fold/$FOLD_NAME" ] && \
    cp -f "$FOLD_TGT" "$ORIG/fold/$FOLD_NAME" 2>/dev/null

  if [ -n "$DIR_TGT" ] && [ -d "$DIR_TGT" ]; then
    mkdir -p "$ORIG/proj/$PROJECT" 2>/dev/null
    for f in "$DIR_TGT"/*; do
      [ -f "$f" ] || continue
      base=$(basename "$f")
      [ -f "$ORIG/proj/$PROJECT/$base" ] || cp -f "$f" "$ORIG/proj/$PROJECT/$base" 2>/dev/null
    done
  fi
  {
    echo "SAVED_ROM=\"$ROMVER\""
    echo "SAVED_DEFAULT_PATH=\"$DEFAULT_TGT\""
    echo "SAVED_DEFAULT_SIG=\"$DEF_SIG\""
    echo "SAVED_DIR_PATH=\"$DIR_TGT\""
    echo "SAVED_DIR_SIG=\"$DIR_SIG\""
    echo "SAVED_PROJECT=\"$PROJECT\""
  } > "$META" 2>/dev/null
  echo "$ROMVER" > "$ORIG/rom_version" 2>/dev/null
}

stage_base() {
  # 每次开机重建 stage，保证目录 bind 能看到 ROM 当前的全部文件。
  rm -rf "$STAGE" 2>/dev/null
  mkdir -p "$STAGE/default" "$STAGE/fold" "$STAGE/proj/$PROJECT" 2>/dev/null

  if [ -n "$DEFAULT_TGT" ]; then
    cp -f "$DEFAULT_TGT" "$STAGE/default/$DEFAULT_NAME" 2>/dev/null || \
      cp -f "$ORIG/default/$DEFAULT_NAME" "$STAGE/default/$DEFAULT_NAME" 2>/dev/null
  fi
  if [ -n "$FOLD_TGT" ]; then
    cp -f "$FOLD_TGT" "$STAGE/fold/$FOLD_NAME" 2>/dev/null || \
      cp -f "$ORIG/fold/$FOLD_NAME" "$STAGE/fold/$FOLD_NAME" 2>/dev/null
  fi
  if [ -n "$DIR_TGT" ] && [ -d "$DIR_TGT" ]; then
    for f in "$DIR_TGT"/*; do
      [ -f "$f" ] || continue
      cp -f "$f" "$STAGE/proj/$PROJECT/$(basename "$f")" 2>/dev/null
    done
  fi
}

gen_table() {
  src=$1; dst=$2; wall=$3; tmax=$4
  [ -n "$tmax" ] || tmax=${TABLE_LADDER_MAX:-$WALL_MAX}
  [ -f "$src" ] || return 1
  rm -f "$dst.tmp" 2>/dev/null
  awk -f "$MODDIR/bin/tablegen.awk" -v wall="$wall" -v tmax="$tmax" "$src" > "$dst.tmp" 2>/dev/null
  [ -s "$dst.tmp" ] || { rm -f "$dst.tmp"; return 2; }
  grep -qi '_thermal_control_start' "$dst.tmp" 2>/dev/null || { rm -f "$dst.tmp"; return 3; }
  # 原地覆盖，不 mv：目标文件 inode 不变，bind 源不会变成 //deleted。
  cat "$dst.tmp" > "$dst" 2>/dev/null || { rm -f "$dst.tmp"; return 4; }
  rm -f "$dst.tmp" 2>/dev/null
  return 0
}

regen_all() {
  wall=$1
  rc=0

  if [ -n "$DEFAULT_NAME" ]; then
    src="$ORIG/default/$DEFAULT_NAME"
    [ -f "$src" ] || src="$DEFAULT_TGT"
    dst="$STAGE/default/$DEFAULT_NAME"
    if [ "$wall" = "0" ]; then
      cat "$src" > "$dst" 2>/dev/null || rc=1
    else
      gen_table "$src" "$dst" "$wall" || rc=1
    fi
  fi

  if [ -n "$FOLD_NAME" ]; then
    src="$ORIG/fold/$FOLD_NAME"
    [ -f "$src" ] || src="$FOLD_TGT"
    dst="$STAGE/fold/$FOLD_NAME"
    if [ "$wall" = "0" ]; then
      cat "$src" > "$dst" 2>/dev/null || rc=1
    else
      gen_table "$src" "$dst" "$wall" || rc=1
    fi
  fi

  for base in $HYPER_LIST; do
    src="$ORIG/proj/$PROJECT/$base"
    [ -f "$src" ] || src="$DIR_TGT/$base"
    dst="$STAGE/proj/$PROJECT/$base"
    if [ "$wall" = "0" ]; then
      cat "$src" > "$dst" 2>/dev/null || rc=1
    else
      gen_table "$src" "$dst" "$wall" || rc=1
    fi
  done

  # 兼容不同代 HAL 的路径名。原厂存在就用原厂内容；不存在则用主 hyper 表生成。
  for alias in silicon_single_charging_hyper_mode_config.txt \
               qcom_single_charging_hyper_mode_config.txt; do
    asrc="$ORIG/proj/$PROJECT/$alias"
    adst="$STAGE/proj/$PROJECT/$alias"
    if [ -f "$asrc" ]; then
      if [ "$wall" = "0" ]; then
        cat "$asrc" > "$adst" 2>/dev/null || rc=1
      else
        gen_table "$asrc" "$adst" "$wall" || rc=1
      fi
    elif [ "$wall" = "0" ]; then
      rm -f "$adst" 2>/dev/null
    else
      psrc="$STAGE/proj/$PROJECT/$PRIMARY_HYPER"
      [ -f "$psrc" ] && { cat "$psrc" > "$adst" 2>/dev/null || rc=1; }
    fi
  done

  # 生成目录里的文件必须可读；cat 新建的别名在 umask 000 下会是 666。
  find "$STAGE" -type f -exec chmod 644 {} \; 2>/dev/null
  return $rc
}

profile_write() {
  mkdir -p "$DATA" 2>/dev/null
  {
    echo "SUPPORTED=$SUPPORTED"
    echo "ENABLED=$ENABLED"
    echo "FORMAT=$FORMAT"
    echo "ODM_ROOT=$ODM_ROOT"
    echo "PROJECT=$PROJECT"
    echo "MAX_CURRENT=$MAX_CURRENT"
    echo "MAX_TEMP=$MAX_TEMP"
    echo "MAX_TABLE_TEMP=$MAX_TABLE_TEMP"
    echo "TABLE_LADDER_MAX=$TABLE_LADDER_MAX"
    echo "WALL_MAX=$WALL_MAX"
    echo "ACTIVE_SECTION=$ACTIVE_SECTION"
    printf 'SECTIONS="%s"\n' "$SECTIONS"
    printf 'ODM_ROOTS="%s"\n' "$ODM_ROOTS"
    echo "DEFAULT_ROOT=$DEFAULT_ROOT"
    echo "FOLD_ROOT=$FOLD_ROOT"
    echo "PROJECT_ROOT=$PROJECT_ROOT"
    echo "DEFAULT_WALL=$DEFAULT_WALL"
    echo "WALL=$WALL"
    echo "AUTO=$AUTO"
    echo "RESTORED=$RESTORED"
    echo "HAS_DEFAULT=$HAS_DEFAULT"
    echo "HAS_FOLD=$HAS_FOLD"
    echo "HAS_DIR=$HAS_DIR"
    echo "DEFAULT_NAME=$DEFAULT_NAME"
    echo "FOLD_NAME=$FOLD_NAME"
    printf 'HYPER_LIST="%s"\n' "$HYPER_LIST"
    echo "PRIMARY_HYPER=$PRIMARY_HYPER"
    echo "DEFAULT_TGT=$DEFAULT_TGT"
    echo "DEFAULT_SRC=$STAGE/default/$DEFAULT_NAME"
    echo "FOLD_TGT=$FOLD_TGT"
    echo "FOLD_SRC=$STAGE/fold/$FOLD_NAME"
    echo "DIR_TGT=$DIR_TGT"
    echo "DIR_SRC=$STAGE/proj/$PROJECT"
    echo "SILICON_TGT=$DIR_TGT/silicon_single_charging_hyper_mode_config.txt"
    echo "SILICON_SRC=$STAGE/proj/$PROJECT/silicon_single_charging_hyper_mode_config.txt"
    echo "HYPER_TGT=$DIR_TGT/$PRIMARY_HYPER"
    echo "HYPER_SRC=$STAGE/proj/$PROJECT/$PRIMARY_HYPER"
    echo "STAGE_ROOT=$STAGE"
    echo "ROM_VERSION=$(getprop ro.build.version.oplusrom 2>/dev/null)"
    echo "DETECTED_AT=$(date '+%Y-%m-%d %H:%M:%S')"
  } > "$PROFILE" 2>/dev/null
}

load_profile() {
  SUPPORTED=0; ENABLED=1; FORMAT=""; ODM_ROOT=""; PROJECT="?"
  ODM_ROOTS=""; DEFAULT_ROOT=""; FOLD_ROOT=""; PROJECT_ROOT=""
  MAX_CURRENT=0; MAX_TEMP=0; MAX_TABLE_TEMP=0; TABLE_LADDER_MAX=480; WALL_MAX=480; ACTIVE_SECTION=""; SECTIONS=""
  DEFAULT_WALL=440; WALL=0; AUTO=1; RESTORED=0
  HAS_DEFAULT=0; HAS_FOLD=0; HAS_DIR=0
  DEFAULT_NAME=""; FOLD_NAME=""; HYPER_LIST=""; PRIMARY_HYPER=""
  DEFAULT_TGT=""; DEFAULT_SRC=""; FOLD_TGT=""; FOLD_SRC=""
  DIR_TGT=""; DIR_SRC=""; SILICON_TGT=""; SILICON_SRC=""
  HYPER_TGT=""; HYPER_SRC=""; STAGE_ROOT=""
  [ -f "$PROFILE" ] && . "$PROFILE" 2>/dev/null
}

default_wall_for() {
  m=$1; t=$2; mt=${3:-0}
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  case "$t" in ''|*[!0-9]*) t=0 ;; esac
  case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
  # 表结构无法解析出峰值电流/温度时，用一个中性墙，不猜机型。
  if [ "$m" -eq 0 ] || [ "$t" -eq 0 ]; then echo 470; return; fi
  # 全局安全上限也来自本机表，而不是某个机型写死的高温值：
  # 允许比原厂表最高温度再高 11℃；表没有最高温度时才退回 480。
  if [ "$mt" -gt 0 ]; then
    wmax=$((mt + 110))
    [ "$wmax" -lt 440 ] && wmax=440
    [ "$wmax" -gt 580 ] && wmax=580
  else
    wmax=480
  fi
  # 基线 = 原厂表里“峰值电流最后出现的温度”（0.1℃）。
  # 峰值越高，允许把这段满流区往后抬得越多：5..21℃。
  boost=$((5 + (m - 3000) * 16 / 5000))
  [ "$boost" -lt 5 ] && boost=5
  [ "$boost" -gt 21 ] && boost=21
  wall=$((t + boost * 10))
  [ "$wall" -lt 440 ] && wall=440
  [ "$wall" -gt "$wmax" ] && wall=$wmax
  echo "$wall"
}

detect() {
  mkdir -p "$DATA/log" 2>/dev/null
  # detect 会重建 ORIG/stage；stage 已经被挂载时读到的是生成表，
  # 再拿它当原厂基准会把错误内容固化。开机 prepare 已在外面挡一次，
  # 这里再挡一次，防止 WebUI 或手动误调。
  if grep -q "coloros_fullpower/stage" /proc/self/mountinfo 2>/dev/null; then
    echo "err=stage_mounted"
    return 1
  fi
  ODM_ROOTS=""; ODM_ROOT=""; DEFAULT_ROOT=""; FOLD_ROOT=""; PROJECT_ROOT=""
  find_odm_roots || {
    SUPPORTED=0; FORMAT="no_odm"; PROJECT="?"; MAX_CURRENT=0
    MAX_TEMP=0; MAX_TABLE_TEMP=0; TABLE_LADDER_MAX=480; WALL_MAX=480
    DEFAULT_WALL=440; WALL=0; AUTO=1; RESTORED=0
    HAS_DEFAULT=0; HAS_FOLD=0; HAS_DIR=0
    ENABLED=$(config_get ENABLE_PEAK); [ -z "$ENABLED" ] && ENABLED=1
    profile_write
    log "detect: no fastchg firmware root; fastchg overlay skipped"
    return 1
  }

  find_default
  find_fold

  PROJECT="?"; SECTIONS=""; MAX_CURRENT=0; MAX_TEMP=0; MAX_TABLE_TEMP=0; TABLE_LADDER_MAX=480; ACTIVE_SECTION=""; FORMAT=""
  if [ -n "$DEFAULT_TGT" ]; then
    dm=$(table_meta "$DEFAULT_TGT")
    PROJECT=$(meta_get "$dm" PROJECT); [ -z "$PROJECT" ] && PROJECT="?"
    SECTIONS=$(meta_get "$dm" SECTIONS)
    MAX_CURRENT=$(meta_get "$dm" MAX_CURRENT)
    MAX_TEMP=$(meta_get "$dm" MAX_TEMP)
    MAX_TABLE_TEMP=$(meta_get "$dm" MAX_TABLE_TEMP)
    ACTIVE_SECTION=$(meta_get "$dm" ACTIVE_SECTION)
    FORMAT=$(meta_get "$dm" FORMAT)
  fi

  find_project

  if [ -n "$PRIMARY_HYPER" ]; then
    hm=$(table_meta "$DIR_TGT/$PRIMARY_HYPER")
    hs=$(meta_get "$hm" SECTIONS)
    hmc=$(meta_get "$hm" MAX_CURRENT)
    hmt=$(meta_get "$hm" MAX_TEMP)
    hmtb=$(meta_get "$hm" MAX_TABLE_TEMP)
    ha=$(meta_get "$hm" ACTIVE_SECTION)
    [ -n "$hs" ] && SECTIONS=$hs
    [ -n "$hmc" ] && MAX_CURRENT=$hmc
    [ -n "$hmt" ] && MAX_TEMP=$hmt
    [ -n "$hmtb" ] && MAX_TABLE_TEMP=$hmtb
    [ -n "$ha" ] && ACTIVE_SECTION=$ha
    FORMAT=protocol
  fi

  case "$MAX_CURRENT" in ''|*[!0-9]*) MAX_CURRENT=0 ;; esac
  case "$MAX_TEMP" in ''|*[!0-9]*) MAX_TEMP=0 ;; esac
  case "$MAX_TABLE_TEMP" in ''|*[!0-9]*) MAX_TABLE_TEMP=0 ;; esac
  if [ "$MAX_TABLE_TEMP" -gt 0 ]; then
    WALL_MAX=$((MAX_TABLE_TEMP + 110))
    [ "$WALL_MAX" -lt 440 ] && WALL_MAX=440
    [ "$WALL_MAX" -gt 580 ] && WALL_MAX=580
    # 低电流档的梯度上限也按本机表推导：原厂表最高温 +16℃，
    # 再夹到 440..580；25061（42.0℃）正好得到 580，不改变原有表现。
    TABLE_LADDER_MAX=$((MAX_TABLE_TEMP + 160))
    [ "$TABLE_LADDER_MAX" -lt 440 ] && TABLE_LADDER_MAX=440
    [ "$TABLE_LADDER_MAX" -gt 580 ] && TABLE_LADDER_MAX=580
  else
    WALL_MAX=480
    TABLE_LADDER_MAX=480
  fi
  [ -n "$DEFAULT_TGT" ] && HAS_DEFAULT=1 || HAS_DEFAULT=0
  [ -n "$FOLD_TGT" ] && HAS_FOLD=1 || HAS_FOLD=0
  if [ -n "$DIR_TGT" ] && [ -n "$PRIMARY_HYPER" ]; then HAS_DIR=1; else HAS_DIR=0; fi
  [ -z "$ODM_ROOT" ] && ODM_ROOT=${DEFAULT_ROOT:-$PROJECT_ROOT}

  if [ "$HAS_DEFAULT" = "0" ] && [ "$HAS_DIR" = "0" ]; then
    SUPPORTED=0
  elif [ "$FORMAT" = "flat" ] && [ -z "$PRIMARY_HYPER" ]; then
    # 没有协议段标记的表不硬改，避免在未知表结构上误写。
    SUPPORTED=0
  else
    SUPPORTED=1
  fi

  DEFAULT_WALL=$(default_wall_for "$MAX_CURRENT" "$MAX_TEMP" "$MAX_TABLE_TEMP")
  cw=$(config_get TEMP_WALL)
  case "$cw" in
    ''|0|*[!0-9]*) WALL=$DEFAULT_WALL; AUTO=1 ;;
    *)
      [ "$cw" -lt 440 ] && cw=440
      [ "$cw" -gt "$WALL_MAX" ] && cw=$WALL_MAX
      WALL=$cw; AUTO=0
      ;;
  esac
  RESTORED=0
  ENABLED=$(config_get ENABLE_PEAK); [ -z "$ENABLED" ] && ENABLED=1

  if [ "$SUPPORTED" = "1" ]; then
    capture_orig
    stage_base
    regen_all "$WALL" || log "detect: tablegen failed, check $ORIG"
  else
    rm -rf "$STAGE" 2>/dev/null
  fi

  profile_write
  log "detect: root=$ODM_ROOT project=$PROJECT max=${MAX_CURRENT}mA sections=$SECTIONS wall=$WALL auto=$AUTO default=$HAS_DEFAULT dir=$HAS_DIR fold=$HAS_FOLD supported=$SUPPORTED"
  return 0
}

prepare() {
  ENABLED=$(config_get ENABLE_PEAK); [ -z "$ENABLED" ] && ENABLED=1
  if [ "$ENABLED" != "1" ]; then
    log "prepare: ENABLE_PEAK=0, skip overlay"
    return 0
  fi

  # 只在开机、尚未挂载 stage 时调用。若 stage 已在挂载，重建会制造 stale inode。
  if grep -q "coloros_fullpower/stage" /proc/self/mountinfo 2>/dev/null; then
    echo "err=stage_mounted"
    return 1
  fi

  i=0
  # 目录先出现、表后落盘的情况在 ColorOS 上很常见；必须等到真正有表，
  # 不能只等 fastchg 目录存在，否则一次误判成 unsupported 就整次开机跳过。
  while [ "$i" -lt 8 ]; do
    find_odm_roots
    find_default
    [ -n "$DEFAULT_TGT" ] && break
    any_project_table && break
    sleep 1; i=$((i+1))
  done

  detect
  return $?
}

show() {
  load_profile
  ENABLED=$(config_get ENABLE_PEAK); [ -z "$ENABLED" ] && ENABLED=1
  echo "enabled=$ENABLED"
  echo "supported=$SUPPORTED"
  echo "format=${FORMAT:-unknown}"
  echo "wall=$WALL"
  echo "auto=$AUTO"
  echo "restored=$RESTORED"
  echo "default_wall=$DEFAULT_WALL"
  echo "max_current=$MAX_CURRENT"
  echo "max_temp=$MAX_TEMP"
  echo "max_table_temp=$MAX_TABLE_TEMP"
  echo "wall_max=$WALL_MAX"
  echo "project=$PROJECT"
  printf 'sections=%s\n' "$SECTIONS"
  echo "active_section=$ACTIVE_SECTION"
  echo "odm_root=$ODM_ROOT"
  echo "default_name=$DEFAULT_NAME"
  echo "fold_name=$FOLD_NAME"
  echo "primary_hyper=$PRIMARY_HYPER"
}

set_wall() {
  want=$1
  case "$want" in ''|*[!0-9]*) echo "err=bad_temp"; return 1 ;; esac

  load_profile
  if [ "$SUPPORTED" != "1" ]; then echo "err=unsupported"; return 1; fi
  [ "$want" -lt 440 ] && want=440
  [ "$want" -gt "$WALL_MAX" ] && want=$WALL_MAX
  old=$WALL; old_auto=$AUTO; old_restored=$RESTORED

  WALL=$want; AUTO=0; RESTORED=0
  config_set TEMP_WALL "$want" || { echo "err=config_write"; return 1; }

  if ! regen_all "$WALL"; then
    WALL=$old; AUTO=$old_auto; RESTORED=$old_restored
    regen_all "$WALL" >/dev/null 2>&1
    if [ "$old_auto" = "1" ]; then
      config_set TEMP_WALL 0 >/dev/null 2>&1
    else
      config_set TEMP_WALL "$old" >/dev/null 2>&1
    fi
    profile_write
    echo "err=tablegen"
    return 1
  fi
  profile_write
  log "set wall=$want project=$PROJECT max=${MAX_CURRENT}mA"
  echo "wall=$want"
}

set_auto() {
  load_profile
  if [ "$SUPPORTED" != "1" ]; then echo "err=unsupported"; return 1; fi

  old=$WALL; old_auto=$AUTO; old_restored=$RESTORED
  WALL=$DEFAULT_WALL; AUTO=1; RESTORED=0
  config_set TEMP_WALL 0 || { echo "err=config_write"; return 1; }
  if ! regen_all "$WALL"; then
    WALL=$old; AUTO=$old_auto; RESTORED=$old_restored
    regen_all "$WALL" >/dev/null 2>&1
    if [ "$old_auto" = "1" ]; then
      config_set TEMP_WALL 0 >/dev/null 2>&1
    else
      config_set TEMP_WALL "$old" >/dev/null 2>&1
    fi
    profile_write
    echo "err=tablegen"
    return 1
  fi
  profile_write
  log "auto wall=$WALL project=$PROJECT max=${MAX_CURRENT}mA"
  echo "wall=$WALL"
}

restore_orig() {
  load_profile
  if [ "$SUPPORTED" != "1" ]; then echo "err=unsupported"; return 1; fi

  old=$WALL; old_auto=$AUTO; old_restored=$RESTORED
  WALL=0; AUTO=0; RESTORED=1
  if ! regen_all 0; then
    WALL=$old; AUTO=$old_auto; RESTORED=$old_restored
    regen_all "$WALL" >/dev/null 2>&1
    profile_write
    echo "err=restore"
    return 1
  fi
  profile_write
  log "restore original tables project=$PROJECT"
  echo "restored=1"
}

case "$1" in
  prepare) prepare ;;
  get)     show ;;
  set)     set_wall "$2" ;;
  auto)    set_auto ;;
  restore) restore_orig ;;
  detect)
    load_profile
    detect
    show
    ;;
  *)
    echo "usage: $0 {prepare|get|set <440-wall_max>|auto|restore|detect}"
    ;;
esac

