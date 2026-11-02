# Verification Plan — Milestone 1

Written before testbench implementation. The user's Windows Vivado 2026.1 XSIM and WSL Icarus/Yosys/Z3 runs are recorded below; local execution results are distinguished from output supplied by the user.

## 1. Verification architecture

Implement an independent instruction-level reference model in SystemVerilog. It decodes each supported instruction and updates expected PC, 32 registers, and byte-addressed little-endian memory. At every retirement, compare PC/instruction and architectural register write. Check stores against the reference memory model and use later loads to expose corruption. For illegal/misaligned events, compare stop reason and faulting PC and verify no side effect. Expected results must not be computed from DUT ALU, forwarding, branch, or memory-control signals.

Use a portable self-checking SystemVerilog testbench/memory model for Icarus. The user's Vivado 2026.1 installation has XSIM/UVM support, so add a UVM environment with constrained-random program generation, retirement monitor, architectural reference scoreboard, and reports. Keep the directed/open-source regression portable. The user must run XSIM after packaging because this workspace cannot invoke simulators.

## 2. Directed test matrix

| Area | Required cases and pass condition |
|---|---|
| Reset/validity | Startup and mid-run reset; PC restart; no stale retirement; reset gates memory/register side effects. |
| Register file | Representative read/write; x0 write ignored and reads zero; WB-to-ID same-cycle dependency. |
| Instruction completeness | At least one meaningful scoreboard-checked case for each of the 37 supported instructions; positive/negative immediates where applicable. |
| ALU boundaries | Zero, all ones, sign bit, signed/unsigned comparison differences, shift counts 0/1/31, wraparound, SRA fill, immediate extension/shift encodings. |
| Forwarding | EX/MEM and MEM/WB on rs1 and rs2; youngest matching writer wins; both operands forwarded; store data and branch operands forwarded. |
| Load-use interlock | Immediate dependent ALU, branch, store-data, and JALR-base consumer; exactly one bubble; no false stall for unused fields or rd=x0. |
| Branches | Every branch taken and untaken; signed/unsigned boundaries; forward/backward offsets; forwarded operands; wrong-path register and store ops flushed. |
| Jumps | JAL/JALR link=PC+4, rd=x0, forwarded JALR base, redirect, and wrong-path flush. |
| Loads/stores | All widths, legal offsets/lanes, sign/zero extension, strobe/data placement, readback, store-data forwarding. |
| Alignment | Misaligned LH/LHU/SH and LW/SW: no request or side effect. Misaligned branch/JAL/JALR target: wrong path suppressed. |
| Illegal encodings | FENCE, ECALL, EBREAK and malformed/reserved opcode/funct: sticky stop, correct PC, no side effect. |
| Throughput/interaction | Back-to-back stream retires one per cycle after fill absent hazards; redirect adjacent to younger load-use pattern resolves without deadlock. |

## 3. Constrained-random testing

Generate bounded seeded programs from supported instructions. Constrain registers, immediates, branch targets, memory addresses, and dependencies so programs are legal and terminate. Bias toward hazards, redirects, signed/unsigned boundaries and memory lanes. Include a watchdog. Print the seed on failure and run a separate negative stream for unsupported encodings/alignment. Random passing does not replace directed coverage.

## 4. Functional coverage

Track every mnemonic and format; branch opcode × outcome; redirect/flush type; forwarding source × operand port and priority; load-use consumer class × stall count; memory width × lane × signedness; reset phase; stop reason; x0 write attempt; back-to-back retirement; and crosses for opcode class × hazard, branch outcome × forwarding, memory width × lane, redirect × younger dependency.

Use explicit counters/bitmaps in portable tests so Icarus need not support covergroups. Add XSIM covergroups only if supported by the installed simulator. Every mandatory bin must hit or be justified unreachable.

## 5. Assertions and safety checks

Assert/check: x0 reads zero and is never written; invalid slots never write/register or issue memory; stall holds PC/IF-ID and inserts ID/EX bubble; forwarding selects youngest matching producer and never treats a load address as data; redirect flushes younger slots; wrong path cannot retire or issue memory; misaligned access cannot request memory/write a register; reset gates writes; retirement metadata stays aligned. Exercise assertions in simulation; compile success alone is not evidence.

## 6. Performance telemetry

The UVM testbench reports `pipeline_active_cycles`, `retired`, load-use stalls, redirects, and `measured_CPI`. A cycle counts when reset is released and at least one IF/ID, ID/EX, EX/MEM, or MEM/WB valid bit is set. The reported ratio is `pipeline_active_cycles / retired`; reset cycles and empty-pipeline drain cycles are excluded. The current test program and combinational, zero-wait memory model make this a workload-specific simulation metric, not FPGA frequency, silicon throughput, or a general benchmark. The user ran all three fixed seeds in Vivado 2026.1 XSIM/UVM 1.2: each retired 225 instructions with zero UVM warnings/errors/fatals. Measured CPI was 1.200 (270 cycles), 1.213 (273 cycles), and 1.169 (263 cycles) for seeds 1, 17, and 20261101.

