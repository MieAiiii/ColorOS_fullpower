#!/usr/bin/env bash
# PC mock regression for adapt.sh / ctl.sh / advanced.sh
# Usage: bash _analysis/adapt_mock_test.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src"
WORK="${TMPDIR:-/tmp}/coloros_adapt_test.$$"
MOCK="$WORK/mock"
mkdir -p "$MOCK"
FAIL=0

ok() { echo "  OK   $*"; }
bad() { echo "  FAIL $*"; FAIL=$((FAIL+1)); }

# ---- mock commands ----
cat > "$MOCK/getprop" <<'EOF'
#!/bin/sh
exec </dev/null
k="$1"
v=$(awk -F= -v k="$k" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$MOCK_PROPS" </dev/null)
printf '%s\n' "$v"
EOF

cat > "$MOCK/setprop" <<'EOF'
#!/bin/sh
exec </dev/null
k="$1"; v="$2"
printf '%s\t%s\n' "$k" "$v" >> "$MOCK_PROP_WRITES"
tmp="$MOCK_PROPS.tmp"
awk -F= -v k="$k" -v v="$v" '
  $1==k { print k"="v; found=1; next }
  { print }
  END { if(!found) print k"="v }
' "$MOCK_PROPS" > "$tmp" && mv "$tmp" "$MOCK_PROPS"
EOF
cp "$MOCK/setprop" "$MOCK/resetprop"

cat > "$MOCK/pm" <<'EOF'
#!/bin/sh
exec </dev/null
case "$1" in
  path)
    grep -qx "$2" "$MOCK_PKGS" 2>/dev/null || exit 1
    echo "package:/data/app/$2/base.apk" ;;
  *) exit 0 ;;
esac
EOF

cat > "$MOCK/settings" <<'EOF'
#!/bin/sh
exec </dev/null
cmd="$1"; type="$2"; key="$3"; val="$4"
file="$MOCK_SETTINGS_DIR/$type"
[ -f "$file" ] || : > "$file"
case "$cmd" in
  list) cat "$file" ;;
  get)
    v=$(awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$file" </dev/null)
    [ -n "$v" ] && printf '%s\n' "$v" || printf 'null\n' ;;
  put)
    printf '%s\t%s\t%s\n' "$type" "$key" "$val" >> "$MOCK_PUT_LOG"
    tmp="$file.tmp"
    awk -F= -v k="$key" -v v="$val" '
      $1==k { print k"="v; found=1; next }
      { print }
      END { if(!found) print k"="v }
    ' "$file" > "$tmp" && mv "$tmp" "$file" ;;
  delete)
    tmp="$file.tmp"
    awk -F= -v k="$key" '$1!=k' "$file" > "$tmp" && mv "$tmp" "$file" ;;
esac
EOF

