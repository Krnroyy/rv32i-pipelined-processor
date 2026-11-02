if {$argc != 4} {
    puts stderr "Usage: run_vivado_synthesis.tcl <repo_root> <part> <clock_period_ns> <report_dir>"
    exit 2
}

set repo_root [file normalize [lindex $argv 0]]
set part [lindex $argv 1]
set period_ns [lindex $argv 2]
set report_dir [file normalize [lindex $argv 3]]
set rtl_file [file join $repo_root rtl rv32i_core.sv]

if {![file exists $rtl_file]} {
    puts stderr "RTL source not found: $rtl_file"
    exit 2
}
if {![string is double -strict $period_ns] || $period_ns <= 0} {
    puts stderr "Clock period must be a positive number of nanoseconds: $period_ns"
    exit 2
}
file mkdir $report_dir

puts "INFO: Synthesizing rv32i_core for $part with a ${period_ns} ns clock target"
puts "INFO: Reports are estimates from synthesis; placement and routing are not run."

read_verilog -sv $rtl_file
set xdc_file [file join $report_dir core_clock.xdc]
set xdc [open $xdc_file w]
puts $xdc "create_clock -name core_clk -period $period_ns \[get_ports clk\]"
close $xdc
read_xdc $xdc_file
synth_design -top rv32i_core -part $part -flatten_hierarchy rebuilt

report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -report_unconstrained -file [file join $report_dir timing_summary.rpt]
report_timing -from [all_registers] -to [all_registers] -max_paths 25 -path_type full -file [file join $report_dir register_to_register_timing.rpt]
write_checkpoint -force [file join $report_dir rv32i_core_synth.dcp]

set report_file [open [file join $report_dir run_info.txt] w]
puts $report_file "Top: rv32i_core"
puts $report_file "Part: $part"
puts $report_file "Clock target: $period_ns ns ([expr {1000.0 / $period_ns}] MHz)"
puts $report_file "Vivado version: [version -short]"
puts $report_file "Flow: synth_design only; no placement, routing, board I/O constraints, or bitstream generation"
close $report_file

puts "PASS: Synthesis and reports completed. Review timing_summary.rpt for constrained and unconstrained paths."
exit 0
