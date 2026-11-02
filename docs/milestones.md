# Reviewable Milestones

| Milestone | Scope | Status |
|---|---|---|
| 1. Repository audit and processor specification | Confirm whether prior repo exists; define ISA, architecture, limits, and test plan. | **Complete:** no previous RISC-V repo was supplied or present in workspace. Fresh isolated scaffold created. No RTL or tests run. |
| 2. Core RTL and basic instruction tests | Pipeline/stage registers, decoder, register file, ALU, simple memories and first instruction tests. | **Complete per user-run Vivado 2026.1 XSIM.** `tb_core_smoke`: PASS, 37 instructions retired; illegal-instruction stop checked. |
| 3. Pipeline hazards and directed tests | Forwarding, load-use stall, branch/jump redirect and flush; directed hazard/control/memory tests. | **Complete per user-run Vivado 2026.1 XSIM.** `tb_hazard_control`: PASS, 56 instructions retired, four load-use stalls, branch/jump flushes checked. |
| 4. Scoreboard, random testing, assertions, and coverage | Independent model, constrained-random, coverage and assertions/UVM. | **Complete per user-run Vivado 2026.1 XSIM/UVM 1.2.** All three expanded seeds passed with 225 retirements each, 37/37 instruction bins, 12/12 branch condition/outcome bins, reset and hazard crosses exercised, and zero UVM warnings/errors/fatals. |
| 5. Formal checks and CI | Bounded safety properties and automated portable regression; formal CI if reproducible. | **Complete per user-run WSL and GitHub Actions.** Icarus and 40-step Yosys/Z3 formal checks passed locally; the latest reported hosted workflow passed on `main` at commit `fc57f0b` (run `41441716637`). |
| 6. Documentation | Final architecture, exact subset, measured results, limits and commands. | **Updated** with the three-seed expanded UVM results, 40-step bounded formal results, hosted CI success, exact subset, known limits, and reproduction commands. |
| 7. Performance telemetry | Count active pipeline cycles and report program-specific CPI, stalls, and redirects. | **Complete per user-run Vivado 2026.1 XSIM/UVM.** Three seeds passed; workload-specific CPI was 1.200, 1.213, and 1.169. The metric excludes reset/empty cycles and is not a physical performance result. |
| 8. Synthesis and timing estimate | Add a repeatable Vivado synthesis flow for a named FPGA part and clock target, saving utilization and timing reports. | **Core-only post-synthesis reporting complete.** User ran Vivado 2026.1 for ZCU104 `xczu7ev-ffvc1156-2-e` at 10 ns. Synthesis completed with zero errors; the report shows 1,688 CLB LUTs (0.73%), 1,610 registers (0.35%), 44 CARRY8, 141 F7 muxes, and zero BRAM/DSP. Timing summary WNS=6.161 ns, TNS=0 ns, with all specified constraints met. This is a post-synthesis estimate only; no place/route or board I/O constraints were run. The separate board-wrapper implementation is recorded in milestone 10. |
| 9. Board demonstration wrapper | Integrate the core with a small ROM/RAM demo and ZCU104 clock/reset/LED pins; add a self-checking simulation. | **Simulation passed per user-run WSL Icarus.** `tb_rv32i_demo_system`: PASS in 11 cycles; checked 12 and 13 in memory, LED=`D`, no stop. The existing smoke and hazard tests also passed (37 and 56 retirements; four load-use stalls). |
| 10. FPGA implementation flow | Run synthesis, placement, physical optimization, routing, timing/DRC reports, and bitstream generation using board constraints. | **Vivado implementation, bitstream generation, and board functional check complete per user logs.** ZCU104 at 125 MHz using corrected clock pins F23/E23; synthesis, placement, physical optimization, routing, DRC, and bitstream generation completed. Vivado reported zero DRC errors. The final router log estimated WNS=3.777 ns, TNS=0 ns, WHS=0.021 ns, and THS=0 ns, with zero unrouted nets. The implementation utilization report lists 760 LUTs (0.33%), 1,088 registers (0.24%), 22 CARRY8, 64 F7, and 32 F8. Earlier WNS=3.887 ns / WPWS=3.725 ns figures came from an earlier run and are superseded. The user programmed the final bitstream and observed the expected LED result. One input and four outputs have no I/O delays, so this is not complete board I/O timing signoff. |

## Milestone 1 evidence

- Initial workspace contained no RISC-V files or Git checkout; a fresh `rv32i-pipeline` project was created independently.
- Current Codex Linux workspace lacks Icarus, Yosys, Z3, Verilator, XSIM and PowerShell on PATH.
- Earlier user environment context records Icarus, Yosys, Z3 and GTKWave in WSL, and Vivado 2026.1/XSIM with UVM 1.2 on Windows. Recheck from the user's machine before running tests.
- RTL/testbench, formal harness, and CI workflow now exist; test outcomes are documented under their respective milestones.

