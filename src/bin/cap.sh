#!/system/bin/sh
# 电池容量诊断 / 电量计再学习
DATA=/data/adb/screenoff_fix
LOG=$DATA/log
BK=$DATA/backup
O=/sys/class/oplus_chg/battery
B=/sys/class/power_supply/battery

status() {
  echo "design=$(cat $O/design_capacity 2>/dev/null)"
  echo "qmax=$(cat $O/battery_qmax 2>/dev/null)"
  echo "fcc=$(cat $O/battery_fcc 2>/dev/null)"
  echo "soh=$(cat $O/battery_soh 2>/dev/null)"
  echo "cycles=$(cat $O/battery_cc 2>/dev/null)"
  echo "charge_full=$(cat $B/charge_full 2>/dev/null)"
  echo "charge_full_design=$(cat $B/charge_full_design 2>/dev/null)"
  echo "charge_counter=$(cat $B/charge_counter 2>/dev/null)"
  echo "rm=$(cat $O/battery_rm 2>/dev/null)"
  echo "level=$(cat $B/capacity 2>/dev/null)"
  n=0
  [ -f "$LOG/full.csv" ] && n=$(wc -l < "$LOG/full.csv" 2>/dev/null | tr -d ' ')
  echo "full_log=$n"
}

# 触发电量计再学习（仅记录，不改任何容量参数）
calib() {
  mkdir -p "$BK" "$LOG" 2>/dev/null
  if [ ! -f "$BK/cap.env" ]; then
    { status; echo "captured_at=$(date '+%F %T')"; } > "$BK/cap.env"
    echo "$(date '+%F %T') cap snapshot -> backup/cap.env" >> "$LOG/changes.log"
  fi
  if echo 1 > "$O/reset_gauge" 2>/dev/null; then
    echo "$(date '+%F %T') CALIB reset_gauge=1 (电量计再学习，需完整一次满充满放)" >> "$LOG/changes.log"
    echo "ok"
  else
    echo "fail"
  fi
}

case "$1" in
  status) status ;;
  calib) calib ;;
  *) echo "usage: cap.sh {status|calib}" ;;
esac
