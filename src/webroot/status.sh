#!/system/bin/sh
# 只读状态采集：供 WebUI 显示，不做任何写入。
# 所有路径来自 /data/adb/coloros_fullpower/profile.env；
# 没有 profile 时退回 /odm/firmware/fastchg 兼容旧安装。

MODDIR=/data/adb/modules/coloros_fullpower
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules_update/coloros_fullpower
P=/data/adb/coloros_fullpower/profile.env

SUPPORTED=0
ODM_ROOT=/odm/firmware/fastchg
PROJECT="?"
MAX_CURRENT=0
MAX_TEMP=0
MAX_TABLE_TEMP=0
TABLE_LADDER_MAX=480
SECTIONS=""
ACTIVE_SECTION=""
DEFAULT_NAME=""
PRIMARY_HYPER=""
WALL=0
AUTO=1
RESTORED=0
DEFAULT_WALL=440
WALL_MAX=480
HAS_DEFAULT=0
HAS_DIR=0
HAS_FOLD=0
DEFAULT_TGT=""
DEFAULT_SRC=""
FOLD_TGT=""
FOLD_SRC=""
DIR_TGT=""
DIR_SRC=""
SILICON_TGT=""
SILICON_SRC=""
HYPER_TGT=""
HYPER_SRC=""

[ -f "$P" ] && . "$P" 2>/dev/null

# 没有 profile 时按候选根找一个真实存在的 fastchg 目录，
# 避免旧安装/首次启动把 /odm/firmware/fastchg 当成唯一路径。
if [ ! -f "$P" ]; then
  for d in /odm/firmware/fastchg /odm/etc/firmware/fastchg \
           /vendor/firmware/fastchg /vendor/etc/firmware/fastchg \
           /my_odm/firmware/fastchg /my_product/firmware/fastchg \
           /product/firmware/fastchg /system_ext/firmware/fastchg; do
    [ -d "$d" ] && { ODM_ROOT=$d; break; }
  done
fi

D1=${DEFAULT_TGT:-$ODM_ROOT/charging_thermal_config_default.txt}
D2=${DIR_TGT:-}
S=${SILICON_SRC:-}
H=${HYPER_SRC:-}
if [ -n "$D2" ]; then
  [ -n "$S" ] || S=$D2/silicon_single_charging_hyper_mode_config.txt
  [ -n "$H" ] || H=$D2/${PRIMARY_HYPER:-charging_hyper_mode_config.txt}
fi

echo "supported=$SUPPORTED"
echo "project=$PROJECT"
echo "sections=$SECTIONS"
echo "active_section=$ACTIVE_SECTION"
echo "has_default=$HAS_DEFAULT"
echo "has_dir=$HAS_DIR"
echo "wall=$WALL"
echo "auto=$AUTO"
echo "restored=$RESTORED"
echo "default_wall=$DEFAULT_WALL"
echo "wall_max=$WALL_MAX"
echo "max_temp=$MAX_TEMP"
echo "max_table_temp=$MAX_TABLE_TEMP"
echo "ladder_max=$TABLE_LADDER_MAX"
echo "max_current=$MAX_CURRENT"
echo "odm_root=$ODM_ROOT"

c1=$(mount 2>/dev/null | grep -c "on $D1 ")
[ "$c1" -ge 1 ] && echo "m_default=1" || echo "m_default=0"
if [ -n "$D2" ] && mount 2>/dev/null | grep -q "on $D2 "; then
  echo "m_dir=1"
else
  echo "m_dir=0"
fi
[ -n "$S" ] && [ -f "$S" ] && echo "f_silicon=1" || echo "f_silicon=0"
[ -n "$H" ] && [ -f "$H" ] && echo "f_hyper=1" || echo "f_hyper=0"
if [ -n "$D2" ]; then
  echo "label=$(ls -Z "$D2" 2>/dev/null | grep -c vendor_configs_file)"
  echo "label_total=$(ls -A "$D2" 2>/dev/null | wc -l | tr -d ' ')"
