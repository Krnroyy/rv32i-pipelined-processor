# Vivado Synthesis and Timing Estimate

This flow gives the five-stage core a reproducible synthesis target and saves reports for review. It synthesizes `rv32i_core` as a standalone top, targeting the ZCU104 FPGA part `xczu7ev-ffvc1156-2-e` with a 10 ns (100 MHz) clock by default. It does not instantiate the testbench memories or a board wrapper.

## Run from PowerShell

From the project root, with Vivado 2026.1 available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_vivado_synthesis.ps1
```

If Vivado is installed outside the default path and is not on PATH:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_vivado_synthesis.ps1 `
  -VivadoBin 'C:\AMDDesignTools\2026.1\Vivado\bin' `
  -Part 'xczu7ev-ffvc1156-2-e' `
  -ClockPeriodNs 10.0 `
  -ReportDir '.\reports\vivado'
```

`-Part`, `-ClockPeriodNs`, and `-ReportDir` can be changed for another target. The runner checks Vivado availability and fails if Vivado exits with an error.

## Generated files

The output directory contains:

- `utilization.rpt`: post-synthesis resource estimate.
- `timing_summary.rpt`: setup timing summary, including unconstrained paths.
- `register_to_register_timing.rpt`: up to 25 register-to-register paths.
- `core_clock.xdc`: the single core clock constraint.
- `rv32i_core_synth.dcp`: synthesized design checkpoint.
- `run_info.txt`: top, part, target period, Vivado version, and flow scope.

## Limits

The flow runs `synth_design` only. It does not place or route the design, run implementation, generate a bitstream, or connect the core to a board. The clock is constrained, but external instruction/data memory and control inputs/outputs have no board-specific input/output delay constraints or pin assignments. Treat timing and area as Vivado synthesis estimates for this device and constraint set; they are not post-route timing, board performance, or silicon measurements. Review unconstrained paths and add a real wrapper and board constraints before drawing system-level timing conclusions.

## Run status

The user ran the flow in Vivado 2026.1 for the default target. Synthesis completed successfully with zero errors. The utilization report lists:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| CLB LUTs | 1,688 | 230,400 | 0.73% |
| CLB registers | 1,610 | 460,800 | 0.35% |
| CARRY8 | 44 | 28,800 | 0.15% |
| F7 muxes | 141 | 115,200 | 0.12% |
| Block RAM | 0 | 312 | 0.00% |
| DSP | 0 | 1,728 | 0.00% |

The synthesis console separately lists 1,923 LUT primitives (sum of LUT1 through LUT6); the utilization report's 1,688 CLB LUT figure accounts for LUT combining and is the value to use for device utilization. The core has 1,610 flip-flops.

For the 10 ns `core_clk` constraint, Vivado reports WNS=6.161 ns and TNS=0 ns, with zero failing endpoints and all user-specified timing constraints met. A reported maximum-delay path has 3.585 ns data-path delay and a 6.161 ns slack. Vivado labels the path type as setup at the slow process corner.

These timing and area figures are from the standalone core synthesis only. The report includes estimated interconnect delay; placement and routing were not run. External instruction/data and control I/O had no board-specific delay constraints or pin assignments in that measurement. Do not present these results as post-route timing, board performance, maximum operating frequency, or silicon measurements. A separate ZCU104 wrapper and implementation flow are documented below and in `docs/zcu104_demo.md`; its final clock-pin-corrected routed timing estimates and implementation utilization have been reviewed and are summarized separately.

The log notes removal of unused `idex_load_unsigned` and `exmem_load_unsigned` pipeline elements and `regs[0]`; removing the constant-zero register is expected. A floorplanning-quality warning notes that the flattened primitive netlist is not ideal for floorplanning; this did not prevent synthesis and is only relevant if floorplanning is later attempted.


## ZCU104 routed demo result

The user's Vivado 2026.1 implementation run for `rv32i_zcu104_top` on `xczu7ev-ffvc1156-2-e` completed routing and generated a bitstream. The reviewed reports show:

| Metric | Result |
|---|---:|
| Clock target | 8.000 ns (125 MHz) |
| Final clock-pin-corrected router estimate: setup WNS / TNS | 3.777 ns / 0 ns |
| Final clock-pin-corrected router estimate: hold WHS / THS | 0.021 ns / 0 ns |
| CLB LUTs | 760 (0.33%) |
| CLB registers | 1,088 (0.24%) |
| CARRY8 / F7 / F8 | 22 / 64 / 32 |
| DRC checks reported | 0 |

The final router log for the clock-pin-corrected implementation reported zero unrouted nets and the timing estimates listed above. One input and four outputs have no I/O delay constraints, so this is a routed result for the constrained clock paths, not complete external I/O timing signoff. An earlier implementation report showed WNS=3.887 ns and WPWS=3.725 ns; those results are superseded and are not combined with the final router estimates. The user separately programmed the final bitstream and observed the expected LED pattern. The board observation validates basic function; it does not establish silicon timing or performance.
