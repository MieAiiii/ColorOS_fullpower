# ============================================================
#  ColorOS 充电温控表生成器（通用，不绑定机型）
#
#  输入：原厂 charging_thermal_config_*.txt / *hyper_mode_config.txt
#  输出：同结构表，但把每个 *_THERMAL_CONTROL 段的最大电流档
#        放到温度墙 wall（0.1℃），其余电流档按设备原有阶梯
#        等距铺到本机梯度上限 tmax（由 tempwall 依本机表计算）。
#
#  设计约束：
#    - 只改温度，不改电流值、档位 gear、协议段顺序、文件头。
#    - 不引入固定电流/温度参数；全部来自输入表。
#    - 如果表里没有 *_THERMAL_CONTROL_START，原样输出，由上层判定不支持。
#
#  用法：awk -f tablegen.awk -v wall=<440..WALL_MAX> -v tmax=<WALL_MAX> orig.txt > out.txt
# ============================================================

BEGIN {
  FS = ","
  insec = 0
  n = 0
  hasgear = 0
  wall = wall + 0
  if (wall < 0) wall = 0
  # 温度阶梯上限也来自本机表（由 tempwall 传入 WALL_MAX），
  # 不再无条件铺到 580；低电流档不能超出本机算出的安全上限。
  tmax = tmax + 0
  if (tmax < wall) tmax = wall
  if (tmax < 440) tmax = 440
  if (tmax > 580) tmax = 580
}

function reset_section(  i) {
  for (i in cur) delete cur[i]
  for (i in gear) delete gear[i]
  n = 0
  hasgear = 0
}

function emit_section(  i, j, m, tmp, arr, last, prev, t, c) {
  if (n == 0) return

  # 复制电流列表并按从大到小排序；用插入排序，避免依赖 awk 的 asort。
  for (i = 1; i <= n; i++) arr[i] = cur[i]
  for (i = 2; i <= n; i++) {
    tmp = arr[i]
    j = i - 1
    while (j >= 1 && arr[j] < tmp) {
      arr[j + 1] = arr[j]
      j--
    }
    arr[j + 1] = tmp
  }

  # 去重，保留每个电流第一次出现时的 gear。
  m = 0
  for (i = 1; i <= n; i++) {
    if (m == 0 || arr[i] != last[m]) {
      m++
      last[m] = arr[i]
    }
  }

  prev = -1
  for (i = 1; i <= m; i++) {
    c = last[i]
    if (m == 1) {
      t = wall
    } else {
      t = wall + int((tmax - wall) * (i - 1) / (m - 1) + 0.5)
    }
    if (i > 1 && t <= prev) t = prev + 1
    if (t > tmax) t = tmax
    prev = t

    if (hasgear)
      printf "%d,%d,%s\n", t, c, gear[c]
    else
      printf "%d,%d\n", t, c
  }
}

{
  # 去掉 CR，兼容 Windows/CRLF 生成的厂商表。
  sub(/\r$/, "")

  if ($0 ~ /^[ \t]*[A-Za-z0-9_-]+_[Tt][Hh][Ee][Rr][Mm][Aa][Ll]_[Cc][Oo][Nn][Tt][Rr][Oo][Ll]_[Ss][Tt][Aa][Rr][Tt][ \t]*$/) {
    print
    insec = 1
    reset_section()
    next
  }

  if ($0 ~ /^[ \t]*[A-Za-z0-9_-]+_[Tt][Hh][Ee][Rr][Mm][Aa][Ll]_[Cc][Oo][Nn][Tt][Rr][Oo][Ll]_[Ee][Nn][Dd][ \t]*$/) {
    emit_section()
    print
    insec = 0
    next
  }

  if (insec && $0 ~ /^[ \t]*[0-9]+[ \t]*,[ \t]*[0-9]+/) {
    c = $2 + 0
    if (c <= 0) next
    g = ""
    if (NF >= 3) {
      g = $3
      gsub(/^[ \t]+/, "", g)
      gsub(/[ \t]+$/, "", g)
    }
    n++
    cur[n] = c
    if (g != "") {
      hasgear = 1
      if (!(c in gear)) gear[c] = g
    }
    next
  }

  print
}

END {
  if (insec) emit_section()
}