## Milestone 2 evidence

- Added `rtl/rv32i_core.sv`, `tb/tb_core_smoke.sv`, and runnable Icarus/XSIM smoke scripts.
- Directed smoke program covers all 29 non-control instruction mnemonics (with repeated operations and three NOPs), memory byte strobes and loads, sequential retirement metadata, and illegal-stop reporting. It avoids dependencies because forwarding/interlocks are Milestone 3.
- `./scripts/run_iverilog.sh` was actually invoked and returned exit code 127 with `ERROR: iverilog not found on PATH` in the Codex execution environment.
- The user's first Vivado 2026.1 XSIM compile reported VRFC 10-1103 on `clk`, `rst_n`, `imem_rdata`, and `dmem_rdata` under `default_nettype none`. Those ports now use plain `input wire` declarations.
- The user corrected the input declarations locally and subsequently compiled/elaborated and simulated the updated 37-instruction smoke test in Vivado 2026.1 XSIM. The final reported output was `PASS: basic RV32I smoke test; 37 instructions retired; illegal stop checked`.

## Milestone 3 evidence

- Added EX/MEM and MEM/WB forwarding with EX/MEM priority, plus same-cycle WB-to-ID bypass. Load-use detection considers only source operands actually used by the decoded instruction; a detected dependency holds PC/IF-ID and inserts one ID/EX bubble.
- Added a directed test for immediate ALU chains, forwarding priority, store base/data, load-to-ALU/store/branch/JALR dependencies, all six branch conditions taken and untaken, JAL/JALR links and flushes, a wrong-path store, and misaligned jump stop.
- The portable regression scripts now run both smoke and hazard/control tops and require explicit PASS markers without FAIL markers.
- The user ran both test tops using Vivado 2026.1 XSIM. `tb_core_smoke` passed with 37 retirements; `tb_hazard_control` passed with 56 retirements and exactly four load-use stalls.
- `bash -n scripts/run_iverilog.sh` passed in this workspace. Icarus simulation was not available here; the XSIM results above came from the user's machine.

## Milestone 4 evidence

- Added `tb/uvm/rv32i_uvm_if.sv`, `tb/uvm/rv32i_uvm_pkg.sv`, and `tb/uvm/tb_uvm_random.sv`, plus `scripts/run_xsim_uvm.ps1`.
- The UVM sequence includes directed dependency/control/memory cases followed by 120 constrained-random legal R-type, immediate, load, and store instructions. The scoreboard maintains independent 32-register and byte-memory models and compares retirement PC/instruction, register writes, and store address/data/strobes. The XSIM runner schedules three fixed seeds and saves per-seed logs and WDB waveforms.
- Coverage counters check instruction classes, load/store widths, branch outcomes, jumps, forwarding source and operand port, load-use stalls, redirects, and committed memory writes. Procedural assertions check x0, memory request validity, stall holds/bubbles, and redirect flush/target behavior.
- The user's first Vivado compile caught VRFC 10-1103 for the interface `clk` port under `default_nettype none`; changing it to `input wire` resolved the reported compile failure. The next run compiled and elaborated `rv32i_uvm_pkg` and `tb_uvm_random` successfully.
- The user ran the corrected three-seed XSIM regression. Each run compiled/elaborated and passed the independent UVM reference scoreboard with 148 retired instructions and zero UVM warnings/errors/fatals.
- Coverage summary from user-provided logs:

| Seed | R | I | Loads | Stores | Taken/untaken branches | Jumps | Stalls | EX/MEM fwd A/B | MEM/WB fwd A/B | Redirects |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 37 | 82 | 13 | 12 | 2/1 | 1 | 2 | 5/3 | 8/5 | 3 |
| 17 | 37 | 84 | 11 | 12 | 2/1 | 1 | 1 | 4/2 | 11/3 | 3 |
| 20261101 | 28 | 89 | 11 | 16 | 2/1 | 1 | 1 | 6/2 | 7/3 | 3 |

- The runner's false-positive match on the UVM `UVM_ERROR : 0` summary was fixed. The corrected runner completed all three seeds successfully. Evidence is user-provided simulator output; XSIM is not installed in this workspace.

## Milestone 5 evidence

