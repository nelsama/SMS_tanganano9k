#!/usr/bin/env bash
# sim/run_sys.sh frames [pad@from-to ...]   (pad in hex: 01 U 02 D 04 L
# 08 R 10 button 1 20 button 2 100 Pause). Synthesizes sms_sys, turns the netlist into
# C++ and runs it; pictures in build/sim. SKIP_SYN=1 reuses the netlist.
set -euo pipefail
export PATH=/c/msys64/ucrt64/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd); O=$ROOT/build/sim; mkdir -p "$O"; cd "$O"
if [ "${SKIP_SYN:-0}" = 0 ]; then
  bash "$ROOT/tools/build.sh" syn
  python "$ROOT/sim/netlist2cpp.py" "$ROOT/build/syn/impl/gwsynthesis/sms_sys.vg" sms_sys netlist.h
  g++ -O2 -I. -o sim_sys "$ROOT/sim/sim_sys.cpp"
fi
rm -f ./*.ppm
./sim_sys "$1" . "${@:2}"
for f in *.ppm; do ffmpeg -v error -y -i "$f" -vf scale=512:480:flags=neighbor "${f%.ppm}.png"; done