chmod +x "$MOCK"/*

make_profile() {
  name="$1"; rom="$2"; pkg="$3"
  p="$WORK/$name"
  rm -rf "$p"; mkdir -p "$p/settings" "$p/data"
  cp -r "$SRC" "$p/mod"
  printf '%s\n' "$rom" > "$p/rom"
  : > "$p/settings/system"; : > "$p/settings/secure"; : > "$p/settings/global"
  : > "$p/props"; : > "$p/pkgs"; : > "$p/put.log"; : > "$p/prop_writes.log"
  [ "$pkg" = "1" ] && echo "com.workbuddy.antidizzybridge" > "$p/pkgs"
  echo "ADAPT_MODE=auto" > "$p/mod/config.conf"
}

set_setting_mock() {
  p="$1"; type="$2"; key="$3"; val="$4"
  printf '%s=%s\n' "$key" "$val" >> "$p/settings/$type"
}
set_prop_mock() { p="$1"; k="$2"; v="$3"; printf '%s=%s\n' "$k" "$v" >> "$p/props"; }

add_common_globals() {
  p="$1"
  set_setting_mock "$p" global animator_duration_scale 1
  set_setting_mock "$p" global transition_animation_scale 1
  set_setting_mock "$p" global window_animation_scale 1
  set_setting_mock "$p" global media_fluid_disable_anim 0
  set_setting_mock "$p" system oplus_customize_color_ink_enable 0
  set_setting_mock "$p" system motion_sickness_relief_switch 0
  set_setting_mock "$p" secure oplus_customize_antidizzy_enable 0
}

run_status() {
  p="$1"
  export MOCK_PROPS="$p/props" MOCK_PKGS="$p/pkgs" MOCK_SETTINGS_DIR="$p/settings" \
         MOCK_PUT_LOG="$p/put.log" MOCK_PROP_WRITES="$p/prop_writes.log"
  PATH="$MOCK:$PATH" timeout 20 bash "$p/mod/webroot/ctl.sh" status
}

run_adv() {
  p="$1"; mode="$2"
  echo "ADAPT_MODE=$mode" > "$p/mod/config.conf"
  export MOCK_PROPS="$p/props" MOCK_PKGS="$p/pkgs" MOCK_SETTINGS_DIR="$p/settings" \
         MOCK_PUT_LOG="$p/put.log" MOCK_PROP_WRITES="$p/prop_writes.log"
  DATA="$p/data" LOG="$p/adv.log" PATH="$MOCK:$PATH" timeout 20 bash "$p/mod/advanced.sh"
}

expect() {
  name="$1"; file="$2"; pat="$3"
  if grep -q "$pat" "$file"; then ok "$name"; else bad "$name (missing: $pat)"; fi
}

not_expect() {
  name="$1"; file="$2"; pat="$3"
  if grep -q "$pat" "$file"; then bad "$name (unexpected: $pat)"; else ok "$name"; fi
}

# =====================================================================
# Profile A: ColorOS 17 full flagship
# =====================================================================
A="$WORK/c17_full"
make_profile c17_full "V17.0.0" 1
p="$A"
printf '%s\n' \
  "ro.build.version.oplusrom=V17.0.0" \
  "ro.build.version.release=17" \
  "ro.product.model=PMG110" \
  "ro.product.marketname=OPPO K15 Pro+" \
  "ro.oplus.gaussianlevel=3" \
  "persist.sys.oplus.anim_level=1" \
  "persist.sys.oplus.material_blur_switch=true" \
  "persist.vendor.sys.pq.hdr10p_adaptive.en=0" \
  "persist.vendor.sys.pq.hdr10_adaptive.en=0" \
  "persist.vendor.sys.pq.hdrvivid_adaptive.en=0" \
  "persist.vendor.sys.pq.ultrares.en=0" \
  "persist.vendor.sys.pq.mdp.color.adaptive.en=0" \
  "persist.vendor.sys.pq.sdr_adaptive.en=0" > "$p/props"
add_common_globals "$p"
for kv in \
  "system system_material_blur_enable 0" \
  "system system_material_stroke_enable 0" \
  "system animationBlurrySwitch 1" \
  "system game_color_enhance 1" \
  "secure is_desktop_wallpaper_blur_enable 1" \
  "secure full_screen_aod 1" \
  "secure oplus_keyguard_charge_anim_show 1" \
  "secure oplus_keyguard_workshop_aod_support 1" \
  "secure oplus_keyguard_panoramic_aod_all_day_support 1" \
  "secure follow_hand 1" \
  "secure oplus_page_slide_with_gesture 1" \
  "secure oplus_page_slide_against_gesture 1" \
  "secure oplus_tile_icon_animation_speed 1" \
  "secure display_memc_game_enable 1"; do
  set_setting_mock "$p" $kv
done
out="$WORK/c17_full.status"
run_status "$p" > "$out"
expect "C17 auto => full" "$out" "^ADAPT_EFFECTIVE=full$"
expect "C17 ROM major" "$out" "^ROM_MAJOR=17$"
for f in MATERIAL_BLUR MATERIAL_STROKE DESKTOP_BLUR FULL_AOD AOD_CHARGE AOD_WORKSHOP ALL_DAY_AOD FOLLOW_HAND GAME_MEMC GAME_COLOR HDR10P HDR10 HDRVIVID ULTRA_RES MML_COLOR AI_SDR LEGACY MOTION; do
  expect "C17 SUP_$f=1" "$out" "^SUP_${f}=1$"
done

run_adv "$p" auto
cp "$p/put.log" "$WORK/c17_full.put"
cp "$p/prop_writes.log" "$WORK/c17_full.prop"
expect "C17 apply reads full" "$p/adv.log" "适配模式：auto → full"
expect "C17 apply writes material key" "$WORK/c17_full.put" "system[[:space:]]system_material_blur_enable[[:space:]]1"
expect "C17 apply writes HDR PQ" "$WORK/c17_full.prop" "persist.vendor.sys.pq.hdr10p_adaptive.en[[:space:]]1"
not_expect "C17 no N/A for full AOD" "$p/adv.log" "N/A.*full_screen_aod"

# =====================================================================
# Profile B: ColorOS 16 mid-range, no material / no full AOD / no PQ
# =====================================================================
B="$WORK/c16_compat"
make_profile c16_compat "V16.0.1" 0
p="$B"
printf '%s\n' \
  "ro.build.version.oplusrom=V16.0.1" \
  "ro.build.version.release=16" \
  "ro.product.model=PEEM00" \
  "ro.product.marketname=OPPO Reno" \
  "ro.oplus.gaussianlevel=3" \
  "persist.sys.oplus.anim_level=1" \
  "persist.sys.oplus.material_blur_switch=true" > "$p/props"
add_common_globals "$p"
for kv in \
  "system game_color_enhance 0" \
  "secure is_desktop_wallpaper_blur_enable 1" \
  "secure follow_hand 1" \
  "secure oplus_page_slide_with_gesture 1"; do
  set_setting_mock "$p" $kv
done
out="$WORK/c16_compat.status"
run_status "$p" > "$out"
expect "C16 auto => compat" "$out" "^ADAPT_EFFECTIVE=compat$"
expect "C16 ROM major" "$out" "^ROM_MAJOR=16$"
expect "C16 no material blur" "$out" "^SUP_MATERIAL_BLUR=0$"
expect "C16 no material stroke" "$out" "^SUP_MATERIAL_STROKE=0$"
expect "C16 no full AOD" "$out" "^SUP_FULL_AOD=0$"
expect "C16 no HDR10P" "$out" "^SUP_HDR10P=0$"
expect "C16 no motion bridge" "$out" "^SUP_MOTION=0$"
expect "C16 has legacy" "$out" "^SUP_LEGACY=1$"

run_adv "$p" auto
cp "$p/put.log" "$WORK/c16.put"
cp "$p/prop_writes.log" "$WORK/c16.prop"
expect "C16 apply reads compat" "$p/adv.log" "适配模式：auto → compat"
not_expect "C16 does not create material blur key" "$WORK/c16.put" "system[[:space:]]system_material_blur_enable"
not_expect "C16 does not create full AOD key" "$WORK/c16.put" "secure[[:space:]]full_screen_aod"
not_expect "C16 does not write HDR PQ" "$WORK/c16.prop" "persist.vendor.sys.pq.hdr10"
expect "C16 N/A material" "$p/adv.log" "N/A.*system_material_blur_enable"
expect "C16 N/A full AOD" "$p/adv.log" "N/A.*full_screen_aod"

# =====================================================================
# Profile C: ColorOS 17 but stripped keys (auto must fall back to compat)
# =====================================================================
C="$WORK/c17_partial"
make_profile c17_partial "V17.0.0" 0
p="$C"
printf '%s\n' \
  "ro.build.version.oplusrom=V17.0.0" \
  "ro.build.version.release=17" \
  "ro.product.model=CPH0000" > "$p/props"
add_common_globals "$p"
set_setting_mock "$p" secure is_desktop_wallpaper_blur_enable 1
out="$WORK/c17_partial.status"
run_status "$p" > "$out"
expect "C17 partial auto => compat" "$out" "^ADAPT_EFFECTIVE=compat$"
expect "C17 partial no material blur" "$out" "^SUP_MATERIAL_BLUR=0$"
expect "C17 partial no full AOD" "$out" "^SUP_FULL_AOD=0$"

# =====================================================================
# Profile D: explicit modes
# =====================================================================
D="$WORK/modes"
make_profile modes "V17.0.0" 1
p="$D"
printf '%s\n' "ro.build.version.oplusrom=V17.0.0" > "$p/props"
add_common_globals "$p"
for kv in "system system_material_blur_enable 1" "secure full_screen_aod 1"; do set_setting_mock "$p" $kv; done
echo "ADAPT_MODE=compat" > "$p/mod/config.conf"
out="$WORK/mode_compat.status"; run_status "$p" > "$out"
expect "explicit compat on C17" "$out" "^ADAPT_EFFECTIVE=compat$"
echo "ADAPT_MODE=full" > "$p/mod/config.conf"
out="$WORK/mode_full.status"; run_status "$p" > "$out"
expect "explicit full on C17" "$out" "^ADAPT_EFFECTIVE=full$"

# =====================================================================
# Profile E: unknown ROM (no oplusrom prop)
# =====================================================================
E="$WORK/unknown"
make_profile unknown "" 0
p="$E"
: > "$p/props"; add_common_globals "$p"
out="$WORK/unknown.status"; run_status "$p" > "$out"
expect "unknown ROM => 0" "$out" "^ROM_MAJOR=0$"
expect "unknown auto => compat" "$out" "^ADAPT_EFFECTIVE=compat$"

# =====================================================================
# adaptmode write test
# =====================================================================
p="$B"
MOCK_PROPS="$p/props" MOCK_PKGS="$p/pkgs" MOCK_SETTINGS_DIR="$p/settings" \
MOCK_PUT_LOG="$p/put.log" MOCK_PROP_WRITES="$p/prop_writes.log" \
PATH="$MOCK:$PATH" sh "$p/mod/webroot/ctl.sh" adaptmode full > "$WORK/adaptmode.out"
expect "adaptmode full writes config" "$p/mod/config.conf" "^ADAPT_MODE=full$"
expect "adaptmode full effective full" "$WORK/adaptmode.out" "^ADAPT_EFFECTIVE=full$"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "ALL MOCK TESTS PASSED"
  exit 0
else
  echo "$FAIL MOCK TEST(S) FAILED"
  exit 1
fi
