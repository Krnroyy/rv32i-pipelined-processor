# ZCU104 PL clock: 125 MHz differential input; board schematic maps CLK_125_P/N to F23/E23.
set_property PACKAGE_PIN F23 [get_ports clk_125_p]
set_property PACKAGE_PIN E23 [get_ports clk_125_n]
set_property IOSTANDARD LVDS [get_ports {clk_125_p clk_125_n}]
create_clock -name clk_125 -period 8.000 -waveform {0.000 4.000} [get_ports clk_125_p]

# CPU reset pushbutton SW20 is active-high; GPIO LEDs are active-high.
set_property PACKAGE_PIN M11 [get_ports cpu_reset]
set_property IOSTANDARD LVCMOS33 [get_ports cpu_reset]

set_property PACKAGE_PIN D5 [get_ports {leds[0]}]
set_property PACKAGE_PIN D6 [get_ports {leds[1]}]
set_property PACKAGE_PIN A5 [get_ports {leds[2]}]
set_property PACKAGE_PIN B5 [get_ports {leds[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {leds[*]}]

# Reset is asynchronous and is synchronized before it reaches the core.
set_false_path -from [get_ports cpu_reset]
