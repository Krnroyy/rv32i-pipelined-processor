# Five-Stage RV32I Subset Processor

A new, isolated 32-bit in-order processor portfolio project for RTL design and design verification roles. Intended pipeline: **IF → ID → EX → MEM → WB**.

## Status

**Milestones 1–6 are documented; expanded UVM, directed simulation, bounded formal checks, and GitHub Actions have passed.** The three-seed expanded UVM regression passed in Vivado 2026.1 XSIM/UVM 1.2 with 225 retirements per seed, 37/37 instruction bins, 12/12 branch condition/outcome bins, reset and hazard crosses covered, and zero UVM warnings/errors/fatals. The Icarus directed suite and 40-step Yosys 0.52/Z3 formal check passed in WSL. GitHub Actions passed on `main` at commit `988bd07`, running the portable directed regression and bounded formal checks.

This repository is isolated from the user's other projects. No other repositories, portfolio, releases, or remote branches have been modified.

## ISA scope

The planned core supports 37 RV32I integer instructions: arithmetic/logic, byte/halfword/word loads and stores, conditional branches, jumps, and upper immediates. `FENCE`, `ECALL`, and `EBREAK` are intentionally unsupported, so this will be described as an **RV32I subset**, not a fully RV32I-compliant implementation. See [`docs/processor_spec.md`](docs/processor_spec.md).

## Documents

- [`docs/processor_spec.md`](docs/processor_spec.md): architecture, exact instruction set, pipeline behavior, memory, reset, alignment, and limits.
- [`docs/test_plan.md`](docs/test_plan.md): reference model, scoreboard, directed/random tests, assertions, coverage, formal, and CI.
- [`docs/milestones.md`](docs/milestones.md): reviewable progress and exit criteria.
- [`docs/tooling.md`](docs/tooling.md): availability checks for PowerShell and WSL.

## Tool check commands

PowerShell commands: Set-Location to the repository; run `git status --short --branch`; then run `Get-Command git, python, vivado, xvlog, xelab, xsim -ErrorAction SilentlyContinue | Select-Object Name, Source`.

WSL commands:

```bash
cd <path-to-this-repository>
git status --short --branch
for tool in iverilog vvp yosys z3 gtkwave; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-12s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '%-12s unavailable\n' "$tool"
  fi
done
```

The current Codex Linux environment does not expose Icarus, Yosys, Z3, Verilator, XSIM, or PowerShell on `PATH`. The user supplied successful WSL output for Icarus, Yosys 0.52, and Z3, and successful Windows output for Vivado 2026.1/XSim with UVM 1.2.

## Basic smoke regression

From WSL run `./scripts/run_iverilog.sh`. From PowerShell run the directed XSIM suite with `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_xsim_smoke.ps1`. The smoke program covers arithmetic/immediate operations, LUI/AUIPC, all five load forms, all three store forms, retirement order, and illegal-instruction stop. `tb_hazard_control` covers forwarding, load-use stalls, branch/jump redirects, and wrong-path suppression; the user has run both directed tests successfully in XSIM.

For the UVM reference-model test, use a Vivado 2026.1 PowerShell prompt and run `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_xsim_uvm.ps1`. It uses UVM 1.2, runs three fixed SystemVerilog seeds using XSIM's `-sv_seed` option, saves a log and WDB waveform per seed, and checks scoreboard, coverage, and safety-check results. This UVM test is simulator-specific; the Icarus script remains the portable directed suite.

## Current verification limits

The earlier baseline UVM seeds retired 148 instructions and generated only R-type, I-type, loads, and stores. The expanded regression passed its three fixed seeds after correcting the model's SRA/SRAI sign-fill handling. Exhaustive boundary values and a complete formal architectural-equivalence proof are not claimed. The bounded formal safety check passed for 40 SMT steps; no unbounded proof is claimed.

## Formal and CI

`scripts/run_formal.sh` passed through 40 SMT steps with the latest assertions in the user's WSL run. GitHub Actions (`.github/workflows/rtl-regression.yml`) passed on commit `988bd07` and runs the portable Icarus directed tests and formal job on pushes and pull requests. Hosted CI does not run the Vivado-specific UVM suite. See [`docs/milestones.md`](docs/milestones.md) for run evidence and limits.
