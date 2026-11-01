# Processor Specification — Milestone 1

## 1. Goal and compliance claim

Build a synthesizable, in-order, single-issue, 32-bit processor with five stages: **IF → ID → EX → MEM → WB**. The target is a documented subset of the unprivileged RV32I base integer ISA. Because `FENCE`, `ECALL`, and `EBREAK` are intentionally unsupported, the project must not claim full RV32I compliance. Compressed instructions and all extensions are out of scope.

## 2. Exact supported instruction set

All arithmetic is 32-bit modulo 2^32; registers are 32 bits and instruction words are 32 bits.

| Group | Supported instructions |
|---|---|
| Register arithmetic/logic | `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND` |
| Immediate arithmetic/logic | `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI` |
| Loads | `LB`, `LH`, `LW`, `LBU`, `LHU` |
| Stores | `SB`, `SH`, `SW` |
| Conditional branches | `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU` |
| Jumps | `JAL`, `JALR` |
| Upper immediates | `LUI`, `AUIPC` |

This is 37 instructions. Every other encoding, including `FENCE`, `ECALL`, and `EBREAK`, is unsupported and produces a sticky illegal-instruction stop indication without register or memory side effects. This indication is a simple core interface, not a privileged trap handler or machine-mode exception architecture.

## 3. Architectural behavior

- Little-endian memory, byte-addressed 32-bit PC, 32 integer registers. `x0` always reads as zero; writes to it are ignored.
- Reset PC is `0x00000000`. With no compressed-instruction support, fetch addresses are 4-byte aligned.
- Signed operations use two's-complement signed interpretation. `SLTIU` compares `rs1` against the sign-extended immediate as an unsigned value. Shift amount is the low five bits; immediate shift encodings must be legal RV32I encodings.
- `LUI` writes the U-immediate. `AUIPC` writes `PC + U-immediate` modulo 2^32.
- `JAL` writes `PC+4` to `rd`, target=`PC + sign-extended J-immediate`. `JALR` writes `PC+4`, target=`(rs1 + sign-extended I-immediate) & ~1`. A resulting target not 4-byte aligned stops with an instruction-address-misaligned indication.
- Branch target is `PC + sign-extended B-immediate`; signed and unsigned comparisons are distinct as named. Check target alignment only when the branch is taken.
- Illegal or faulting instruction stops fetch; that instruction must not write a register or issue a memory request. Stop is sticky until reset. No trap vector, interrupt, CSR, or recovery mechanism is provided.

## 4. Pipeline contract

Each pipeline register carries a valid bit, PC, instruction word, and the required operand/control metadata. Invalid bubbles have no architectural or memory side effects.

- **IF:** instruction address/read interface; sequential PC increments by 4 absent stall/redirect.
- **ID:** decode, register reads, immediate generation, and source-use identification. Same-cycle WB-to-ID bypass is expected to avoid stale reads.
- **EX:** ALU, effective address, forwarded branch operands, branch comparison and redirect decision.
- **MEM:** data operation through byte-enable interface. Initial response is combinational; a write is accepted at the active edge. No wait states or bus errors.
- **WB:** register writeback and retirement observation containing valid, PC, instruction, register write enable, destination and value. Store/fault events must also be observable for scoreboard checks.

The initial memory interface is a simple simulation/teaching interface, not AXI and not variable-latency memory.

## 5. Hazards and control flow

- Forward the youngest available older result to EX from EX/MEM or MEM/WB. Never forward a load effective address as loaded data; never forward x0.
- If ID/EX is a load to nonzero `rd` and IF/ID consumes that register, insert one bubble into ID/EX and hold PC/IF/ID for one cycle while the load advances. Detect only actually consumed sources; ignore unused encoded `rs` fields.
- Branch comparison and JALR base calculation use forwarded operands.
- Resolve branch/JAL/JALR in EX. On redirect, squash younger IF/ID and ID/EX work and suppress wrong-path writes and memory requests.
- Older EX redirect has priority over a younger load-use stall.

## 6. Memory and alignment

- Data interface is byte-addressed: `addr[31:0]`, read/write enables, `write_data[31:0]`, `write_strobe[3:0]`, `read_data[31:0]`.
- `LB/LBU` access one byte; `LH/LHU` access an aligned halfword; `LW` accesses an aligned word. LB/LH sign-extend; LBU/LHU zero-extend.
- `SB/SH/SW` generate lane-correct write data and byte strobes; the external memory applies enabled bytes.
- Byte addresses may be arbitrary; halfword accesses require `addr[0]==0`; word accesses require `addr[1:0]==0`.
- Misaligned halfword/word load/store gives a sticky data-misaligned stop, emits no request, and causes no register/memory side effect. No split-access emulation.
- Sequential fetch is word-aligned. A taken branch/JAL/JALR target that is not word-aligned stops with an instruction-address-misaligned indication before a wrong-path instruction can commit; an untaken branch does not fault on its unused target.

## 7. Reset and harness

- `rst_n` is active-low. At a rising edge during reset, PC returns to zero, pipeline valid bits clear, stop state clears, and registers initialize to zero for deterministic simulation. `x0` is hard-wired to zero regardless.
- Reset gates memory requests and register writes. The harness initializes instruction/data arrays independently; reset does not clear data memory.
- Initial harness uses separate instruction/data memories, combinational reads, edge-triggered byte writes, and testbench program loading before reset release.

## 8. Deliberate limits

Not full RV32I compliance: no FENCE/ECALL/EBREAK. Also no M/A/C/Zicsr, floating point, privileged ISA, interrupts, debug, caches, MMU, variable bus latency/errors, branch prediction, or misaligned access emulation. No performance, FPGA timing, or synthesis claim until measured on a named tool/device setup.
