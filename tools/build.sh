#!/usr/bin/env bash
# tools/build.sh [pnr|syn]   Gowin command-line build into build/<mode>
#   pnr  full build, bitstream build/pnr/impl/pnr/sms_top.fs
#   syn  sms_sys netlist only (for sim/run_sys.sh)
set -euo pipefail
GW_SH=${GW_SH:-/c/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe}
ROOT=$(cd "$(dirname "$0")/.." && pwd); W=$(cd "$ROOT" && pwd -W); MODE=${1:-pnr}
OUT=$ROOT/build/$MODE; mkdir -p "$OUT"; cd "$OUT"
{
  echo "set_device GW1NR-LV9QN88PC6/I5 -device_version C"
  for f in T80_Pack T80_ALU T80_MCode T80_Reg T80 T80sed; do echo "add_file -type vhdl {$W/src/cpu/$f.vhd}"; done
  for f in "$W"/src/sms/*.v "$W/src/board/sms_sys.v" "$W/src/board/sms2hdmi.v"; do echo "add_file -type verilog {$f}"; done
  echo "set_option -verilog_std sysv2017"
  echo "set_option -include_path {$W/src/board}"
  if [ "$MODE" = pnr ]; then
    echo "add_file -type verilog {$W/src/board/sms_psport.v}"
    echo "add_file -type verilog {$W/src/board/sms_top.v}"
    for f in "$W"/src/board/hdmi/*.vhd "$W"/src/memory/*.vhd; do echo "add_file -type vhdl {$f}"; done
    echo "add_file -type cst {$W/src/board/sms_tn9k.cst}"
    echo "add_file -type sdc {$W/src/board/sms_tn9k.sdc}"
    echo "set_option -top_module sms_top"
    echo "set_option -output_base_name sms_top"
    echo "set_option -use_sspi_as_gpio 1"
    echo "set_option -use_mspi_as_gpio 1"
    echo "set_option -timing_driven 1"
    echo "run all"
  else
    echo "set_option -top_module sms_sys"
    echo "set_option -output_base_name sms_sys"
    echo "set_option -disable_io_insertion 1"
    echo "run syn"
  fi
} > b.tcl
"$GW_SH" b.tcl > out.log 2>&1 || true
grep -E 'ERROR' out.log || true
tail -1 out.log
if [ -f impl/pnr/sms_top.rpt.txt ]; then
  grep -E '^ +(Logic|Register|BSRAM|CLS|rPLL) ' impl/pnr/sms_top.rpt.txt || true
fi
