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

## 6. Formal plan

Formal RTL assertions target x0 immutability, reset/memory side-effect gating, retirement write legality, load-use hold/bubble, redirect flush/target, forwarding priority, and misaligned-memory-request suppression. The user reran the updated Yosys 0.52/SMTBMC/Z3 flow in WSL; it passed through 40 steps in about 8m28s. There is no architectural equivalence proof, induction proof, liveness proof, or unbounded correctness proof.

## 7. Regression and CI

- Icarus: `scripts/run_iverilog.sh` passed again in the user's WSL environment after the verification expansion. `tb_core_smoke` reported 37 retirements and illegal stop checked; `tb_hazard_control` reported 56 retirements, four load-use stalls, and branch/jump flushes checked. Icarus printed time-unit and constant-select compatibility warnings; both tests printed PASS and the shell continued to the formal run.
- XSIM baseline: `scripts/run_xsim_uvm.ps1` passed seeds 1, 17, and 20261101 at 148 retirements each. The expanded three-seed run then passed in the user's Vivado 2026.1 XSIM/UVM 1.2 environment: each seed retired 225 instructions, hit ISA=37/37 and branch condition/outcome=12/12, exercised reset and required hazard crosses, and reported zero UVM warnings/errors/fatals. The explicit sign-fill `model_sra` fix resolved the earlier negative-value SRA/SRAI reference-model mismatches. Logs and WDB waveforms are saved per seed by the runner.
- CI: GitHub Actions installs distro Icarus/Yosys/Z3 and runs the portable directed suite plus bounded formal checks on push/PR. The workflow has not run because no push was authorized. Generic hosted runners are not assumed to have Vivado licenses; XSIM remains optional local.

## 8. Exit criteria

Capture actual commands and exit statuses; all supported instructions/directed cases pass the independent scoreboard; mandatory bins hit or justified; zero assertion failures; seeded tests repeat; watchdog passes; formal results state exact depth/assumptions/limits; CI reproduces portable regression from a clean checkout.
