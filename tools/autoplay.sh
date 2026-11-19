#!/bin/sh
# Plays the whole flow with the autoplay bot and saves screenshots to docs/renders/.
# Usage: tools/autoplay.sh [shots_dir]   (needs godot + xvfb-run; CI runs this on every push)
set -e
SHOTS=${1:-$(pwd)/docs/renders}
XDG=$(mktemp -d)
XDG_DATA_HOME=$XDG timeout 300 xvfb-run -a -s "-screen 0 1080x1920x24" godot --path . \
  --rendering-driver opengl3 --resolution 540x960 -- --autoplay --shots="$SHOTS" 2>&1 | tee autoplay.log
rm -rf "$XDG"
grep -q "^AUTOPLAY PASS" autoplay.log && ! grep -qE "^FAIL|^AUTOPLAY FAIL|SCRIPT ERROR" autoplay.log || { echo "autoplay failed"; exit 1; }
