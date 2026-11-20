#!/system/bin/sh
# 峰值保持 —— 守护进程 / 配置 / 留痕 / 恢复 / 日志轮转
# 只写 /sys/class/oplus_chg 下的运行时降档标志，不改任何电芯参数
DATA=/data/adb/screenoff_fix
CONF=$DATA/config.env
LOG=$DATA/log
STATE=/dev/screenoff_fix_state
PIDF=$DATA/daemon.pid
BAT=/sys/class/power_supply/battery
OCB=/sys/class/oplus_chg/battery
OCC=/sys/class/oplus_chg/common

MAX_LOG=524288      # changes.log / daemon.log 上限 512 KB
MAX_CSV=2097152     # peak.csv 上限 2 MB
IDLE_SLEEP=30       # 未充电时的休眠间隔

init() {
  mkdir -p "$LOG" "$DATA/backup" 2>/dev/null
  touch "$LOG/changes.log" "$LOG/daemon.log" "$LOG/peak.csv" "$LOG/full.csv" 2>/dev/null
  [ -f "$DATA/clear_count" ] || echo 0 > "$DATA/clear_count"
  if [ ! -f "$CONF" ]; then
    cat > "$CONF" <<EOF
ENABLED=1
TARGET_SOC=90
EOF
  fi
  if [ ! -f "$DATA/backup/orig.env" ]; then
    {
      echo "ORIG_cool_down=$(cat $OCB/cool_down 2>/dev/null)"
      echo "ORIG_normal_cool_down=$(cat $OCB/normal_cool_down 2>/dev/null)"
      echo "ORIG_slow_chg_en=$(cat $OCB/slow_chg_en 2>/dev/null)"
      echo "ORIG_chg_up_limit=$(cat $OCC/chg_up_limit 2>/dev/null)"
      echo "ORIG_mmi=$(cat $OCB/mmi_charging_enable 2>/dev/null)"
      echo "SNAPSHOT_AT=$(date '+%F %T')"
    } > "$DATA/backup/orig.env"
    echo "$(date '+%F %T') snapshot orig values -> backup/orig.env" >> "$LOG/changes.log"
  else
    # 5.x 的旧快照缺少新键；补齐后再 restore，避免漏恢复。
    grep -q '^ORIG_normal_cool_down=' "$DATA/backup/orig.env" 2>/dev/null || \
      echo "ORIG_normal_cool_down=$(cat $OCB/normal_cool_down 2>/dev/null)" >> "$DATA/backup/orig.env"
    grep -q '^ORIG_mmi=' "$DATA/backup/orig.env" 2>/dev/null || \
      echo "ORIG_mmi=$(cat $OCB/mmi_charging_enable 2>/dev/null)" >> "$DATA/backup/orig.env"
  fi
}

size_of() { wc -c < "$1" 2>/dev/null | tr -d ' '; }

# 超限则滚动：保留一份 .1，避免无限增长
rotate() {
  f=$1; cap=$2
  [ -f "$f" ] || return 0
  s=$(size_of "$f")
  [ -z "$s" ] && return 0
  [ "$s" -le "$cap" ] && return 0
  mv -f "$f" "$f.1" 2>/dev/null
  : > "$f" 2>/dev/null
  echo "$(date '+%F %T') rotate $(basename "$f"): $s bytes -> $f.1" >> "$LOG/changes.log"
}

gc() {
  init
  rotate "$LOG/changes.log" "$MAX_LOG"
  rotate "$LOG/daemon.log" "$MAX_LOG"
  rotate "$LOG/peak.csv" "$MAX_CSV"
  rotate "$LOG/full.csv" 65536
}

setconf() {
  k=$1; v=$2
  [ -f "$CONF" ] || init
  tmp=$CONF.tmp
  grep -v "^$k=" "$CONF" > "$tmp" 2>/dev/null
  echo "$k=$v" >> "$tmp"
  mv -f "$tmp" "$CONF"
}

