#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in yosys yosys-smtbmc z3; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "ERROR: required formal tool '$tool' is not on PATH" >&2
    exit 127
  }
done

mkdir -p build/formal
yosys -Q -p "read_verilog -formal -sv rtl/rv32i_core.sv formal/rv32i_formal_top.sv; prep -top rv32i_formal_top -flatten; write_smt2 -wires build/formal/rv32i.smt2" \
  | tee build/formal/yosys.log
yosys-smtbmc -s z3 -t 40 --presat --dump-vcd build/formal/failure.vcd build/formal/rv32i.smt2 \
  | tee build/formal/smtbmc.log
grep -q 'Status: PASSED' build/formal/smtbmc.log || {
  echo "ERROR: bounded formal safety run did not report PASS" >&2
  exit 1
}
echo "PASS: bounded formal safety checks through 40 SMT steps"
