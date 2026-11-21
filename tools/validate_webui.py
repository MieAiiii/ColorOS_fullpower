#!/usr/bin/env python3
"""Static checks for the ColorOS特性补全 WebUI.

Usage: python tools/validate_webui.py
"""
from __future__ import annotations

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "src" / "webroot" / "index.html"


def main() -> int:
    text = HTML.read_text(encoding="utf-8")
    ok = True

    scripts = re.findall(r"<script[^>]*>(.*?)</script>", text, re.S | re.I)
    if not scripts:
        print("FAIL: no <script> block")
        return 1
    js = "\n".join(scripts)
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8") as f:
        f.write(js)
        js_path = f.name
    try:
        proc = subprocess.run(
            ["node", "--check", js_path],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        if proc.returncode != 0:
            print("FAIL: node --check")
            print(proc.stderr.strip())
            ok = False
        else:
            print("PASS: JS syntax")
    finally:
        Path(js_path).unlink(missing_ok=True)

    ids = re.findall(r'\bid\s*=\s*"([^"]+)"', text)
    dup = sorted({x for x in ids if ids.count(x) > 1})
    if dup:
        print("FAIL: duplicate ids: " + ", ".join(dup))
        ok = False
    else:
        print(f"PASS: {len(ids)} unique ids")

    refs = set(re.findall(r'\$\("([^"]+)"\)', js))
    missing = sorted(refs - set(ids))
    if missing:
        print("FAIL: $() references missing ids: " + ", ".join(missing))
        ok = False
    else:
        print(f"PASS: {len(refs)} $() id references all exist")

    required = [
        "page-log", "page-motion",
        "swMotion", "motionEntry", "motionStatus",
        "valGain", "valGainY", "valGate", "btnMotionReset",
        "swReading", "btnApply", "btnRefresh", "btnLog",
    ]
    missing_req = [x for x in required if x not in ids]
    if missing_req:
        print("FAIL: required ids missing: " + ", ".join(missing_req))
        ok = False
    else:
        print("PASS: required ids present")

    sw = set(re.findall(r'data-cfg="([^"]+)"', text))
    for key in (
        "ENABLE_ADVANCED", "ENABLE_ANTIDIZZY", "ENABLE_LEGACY",
        "ENABLE_MATERIAL_BLUR", "ENABLE_FULL_AOD", "ENABLE_FOLLOW_HAND",
        "ENABLE_GAME_MEMC", "ENABLE_HDR10P_ADAPTIVE",
    ):
        if key not in sw:
            print(f"FAIL: switch {key} missing")
            ok = False

    for token in (
        'data-open="page-motion"', 'data-close="page-motion"',
        "motionparam", "motionreset", "MOTION_GAIN", "MOTION_GAIN_Y", "MOTION_GATE",
    ):
        if token not in text:
            print(f"FAIL: UI control token missing: {token}")
            ok = False

    for stale in ("已移除：", "9.1.2", "刷新率与分辨率都已退出本模块", "vRefresh"):
        if stale in text:
            print(f"FAIL: stale copy remains: {stale}")
            ok = False

    print("RESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