clear_flag() {
  f=$1; want=$2; name=$3
  cur=$(cat "$f" 2>/dev/null)
  [ -z "$cur" ] && return
  [ "$cur" = "$want" ] && return
  if echo "$want" > "$f" 2>/dev/null; then
    echo "$(date '+%F %T') clear $name: [$cur] -> [$want]" >> "$LOG/changes.log"
    n=$(cat "$DATA/clear_count" 2>/dev/null); n=$((n + 1))
    echo "$n" > "$DATA/clear_count"
  fi
}

# OPPO 各代 HAL 的 slow_chg_en 字段数可能不同（2 段/4 段/更多）。
# 不写死 "0,0,0,0"，按当前值实际字段数生成全 0 列表。
zero_list_like() {
  cur=$1
  n=$(printf '%s' "$cur" | awk -F, '{print NF}' 2>/dev/null)
  case "$n" in ''|*[!0-9]*|0) n=1 ;; esac
  out=""; i=1
  while [ "$i" -le "$n" ]; do
    [ "$i" -gt 1 ] && out="$out,"
    out="${out}0"
    i=$((i+1))
  done
  echo "$out"
}

# chg_up_limit 的“未启用上限”值在不同 HAL 上字段数不同。
# 常见 5 段 = 0,80,0,80,2；按字段数保留 80 阈值位，避免写坏未知格式。
limit_clear_like() {
  cur=$1
  n=$(printf '%s' "$cur" | awk -F, '{print NF}' 2>/dev/null)
  case "$n" in ''|*[!0-9]*|0) n=1 ;; esac
  case "$n" in
    1) echo 0 ;;
    2) echo 0,80 ;;
    3) echo 0,80,0 ;;
    4) echo 0,80,0,80 ;;
    5) echo 0,80,0,80,2 ;;
    *) echo "" ;;
  esac
}

# 任一电源在线即视为"有充电器插入"
power_online() {
  ch=0
  for p in /sys/class/power_supply/usb/online \
           /sys/class/power_supply/ac/online \
           /sys/class/power_supply/wireless/online; do
    [ "$(cat "$p" 2>/dev/null)" = "1" ] && ch=1
  done
  echo "$ch"
}