else
  echo "label=0"
  echo "label_total=0"
fi
if [ -n "$D1" ] && [ -f "$D1" ]; then echo "sz_default=$(wc -c < "$D1" 2>/dev/null | tr -d ' ')"; else echo "sz_default=0"; fi
if [ -n "$S" ] && [ -f "$S" ]; then echo "sz_silicon=$(wc -c < "$S" 2>/dev/null | tr -d ' ')"; else echo "sz_silicon=0"; fi
if [ -n "$H" ] && [ -f "$H" ]; then echo "sz_hyper=$(wc -c < "$H" 2>/dev/null | tr -d ' ')"; else echo "sz_hyper=0"; fi
if [ -n "$FOLD_TGT" ] && [ -f "$FOLD_TGT" ]; then echo "sz_fold=$(wc -c < "$FOLD_TGT" 2>/dev/null | tr -d ' ')"; else echo "sz_fold=0"; fi

imax=$MAX_CURRENT
if { [ -z "$imax" ] || [ "$imax" = "0" ]; } && [ -n "$S" ] && [ -f "$S" ]; then
  imax=$(awk -F, '$1+0>0 && $2+0>0 {if($2+0>m)m=$2+0} END{print m+0}' "$S" 2>/dev/null)
fi
[ -n "$imax" ] || imax=0
echo "imax=$imax"

if [ -n "$S" ] && [ -f "$S" ]; then
  thr=$(awk -F, '$1+0>0 && $2+0>0 {if($2+0>=m){m=$2+0;t=$1+0}} END{print t+0}' "$S" 2>/dev/null)
else
  thr=0
fi
[ -n "$thr" ] || thr=0
echo "thr=$thr"

echo "bstatus=$(cat /sys/class/power_supply/battery/status 2>/dev/null)"
echo "batt_ma=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)"
echo "batt_mv=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null)"
echo "batt_temp=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)"
echo "soc=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null)"
echo "usb_ua=$(cat /sys/class/power_supply/usb/current_now 2>/dev/null)"
echo "usb_uv=$(cat /sys/class/power_supply/usb/voltage_now 2>/dev/null)"
echo "fast_type=$(cat /sys/class/oplus_chg/usb/fast_chg_type 2>/dev/null)"
echo "adapter=$(cat /sys/class/oplus_chg/common/adapter_power 2>/dev/null)"
echo "cool_down=$(cat /sys/class/oplus_chg/battery/cool_down 2>/dev/null)"
echo "screen=$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=' | sed 's/.*mWakefulness=//')"
echo "hal_err=$(logcat -d -b all -t 400 2>/dev/null | grep -ci SingleHyper)"

sh "$MODDIR/bin/peak.sh" status 2>/dev/null

echo "cap_design=$(cat /sys/class/oplus_chg/battery/design_capacity 2>/dev/null)"
echo "cap_qmax=$(cat /sys/class/oplus_chg/battery/battery_qmax 2>/dev/null)"
echo "cap_fcc=$(cat /sys/class/oplus_chg/battery/battery_fcc 2>/dev/null)"
echo "cap_soh=$(cat /sys/class/oplus_chg/battery/battery_soh 2>/dev/null)"
echo "cap_cycles=$(cat /sys/class/oplus_chg/battery/battery_cc 2>/dev/null)"
echo "cap_counter=$(cat /sys/class/power_supply/battery/charge_counter 2>/dev/null)"
echo "cap_full=$(cat /sys/class/power_supply/battery/charge_full 2>/dev/null)"
if [ -f /data/adb/screenoff_fix/log/full.csv ]; then
  echo "cap_full_log=$(wc -l < /data/adb/screenoff_fix/log/full.csv 2>/dev/null | tr -d ' ')"
else
  echo "cap_full_log=0"
fi

