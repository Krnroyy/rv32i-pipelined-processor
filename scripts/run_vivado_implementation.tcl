if {$argc != 3} {
    puts stderr "Usage: run_vivado_implementation.tcl <repo_root> <part> <report_dir>"
    exit 2
}

set repo_root [file normalize [lindex $argv 0]]
set part [lindex $argv 1]
set report_dir [file normalize [lindex $argv 2]]
set rtl_core [file join $repo_root rtl rv32i_core.sv]
set rtl_system [file join $repo_root rtl rv32i_demo_system.sv]
set rtl_top [file join $repo_root rtl rv32i_zcu104_top.sv]
set xdc_file [file join $repo_root constraints zcu104_demo.xdc]

foreach source_file [list $rtl_core $rtl_system $rtl_top $xdc_file] {
    if {![file exists $source_file]} {
        puts stderr "Required source/constraint file not found: $source_file"
        exit 2
    }
}
file mkdir $report_dir

puts "INFO: Building the ZCU104 RV32I demo for $part"
puts "INFO: This flow runs synthesis, placement, physical optimization, and routing."

read_verilog -sv $rtl_core $rtl_system $rtl_top
read_xdc $xdc_file
synth_design -top rv32i_zcu104_top -part $part -flatten_hierarchy rebuilt
opt_design
place_design
phys_opt_design
route_design

report_utilization -file [file join $report_dir utilization_post_route.rpt]
report_timing_summary -delay_type max -report_unconstrained -file [file join $report_dir timing_post_route.rpt]
report_timing -max_paths 25 -path_type full -file [file join $report_dir critical_paths_post_route.rpt]
report_drc -file [file join $report_dir drc_post_route.rpt]
write_checkpoint -force [file join $report_dir rv32i_zcu104_routed.dcp]
write_bitstream -force [file join $report_dir rv32i_zcu104_demo.bit]

set info [open [file join $report_dir run_info.txt] w]
puts $info "Top: rv32i_zcu104_top"
puts $info "Part: $part"
puts $info "Board: ZCU104"
puts $info "Clock: 125 MHz differential CLK_125 input, 8.000 ns period"
puts $info "Flow: synthesis, opt_design, place_design, phys_opt_design, route_design"
puts $info "Vivado: [version -short]"
puts $info "I/O: clock/reset/LED package pins assigned; no external LED timing budget; CPU reset false-pathed as asynchronous synchronized reset"
close $info

puts "PASS: ZCU104 implementation, routed reports, checkpoint, and bitstream generated. Review DRC and timing reports before programming the board."
exit 0