daemon() {
  init
  echo $$ > "$PIDF"
  . "$CONF"
  echo "$(date '+%F %T') daemon start pid=$$ enabled=$ENABLED target=$TARGET_SOC" >> "$LOG/daemon.log"
  tick=0
  while :; do
    . "$CONF" 2>/dev/null

    # —— 未接电源：静默待机，不碰 sysfs、不写日志、不写 CSV ——
    if [ "$(power_online)" != "1" ]; then
      echo "idle (未接电源)" > "$STATE"
      rm -f /dev/screenoff_fix_fullmark
      tick=0
      sleep $IDLE_SLEEP
      continue
    fi

    soc=$(cat "$BAT/capacity" 2>/dev/null)
    if [ -z "$soc" ] || [ "$soc" != "${soc##*[!0-9]*}" ]; then
      echo "waiting (电量节点未就绪)" > "$STATE"
      sleep 5
      continue
    fi

    # 满充取证：每次插电只记一次。
    # 不能放在 guarding 分支里：TARGET_SOC<=100 时 soc>=target 会先进入
    # released，永远到不了 guarding，full.csv 会一直是 0 B。
    st=$(cat "$BAT/status" 2>/dev/null)
    if [ "$st" = "Full" ]; then
      if [ ! -f /dev/screenoff_fix_fullmark ]; then
        touch /dev/screenoff_fix_fullmark 2>/dev/null
        cf=$(cat "$BAT/charge_full" 2>/dev/null)
        cfd=$(cat "$BAT/charge_full_design" 2>/dev/null)
        cc=$(cat "$BAT/charge_counter" 2>/dev/null)
        vb=$(cat "$BAT/voltage_now" 2>/dev/null)
        fccn=$(cat "$OCB/battery_fcc" 2>/dev/null)
        qmx=$(cat "$OCB/battery_qmax" 2>/dev/null)
        sohn=$(cat "$OCB/battery_soh" 2>/dev/null)
        echo "$(date '+%F %T'),$soc,$cc,$cf,$cfd,$fccn,$qmx,$sohn,$vb" >> "$LOG/full.csv"
        echo "$(date '+%F %T') FULL recorded counter=$cc full=$cf design=$cfd" >> "$LOG/changes.log"
      fi
    else
      rm -f /dev/screenoff_fix_fullmark 2>/dev/null
    fi

    if [ "$ENABLED" != "1" ]; then
      echo "disabled soc=$soc" > "$STATE"
    elif [ "$soc" -ge "$TARGET_SOC" ] 2>/dev/null; then
      echo "released soc=$soc target=$TARGET_SOC" > "$STATE"
    else
      echo "guarding soc=$soc target=$TARGET_SOC" > "$STATE"
      clear_flag "$OCB/cool_down" "0" "cool_down"
      clear_flag "$OCB/normal_cool_down" "0" "normal_cool_down"
      slowcur=$(cat "$OCB/slow_chg_en" 2>/dev/null)
      slowwant=$(zero_list_like "$slowcur")
      [ -n "$slowwant" ] && clear_flag "$OCB/slow_chg_en" "$slowwant" "slow_chg_en"
      upcur=$(cat "$OCC/chg_up_limit" 2>/dev/null)
      upwant=$(limit_clear_like "$upcur")
      [ -n "$upwant" ] && clear_flag "$OCC/chg_up_limit" "$upwant" "chg_up_limit"

      tick=$((tick + 1))
      if [ $((tick % 15)) -eq 0 ]; then
        ma=$(cat "$BAT/current_now" 2>/dev/null)
        mv=$(cat "$BAT/voltage_now" 2>/dev/null)
        tp=$(cat "$BAT/temp" 2>/dev/null)
        ft=$(cat /sys/class/oplus_chg/usb/fast_chg_type 2>/dev/null)
        ap=$(cat "$OCC/adapter_power" 2>/dev/null)
        am=${ma#-}
        w=$((am * mv / 1000000))
        echo "$(date '+%F %T'),$soc,$tp,$am,$mv,$w,$ft,$ap,$(cat $OCB/cool_down 2>/dev/null)" >> "$LOG/peak.csv"
      fi
      # 每 20 个周期检查一次体积
      [ $((tick % 20)) -eq 0 ] && gc
    fi
    sleep 3
  done
}

pid_is_daemon() {
  p=$1
  [ -n "$p" ] || return 1
  kill -0 "$p" 2>/dev/null || return 1
  cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)
  case "$cmd" in *peak.sh*daemon*) return 0 ;; *) return 1 ;; esac
}

start() {
  init
  if [ -f "$PIDF" ]; then
    p=$(cat "$PIDF" 2>/dev/null)
    if pid_is_daemon "$p"; then
      echo "daemon already running pid=$p"
      return 0
    fi
    # PID 可能被系统复用；不验证 cmdline 就 kill 会误杀别的进程。
    rm -f "$PIDF" 2>/dev/null
  fi
  # KernelSU 的 service 脚本退出时会带走同进程组的后台子进程；
  # 用 setsid 新建会话，让守护进程挂到 init 下继续运行。
  if command -v setsid >/dev/null 2>&1; then
    setsid sh "$0" daemon >> "$LOG/daemon.log" 2>&1 < /dev/null &
  else
    nohup sh "$0" daemon >> "$LOG/daemon.log" 2>&1 &
  fi
  sleep 1
  echo "started pid=$(cat "$PIDF" 2>/dev/null)"
}

stop() {
  if [ -f "$PIDF" ]; then
    p=$(cat "$PIDF" 2>/dev/null)
    if pid_is_daemon "$p"; then
      kill "$p" 2>/dev/null
    fi
    rm -f "$PIDF"
    echo "$(date '+%F %T') daemon stop by user" >> "$LOG/changes.log" 2>/dev/null
  fi
  echo "stopped" > "$STATE" 2>/dev/null
}

