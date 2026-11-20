#!/system/bin/sh
# ============================================================
#  系统级温控开关 —— ColorOS 满血特性 6.0
#  作者：三重 / 酷安@MieAi
#
#  on      禁用系统温控：清空亮度/刷新率/CPU降频策略(sys_thermal_control)、
#          关闭高温保护行为(sys_high_temp_protect)、清空并停止 horae
#  off     恢复：只卸载本模块自己的挂载层，恢复 horae 属性
#          并把 horae 拉回 running（旧快照里的 0/stopped 不可信）
#  status  输出 key=value 状态（供 WebUI 解析）
#
#  关键修复：
#    - 不再把 sys_thermal_state.txt 的存在当作“挂载还在”。
#      每次 on 都检查 mountinfo 顶层；不是本模块就补一层。
#    - off 只卸“顶层是本模块 payload”的项，避免误删其他模块的层。
#    - status 的 mine / layers 来自真实 mountinfo，不再用 state 行数冒充。
#
#  原理：用户态温控策略文件 bind mount 覆盖。
#    - 内核熔断（MTK trip 118.8℃）不受影响
#    - 电池/充电温度热区（battery / mtk-charger）不受影响
#    - thermal_core 进程保留（充电温度监控依赖；策略清空后无动作可执行）
#
#  ⚠ 高温不降频不降亮意味着极端场景下芯片可能长时间高热。
# ============================================================

BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODPATH=$(dirname -- "$BIN_DIR")
STATE="$MODPATH/sys_thermal_state.txt"
ORIGENV="$MODPATH/sys_thermal_orig.env"
LOG="$MODPATH/sys_thermal.log"
PL="$MODPATH/payload"
mkdir -p "$PL" 2>/dev/null

log(){ echo "$(date '+%F %T') $*" >> "$LOG" 2>/dev/null; }

capture_origin() {
  [ -f "$ORIGENV" ] && return 0
  {
    echo "ORIG_HORAE_PROP=$(getprop persist.sys.horae.enable 2>/dev/null)"
    echo "ORIG_HORAE_SVC=$(getprop init.svc.horae 2>/dev/null)"
    echo "ORIG_THERMAL_SVC=$(getprop init.svc.thermal-engine 2>/dev/null)"
    echo "SNAPSHOT_AT=$(date '+%F %T')"
  } > "$ORIGENV" 2>/dev/null
}

restore_services() {
  OHP="1"; OHS="running"; OTS="running"
  if [ -f "$ORIGENV" ]; then
    . "$ORIGENV" 2>/dev/null
    OHP=${ORIG_HORAE_PROP:-1}
    OHS=${ORIG_HORAE_SVC:-}
    OTS=${ORIG_THERMAL_SVC:-}
  fi
  # 旧快照可能是在上一次 on 之后才生成的，里面记录的 0/stopped
  # 正是本模块把温控停掉后的状态，不是原厂状态。若继续按它恢复，
  # 用户关掉“去除温控”后 horae 仍然是 stopped。这里做一次可用性修复：
  # 属性必须是 1，horae 必须拉起；thermal-engine 仅在明确存在时处理。
  case "$OHP" in ''|0|*[!0-9]*) OHP=1 ;; esac
  case "$OHS" in running) ;; *) OHS=running ;; esac
  case "$OTS" in running|stopped) ;; *) OTS=running ;; esac
  setprop persist.sys.horae.enable "$OHP" 2>/dev/null
  if [ "$OHS" = "running" ]; then
    setprop ctl.start horae 2>/dev/null
    i=0
    while [ "$i" -lt 4 ]; do
      [ "$(getprop init.svc.horae 2>/dev/null)" = "running" ] && break
      sleep 1; i=$((i+1))
    done
  fi
  case "$OTS" in
    running) setprop ctl.start thermal-engine 2>/dev/null ;;
    stopped) setprop ctl.stop thermal-engine 2>/dev/null ;;
  esac
  # 恢复成功后把快照修正为健康状态，避免下一次 on 又拿旧的 0/stopped
  # 当“原厂值”。
  if [ "$(getprop init.svc.horae 2>/dev/null)" = "running" ]; then
    {
      echo "ORIG_HORAE_PROP=1"
      echo "ORIG_HORAE_SVC=running"
      echo "ORIG_THERMAL_SVC=$(getprop init.svc.thermal-engine 2>/dev/null)"
      echo "SNAPSHOT_AT=$(date '+%F %T')"
      echo "SNAPSHOT_REPAIRED=1"
    } > "$ORIGENV" 2>/dev/null
  fi
  log "restore_services prop=$OHP horae=$(getprop init.svc.horae 2>/dev/null) thermal_engine=$(getprop init.svc.thermal-engine 2>/dev/null)"
}

