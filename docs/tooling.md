# Tool Availability Checks

Run checks from the project root before choosing a regression. This Codex Linux workspace is distinct from the user's Windows and WSL installations.

## Windows PowerShell — Vivado / XSIM / UVM

```powershell
$names = 'git', 'python', 'vivado', 'xvlog', 'xelab', 'xsim'
foreach ($name in $names) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { '{0,-10} {1}' -f $name, $cmd.Source }
    else      { '{0,-10} unavailable' -f $name }
}
"XILINX_VIVADO=$env:XILINX_VIVADO"
```

If Vivado commands are not on PATH, use the Vivado 2026.1 command prompt/settings before retrying. Confirm the UVM 1.2 library path and compile a smoke test before relying on UVM features.

## WSL Ubuntu — simulation / formal

```bash
for tool in iverilog vvp yosys z3 gtkwave yosys-smtbmc sby; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-14s %s\n' "$tool" "$(command -v "$tool")"
    "$tool" --version 2>&1 | head -n 1 || true
  else
    printf '%-14s unavailable\n' "$tool"
  fi
done
```

Formal commands depend on `yosys-smtbmc` or SymbiYosys (`sby`) being installed and supporting the selected frontend. GTKWave is for waveform inspection, not pass/fail.

## Check performed in this workspace

At Milestone 5, `iverilog`, `vvp`, `yosys`, `yosys-smtbmc`, `z3`, `sby`, `verilator`, `xsim`, `xvlog`, `pwsh`, and `powershell` are still unavailable on PATH. `bash -n scripts/run_formal.sh scripts/run_iverilog.sh` passes. Invoking `scripts/run_iverilog.sh` exits 127 with `ERROR: iverilog not found on PATH`; `scripts/run_formal.sh` exits 127 with `ERROR: required formal tool 'yosys' is not on PATH`. Therefore the formal harness and CI workflow have not yet been executed in this workspace. This is distinct from the user's own Windows/WSL tool installations and the XSIM results the user supplied.

## User-run WSL evidence

The user ran the updated `bash scripts/run_iverilog.sh` from the expanded project folder. Both directed tests printed PASS; Icarus emitted time-unit and constant-select compatibility warnings. The user then ran `bash scripts/run_formal.sh` with Yosys 0.52 and Z3; SMTBMC reported `Status: PASSED` at 40 steps in approximately 8 minutes 28 seconds, including the newly added forwarding-priority and memory-alignment assertions. The user also ran the expanded three-seed UVM suite in Vivado 2026.1 XSIM/UVM 1.2; all seeds passed with 225 retirements, 37/37 ISA bins, 12/12 branch outcome bins, reset/hazard crosses exercised, and zero UVM warnings/errors/fatals. These are results from the user's environments, not reruns in this workspace. The GitHub Actions workflow is configured but not run.
