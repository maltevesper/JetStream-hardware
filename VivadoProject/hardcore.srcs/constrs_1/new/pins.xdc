#the magic clock
#set_property IOSTANDARD LVCMOS18 [get_ports emcclk]
#set_property PACKAGE_PIN AP37 [get_ports emcclk]

#bitstream and other shit UNDERSTAND IT
set_property BITSTREAM.CONFIG.BPI_SYNC_MODE Type1 [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN div-1 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pulldown [current_design]
set_property CONFIG_MODE BPI16 [current_design]
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]

#led pins

set_property PACKAGE_PIN AM39 [get_ports {leds[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[0]}]
set_property PACKAGE_PIN AN39 [get_ports {leds[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[1]}]
set_property PACKAGE_PIN AR37 [get_ports {leds[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[2]}]
set_property PACKAGE_PIN AT37 [get_ports {leds[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[3]}]
set_property PACKAGE_PIN AR35 [get_ports {leds[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[4]}]
set_property PACKAGE_PIN AP41 [get_ports {leds[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[5]}]
set_property PACKAGE_PIN AP42 [get_ports {leds[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[6]}]
set_property PACKAGE_PIN AU39 [get_ports {leds[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {leds[7]}]

#pushButton
set_property PACKAGE_PIN AV39 [get_ports centerButton]
set_property IOSTANDARD LVCMOS18 [get_ports centerButton]

###################################################
# falsePaths                                      #
###################################################
set_false_path -to [get_ports -filter {NAME=~leds[*]}]

#reset
set_false_path -from [get_ports sys_reset_n]

#local reset (had no effect)
set_false_path -through [get_pins -include_replicated_objects pciBaseSystem/pcieRegister/reset_reg_reg*/Q]

#pcieCore status information
set_false_path -through [get_pins -include_replicated_objects pciBaseSystem/pcie3x8_core/cfg_max_payload]
set_false_path -through [get_pins -include_replicated_objects pciBaseSystem/pcie3x8_core/cfg_max_read_req]
set_false_path -through [get_pins -include_replicated_objects pciBaseSystem/pcie3x8_core/cfg_negotiated_width]
set_false_path -through [get_pins -include_replicated_objects pciBaseSystem/pcie3x8_core/cfg_current_speed]

#set_false_path -through [get_nets pciBaseSystem/arbiter/cfg_max_payload*]
#set_false_path -through [get_nets pciBaseSystem/arbiter/cfg_max_read_req*]

set_false_path -through [get_nets -hierarchical cfg_max_payload*]
set_false_path -through [get_nets -hierarchical cfg_max_read_req*]

###################################################
# end falsePaths                                  #
###################################################

#clock pins

#Constrains the IBUF for sysclk (CAN NOT CONSTRAIN BOTH, EITHER CONSTRAIN BUFG OR THE SYS_CLK_P/N)
set_property LOC IBUFDS_GTE2_X1Y11 [get_cells pciBaseSystem/refclk_ibuf]

#constrains the sysclk to the onboard fixed 200mhz clk
#set_property LOC H19 [get_ports sys_clk_p]
#set_property IOSTANDARD DIFF_SSTL15_DCI [get_ports sys_clk_p]

#set_property LOC G18 [get_ports sys_clk_n]
#set_property IOSTANDARD DIFF_SSTL15_DCI [get_ports sys_clk_n]

create_clock -period 10.000 -name sys_clk [get_ports sys_clk_p]


#reset pin

# SYS reset (input) signal.  The sys_reset_n signal should be
# obtained from the PCI Express interface if possible.  For
# slot based form factors, a system reset signal is usually
# present on the connector.  For cable based form factors, a
# system reset signal may not be available.  In this case, the
# system reset signal must be generated locally by some form of
# supervisory circuit.  You may change the IOSTANDARD and LOC
# to suit your requirements and VCCO voltage banking rules.
# Some 7 series devices do not have 3.3 V I/Os available.
# Therefore the appropriate level shift is required to operate
# with these devices that contain only 1.8 V banks.
#

#THE BELLOW LINES ARE FROM XILINX, CHECK THEM!
set_property PACKAGE_PIN AV35 [get_ports sys_reset_n]
set_property IOSTANDARD LVCMOS18 [get_ports sys_reset_n]
set_property PULLUP true [get_ports sys_reset_n]

#set_property PACKAGE_PIN AV40 [get_ports sys_reset_n]
#set_property IOSTANDARD LVCMOS18 [get_ports sys_reset_n]