status() {
  # 只读：不调用 init()，避免 WebUI 刷新时去 touch 日志文件。
  ENABLED=1; TARGET_SOC=90
  [ -f "$CONF" ] && . "$CONF" 2>/dev/null
  echo "enabled=$ENABLED"
  echo "target=$TARGET_SOC"
  echo "state=$(cat $STATE 2>/dev/null)"
  echo "power_online=$(power_online)"
  echo "clear_count=$(cat $DATA/clear_count 2>/dev/null)"
  if [ -f "$PIDF" ] && pid_is_daemon "$(cat "$PIDF" 2>/dev/null)"; then echo "running=1"; else echo "running=0"; fi
  if [ -f "$LOG/peak.csv" ]; then echo "csv_lines=$(wc -l < "$LOG/peak.csv" 2>/dev/null | tr -d ' ')"; else echo "csv_lines=0"; fi
  if [ -f "$LOG/full.csv" ]; then echo "full_lines=$(wc -l < "$LOG/full.csv" 2>/dev/null | tr -d ' ')"; else echo "full_lines=0"; fi
  cb=$(size_of "$LOG/changes.log"); [ -n "$cb" ] || cb=0; echo "changes_bytes=$cb"
  pb=$(size_of "$LOG/peak.csv"); [ -n "$pb" ] || pb=0; echo "csv_bytes=$pb"
  db=$(size_of "$LOG/daemon.log"); [ -n "$db" ] || db=0; echo "daemon_bytes=$db"
  tb=$(du -sk "$DATA" 2>/dev/null | cut -f1); [ -n "$tb" ] || tb=0; echo "total_bytes=$tb"
}

restore() {
  init
  stop
  setconf ENABLED 0
  if [ -f "$DATA/backup/orig.env" ]; then
    . "$DATA/backup/orig.env"
    [ -n "$ORIG_cool_down" ] && echo "$ORIG_cool_down" > "$OCB/cool_down" 2>/dev/null
    [ -n "$ORIG_normal_cool_down" ] && echo "$ORIG_normal_cool_down" > "$OCB/normal_cool_down" 2>/dev/null
    [ -n "$ORIG_slow_chg_en" ] && echo "$ORIG_slow_chg_en" > "$OCB/slow_chg_en" 2>/dev/null
    [ -n "$ORIG_chg_up_limit" ] && echo "$ORIG_chg_up_limit" > "$OCC/chg_up_limit" 2>/dev/null
    [ -n "$ORIG_mmi" ] && echo "$ORIG_mmi" > "$OCB/mmi_charging_enable" 2>/dev/null
    echo "$(date '+%F %T') restored orig sysfs values, ENABLED=0" >> "$LOG/changes.log"
  fi
  echo "$(date '+%F %T') restore executed" >> "$LOG/changes.log"
  echo "restored; 模块本体仍挂载，卸载+重启即完全复原"
}

case "$1" in
  daemon) daemon ;;
  start) start ;;
  stop) stop ;;
  status) status ;;
  restore) restore ;;
  gc) gc && status ;;
  set)
    init
    v=$(echo "$3" | tr -cd '0-9')
    case "$2" in
      ENABLED)
        [ "$v" = "1" ] || v=0
        setconf ENABLED "$v"
        [ "$v" = "1" ] && start || stop
        ;;
      TARGET_SOC)
        [ -z "$v" ] && { echo "reject"; exit 1; }
        [ "$v" -lt 60 ] && v=60
        [ "$v" -gt 100 ] && v=100
        setconf TARGET_SOC "$v"
        ;;
      *) echo "unknown key: $2"; exit 1 ;;
    esac
    echo "ok $2=$v"
    ;;
  log)
    tail -n 20 "$LOG/changes.log" 2>/dev/null
    ;;
  *) echo "usage: peak.sh {start|stop|status|restore|gc|set <key> <val>|log}" ;;
esac