| Seed | Active cycles | Retired | Load-use stalls | Redirects | CPI |
|---:|---:|---:|---:|---:|---:|
| 1 | 270 | 225 | 7 | 17 | 1.200 |
| 17 | 273 | 225 | 6 | 19 | 1.213 |
| 20261101 | 263 | 225 | 6 | 14 | 1.169 |

## 7. Formal plan

Formal RTL assertions target x0 immutability, reset/memory side-effect gating, retirement write legality, load-use hold/bubble, redirect flush/target, forwarding priority, and misaligned-memory-request suppression. The user reran the updated Yosys 0.52/SMTBMC/Z3 flow in WSL; it passed through 40 steps in about 8m28s. There is no architectural equivalence proof, induction proof, liveness proof, or unbounded correctness proof.

## 8. Regression and CI

- Icarus: `scripts/run_iverilog.sh` passed again in the user's WSL environment after the verification expansion. `tb_core_smoke` reported 37 retirements and illegal stop checked; `tb_hazard_control` reported 56 retirements, four load-use stalls, and branch/jump flushes checked. Icarus printed time-unit and constant-select compatibility warnings; both tests printed PASS and the shell continued to the formal run.
- XSIM baseline: `scripts/run_xsim_uvm.ps1` passed seeds 1, 17, and 20261101 at 148 retirements each. The expanded three-seed run then passed in the user's Vivado 2026.1 XSIM/UVM 1.2 environment: each seed retired 225 instructions, hit ISA=37/37 and branch condition/outcome=12/12, exercised reset and required hazard crosses, and reported zero UVM warnings/errors/fatals. The explicit sign-fill `model_sra` fix resolved the earlier negative-value SRA/SRAI reference-model mismatches. Logs and WDB waveforms are saved per seed by the runner.
- CI: GitHub Actions installs distro Icarus/Yosys/Z3 and runs the portable directed suite plus bounded formal checks on push/PR. The latest reported workflow passed on `main` at commit `fc57f0b` (run `41441716637`, 9m26s). Generic hosted runners do not run the Vivado-specific UVM suite; XSIM remains a local regression.

## 9. Synthesis reporting

`scripts/run_vivado_synthesis.ps1` invokes the Vivado Tcl flow for core-only synthesis on the named part and clock target. It saves utilization and timing reports, a clock constraint, run metadata, and a synthesized checkpoint. No measured result is recorded until the user executes the flow. The post-synthesis timing estimate is not a placed/routed result; top-level I/O delays, board routing, bitstream generation, and silicon measurements are outside scope.

## 10. Board demo checks

The standalone system demo executes a fixed ROM program, exercises ALU forwarding and a load-use interlock, stores/loads 12 and then stores 13. Its self-checking testbench verifies both memory words, the LED value `4'hd`, no core stop, and a bounded completion watchdog. Run it in the portable Icarus suite and Vivado XSIM. The board top additionally wraps the differential clock input and synchronizes the active-high reset button before core release. User-run WSL Icarus passed all three tops; the demo checked memory values 12 and 13, LED=`D`, no stop, and completed in 11 cycles. The user also programmed the corrected ZCU104 bitstream and observed DS37 off and DS38, DS39, and DS40 on, matching `1101`.

The user ran the Vivado implementation flow through routing and bitstream generation. The final clock-pin-corrected router log reports estimated WNS=3.777 ns, WHS=0.021 ns, TNS=0 ns, THS=0 ns, and zero unrouted nets; Vivado reported zero DRC errors. The implementation utilization report lists 760 CLB LUTs (0.33%), 1,088 registers (0.24%), 22 CARRY8, 64 F7 muxes, and 32 F8 muxes. Earlier timing figures of WNS=3.887 ns and WPWS=3.725 ns were from a prior implementation and are superseded. One input and four outputs lack I/O delay constraints, so the report is not complete board I/O timing signoff. The user programmed the final bitstream and observed the expected LED pattern; this is a board functional check, not a silicon timing measurement.

## 11. Exit criteria

Capture actual commands and exit statuses; all supported instructions/directed cases pass the independent scoreboard; mandatory bins hit or justified; zero assertion failures; seeded tests repeat; watchdog passes; formal results state exact depth/assumptions/limits; CI reproduces portable regression from a clean checkout.
