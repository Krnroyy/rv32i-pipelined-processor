#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v iverilog >/dev/null 2>&1 || { echo "ERROR: iverilog not found on PATH" >&2; exit 127; }
command -v vvp >/dev/null 2>&1 || { echo "ERROR: vvp not found on PATH" >&2; exit 127; }
mkdir -p build
for tb in tb_core_smoke tb_hazard_control; do
  iverilog -g2012 -Wall -s "$tb" -o "build/$tb.vvp" rtl/rv32i_core.sv "tb/$tb.sv"
  run_output="$(vvp "build/$tb.vvp" 2>&1)" || { status=$?; printf '%s\n' "$run_output"; exit "$status"; }
  printf '%s\n' "$run_output"
  if [[ "$run_output" == *"FAIL:"* ]]; then
    echo "ERROR: $tb emitted a FAIL marker" >&2
    exit 1
  fi
  if [[ "$run_output" != *"PASS:"* ]]; then
    echo "ERROR: $tb PASS marker not found" >&2
    exit 1
  fi
done