- Added formal-only RTL assertions and a harness, plus a bounded Yosys SMTBMC/Z3 runner for register-zero, reset/memory side-effect gating, retirement write legality, load-use hold/bubble, and redirect flush/target safety properties. The runner requests 40 SMT steps.
- Added GitHub Actions workflow to install Icarus/Yosys/Z3 and run the portable directed regression and formal check.
- The user ran `bash scripts/run_iverilog.sh` in WSL. `tb_core_smoke` passed with 37 retired instructions and illegal-stop check; `tb_hazard_control` passed with 56 retired instructions, four load-use stalls, and branch/jump flush checks. Icarus emitted time-unit and constant-select compatibility warnings, but both tops printed PASS and the command proceeded to formal.
- The user ran `bash scripts/run_formal.sh` with Yosys 0.52 and Z3. Yosys parsed/elaborated the harness with zero reported design problems; SMTBMC reported `Status: PASSED` and `PASS: bounded formal safety checks through 40 SMT steps`. The reported run took about 7 minutes 39 seconds.
- After that baseline, formal-only checks were expanded to assert EX/MEM-over-MEM/WB forwarding selection and suppression of misaligned memory requests. The user reran the updated flow in the expanded project folder; Yosys/SMTBMC/Z3 again reported `Status: PASSED` through 40 steps (about 8m28s), now including those assertions.
- The first hosted Actions attempts exposed that executable mode bits were not preserved in the Windows ZIP. The workflow was corrected to invoke both scripts as `bash ./scripts/...`; commit `988bd07` was the first successful GitHub Actions `RTL regression` run. The latest reported pass is commit `fc57f0b`, run `41441716637`. The workflow runs Icarus directed simulation and bounded formal checks. Vivado UVM remains a local simulator run because hosted runners do not provide the user's Vivado/UVM environment.
- The UVM sequence/scoreboard was expanded for all 37 mnemonic bins, every branch condition taken and untaken, branch outcome × forwarded/unforwarded crosses, class × forwarding/stall counts, a mid-run reset, load-to-store/branch/JALR interlocks, and random branches/JALs with safe +4 targets. The mid-run reset clears the first-prefix store instruction before replay to check memory retention. The expanded three-seed results are recorded below.
- The user reran the corrected expanded UVM regression in Vivado 2026.1 XSIM with UVM 1.2. Seeds 1, 17, and 20261101 each compiled/elaborated and passed the scoreboard with 225 retirements, zero UVM warnings/errors/fatals, 37/37 instruction bins, 12/12 branch condition/outcome bins, mid-run reset, and requested forwarding/stall/branch crosses hit. The earlier two SRA/SRAI mismatches were resolved by the explicit sign-fill `model_sra` reference function.
- User-provided performance output: seed 1 (270 active cycles, 225 retired, 7 stalls, 17 redirects, CPI 1.200), seed 17 (273, 225, 6, 19, 1.213), and seed 20261101 (263, 225, 6, 14, 1.169). These values are specific to the tested program and zero-wait memories; reset and empty-pipeline cycles are excluded.
- Added `scripts/run_vivado_synthesis.ps1` and `.tcl` for core-only synthesis on the ZCU104 part with a 10 ns clock target. The flow writes utilization, timing summary, register-to-register timing, run metadata, and a synthesized checkpoint. The user executed the flow successfully. The utilization report shows 1,688 CLB LUTs (0.73%), 1,610 registers (0.35%), 44 CARRY8, 141 F7 muxes, and zero BRAM/DSP. The timing report shows a 6.161 ns WNS and 0 ns TNS against the 10 ns clock; all specified constraints are met. These are post-synthesis estimates, not placement/routing or board results.
- Per-seed expanded coverage highlights: seed 1: 7 stalls, 17 redirects, EX/MEM forwarding A/B=7/4, MEM/WB=12/9; seed 17: 6 stalls, 19 redirects, EX/MEM=6/4, MEM/WB=14/7; seed 20261101: 6 stalls, 14 redirects, EX/MEM=10/4, MEM/WB=12/6. Each also hit taken and untaken branches both with and without forwarded operands.
- The new attachment also shows the portable Icarus smoke and hazard tests passing (37 and 56 retirements; four load-use stalls). Icarus emitted the same time-unit and constant-select compatibility warnings as before.
- The current Codex workspace still lacks Icarus/Yosys/Z3, so simulation and formal results are from the user's WSL/GitHub Actions environments rather than local reruns. The latest reported GitHub Actions pass is on `main` at commit `fc57f0b` (run `41441716637`); earlier failed runs remain visible as historical runs.
- Formal scope is bounded safety for 40 SMT steps under the harness's deterministic two-edge initial reset and symbolic instruction/data inputs. It is not an ISA equivalence proof, induction proof, liveness proof, or proof of unbounded program correctness.