opt_chmod() {
  src=$1; ref=$2
  # Toybox 不支持 chmod/chcon --reference；直接取目标原始上下文。
  ctx=$(ls -Z "$ref" 2>/dev/null | awk '{print $1}')
  case "$ctx" in
    u:object_r:*) ;;
    *) case "$ref" in
         /odm/*|/vendor/*) ctx=u:object_r:vendor_configs_file:s0 ;;
         *) ctx=u:object_r:system_file:s0 ;;
       esac ;;
  esac
  chmod 644 "$src" 2>/dev/null
  chown 0:0 "$src" 2>/dev/null
  chcon "$ctx" "$src" 2>/dev/null || log "chcon failed: $ref"
}

# ---------------- 探测目标（按设备实际文件名）----------------
# spec 格式: 目标:类型   类型 empty=0字节清空 / protect=高温保护全关
add_target(){
  spec=$1
  case " $TARGETS " in *" $spec "*) ;; *) TARGETS="$TARGETS $spec" ;; esac
}

build_targets(){
  TARGETS=""
  for f in /odm/etc/temperature_profile/*thermal*control*.xml \
           /odm/etc/temperature_profile/sys_thermal_control*.xml \
           /system_ext/etc/temperature_profile/*thermal*control*.xml \
           /vendor/etc/temperature_profile/*thermal*control*.xml \
           /my_product/etc/temperature_profile/*thermal*control*.xml; do
    [ -f "$f" ] || continue
    add_target "$f:empty"
  done
  for f in /odm/etc/temperature_profile/*high_temp_protect*.xml \
           /system_ext/etc/temperature_profile/*high_temp_protect*.xml \
           /vendor/etc/temperature_profile/*high_temp_protect*.xml \
           /my_product/etc/temperature_profile/*high_temp_protect*.xml; do
    [ -f "$f" ] || continue
    add_target "$f:protect"
  done
  for f in /odm/etc/horae/horae_target.conf \
           /odm/etc/horae/horae.conf \
           /system_ext/etc/horae/horae.conf; do
    [ -f "$f" ] || continue
    add_target "$f:empty"
  done
}

# ---------------- payload ----------------
make_payload(){
  kind="$1"
  target="$2"
  # 每个目标必须独立文件：多个 empty 目标共用一个 inode 时，
  # 最后一次 chcon 会把前面所有挂载的 SELinux 上下文一起改掉。
  tag=$(printf '%s' "$target" | sed 's#^/##; s#/#_#g')
  [ -n "$tag" ] || tag=default
  case "$kind" in
    empty)
      p="$PL/empty_${tag}.bin"
      : > "$p"
      echo "$p" ;;
    protect)
      p="$PL/protect_${tag}.xml"
      cat > "$p" <<'XMLEOF'
<filter-conf>
    <version>2020070201</version>
    <isOpen>1</isOpen>
    <filter-name>sys_high_temp_protect</filter-name>
    <HighTemperatureProtectSwitch>false</HighTemperatureProtectSwitch>
    <HighTemperatureShutdownSwitch>false</HighTemperatureShutdownSwitch>
    <HighTemperatureFirstStepSwitch>false</HighTemperatureFirstStepSwitch>
    <HighTemperatureDisableFlashSwitch>false</HighTemperatureDisableFlashSwitch>
    <CountBatteryChangedForFosUpdateTime>30</CountBatteryChangedForFosUpdateTime>
    <HighTemperatureShutdownUpdateTime>15</HighTemperatureShutdownUpdateTime>
    <HighTemperatureProtectFirstStepIn>0</HighTemperatureProtectFirstStepIn>
    <HighTemperatureProtectFirstStepOut>0</HighTemperatureProtectFirstStepOut>
    <HighTemperatureProtectThresholdIn>0</HighTemperatureProtectThresholdIn>
    <HighTemperatureProtectThresholdOut>0</HighTemperatureProtectThresholdOut>
    <HighTemperatureProtectShutDown>0</HighTemperatureProtectShutDown>
    <MediumTemperatureProtectThreshold>10000</MediumTemperatureProtectThreshold>
    <HighTemperatureDisableFlashLimit>0</HighTemperatureDisableFlashLimit>
    <HighTemperatureDisableFlashChargeLimit>0</HighTemperatureDisableFlashChargeLimit>
    <camera_temperature_limit>0</camera_temperature_limit>
    <HighTemperatureFinishCameraLimit>0</HighTemperatureFinishCameraLimit>
    <HighTemperatureProtect1080PVideoSwitch>false</HighTemperatureProtect1080PVideoSwitch>
    <HighTemperatureProtect720PVideoSwitch>false</HighTemperatureProtect720PVideoSwitch>
    <HighTemperatureDisableFlashCountTime>30</HighTemperatureDisableFlashCountTime>
    <DoubleCheckTime>60000</DoubleCheckTime>
    <HighTemperatureControlVideoRecordSwitch>false</HighTemperatureControlVideoRecordSwitch>
    <HighTemperatureDisableVideoRecordLimit>0</HighTemperatureDisableVideoRecordLimit>
    <HighTemperatureEnableVideoRecordLimit>0</HighTemperatureEnableVideoRecordLimit>
    <HighTemperatureRestoreBrightnessLimit>0</HighTemperatureRestoreBrightnessLimit>
    <ToleranceFirstStepIn>0</ToleranceFirstStepIn>
    <ToleranceFirstStepOut>0</ToleranceFirstStepOut>
    <ToleranceSecondStepIn>0</ToleranceSecondStepIn>
    <ToleranceSecondStepOut>0</ToleranceSecondStepOut>
    <ToleranceThreshold>60</ToleranceThreshold>
    <ToleranceStart>0</ToleranceStart>
    <ToleranceStop>0</ToleranceStop>
    <ToleranceInterval>30000</ToleranceInterval>
</filter-conf>
XMLEOF
      echo "$p" ;;
  esac
}

count_mounts(){
  awk -v t="$1" '$5==t{c++} END{print c+0}' /proc/self/mountinfo 2>/dev/null
}

# mountinfo 的顺序是旧层到新层，最后一条同 mountpoint 的记录就是当前顶层。
top_root(){
  awk -v t="$1" '$5==t{root=$4} END{print root}' /proc/self/mountinfo 2>/dev/null
}

is_ours(){
  case "$(top_root "$1")" in
    *coloros_fullpower/payload*) return 0 ;;
    *) return 1 ;;
  esac
}

state_rebuild(){
  : > "$STATE" 2>/dev/null
  for spec in $TARGETS; do
    tgt="${spec%:*}"
    is_ours "$tgt" && echo "$tgt" >> "$STATE"
  done
}

do_on(){
  build_targets
  capture_origin
  : > "$STATE" 2>/dev/null
  ok=0; skip=0; fail=0
  for spec in $TARGETS; do
    tgt="${spec%:*}"; kind="${spec##*:}"
    if is_ours "$tgt"; then
      skip=$((skip+1)); echo "$tgt" >> "$STATE"
      log "TOP-OK $tgt"
      continue
    fi
    src=$(make_payload "$kind" "$tgt")
    opt_chmod "$src" "$tgt"
    if mount --bind "$src" "$tgt" 2>/dev/null; then
      echo "$tgt" >> "$STATE"
      ok=$((ok+1)); log "MOUNT $tgt <- $src"
    else
      fail=$((fail+1)); log "MOUNT FAIL $tgt"
    fi
  done
  # horae：属性 + 服务（幂等；本机无对应服务时静默失败）
  setprop persist.sys.horae.enable 0 2>/dev/null
  setprop ctl.stop horae 2>/dev/null
  setprop ctl.stop thermal-engine 2>/dev/null
  log "ON 完成 ok=$ok skip=$skip fail=$fail"
  echo "applied=$ok skipped=$skip failed=$fail"
}

do_off(){
  build_targets
  n=0; fail=0
  for spec in $TARGETS; do
    tgt="${spec%:*}"
    # 只卸自己的层；如果别的模块盖在顶上，先不动，留给用户/模块各自处理。
    j=0
    while [ "$j" -lt 3 ] && is_ours "$tgt"; do
      if umount "$tgt" 2>/dev/null; then
        n=$((n+1)); log "UMOUNT $tgt"
      else
        fail=$((fail+1)); log "UMOUNT FAIL $tgt"; break
      fi
      j=$((j+1))
    done
  done
  state_rebuild
  restore_services
  log "OFF 完成 restored=$n failed=$fail"
  echo "restored=$n"
}

do_status(){
  build_targets
  total=0; layers=0; mine=0
  for spec in $TARGETS; do
    tgt="${spec%:*}"
    total=$((total+1))
    layers=$((layers + $(count_mounts "$tgt")))
    is_ours "$tgt" && mine=$((mine+1))
  done

  if [ "$total" -gt 0 ] && [ "$mine" -eq "$total" ]; then
    st=on
  elif [ "$mine" -gt 0 ]; then
    st=partial
  else
    st=off
  fi

  echo "systhermal=$st"
  echo "targets=$total"
  echo "layers=$layers"
  echo "mine=$mine"
  echo "top_ok=$mine"
  if [ -f "$STATE" ]; then
    echo "state_lines=$(wc -l < "$STATE" 2>/dev/null | tr -d ' ')"
  else
    echo "state_lines=0"
  fi

  # 不同 ColorOS 16/17 机型的充电 HAL 服务名不同，只做展示，不做功能依赖。
  hal=""
  for p in init.svc.vendor.oplus.hardware.charger-V12-service \
           init.svc.vendor.oplus.hardware.charger-V11-service \
           init.svc.vendor.oplus.hardware.charger-V10-service \
           init.svc.vendor.oplus.hardware.charger-service; do
    v=$(getprop "$p" 2>/dev/null)
    [ -n "$v" ] && { hal=$v; break; }
  done
  if [ -z "$hal" ]; then
    # 未命中已知名字时，从属性表里发现任意 charger 服务，避免新 HAL 代际显示空。
    for p in $(getprop 2>/dev/null | sed -n 's/^\[\(init\.svc\..*[Cc]harger.*\)\]:.*/\1/p'); do
      v=$(getprop "$p" 2>/dev/null)
      [ -n "$v" ] && { hal=$v; break; }
    done
  fi
  [ -z "$hal" ] && hal=$(getprop init.svc.vendor.thermal-mediatek 2>/dev/null)
  echo "hal=$hal"
  echo "horae=$(getprop init.svc.horae 2>/dev/null)"
  echo "thermal_core=$(getprop init.svc.thermal_core 2>/dev/null)"
  echo "horae_prop=$(getprop persist.sys.horae.enable 2>/dev/null)"
}

case "$1" in
  on)     do_on ;;
  off)    do_off ;;
  status) do_status ;;
  *)      echo "usage: tempctl.sh {on|off|status}" ;;
esac
