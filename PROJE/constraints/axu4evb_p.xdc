# ALINX AXU4EVB-P (xczu4ev-sfvc784-1-i) Constraints
# Reference: MEGA_VIVADO_INSTRUCTIONS.md

# 200 MHz Differential PL System Clock (Bank 64)
set_property PACKAGE_PIN AE5 [get_ports sys_clk_p]
set_property PACKAGE_PIN AF5 [get_ports sys_clk_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports sys_clk_n]
create_clock -period 5.000 -name sys_clk -waveform {0.000 2.500} [get_ports sys_clk_p]

# PL Key (Button, Active Low, Bank 44)
set_property PACKAGE_PIN AE14 [get_ports PL_KEY1]
set_property IOSTANDARD LVCMOS33 [get_ports PL_KEY1]

# PL LED (Bank 44)
set_property PACKAGE_PIN AE15 [get_ports PL_LED1]
set_property IOSTANDARD LVCMOS33 [get_ports PL_LED1]

# PL UART (Bank 43)
set_property PACKAGE_PIN AA11 [get_ports PL_UART_TX]
set_property IOSTANDARD LVCMOS33 [get_ports PL_UART_TX]
set_property PACKAGE_PIN AA10 [get_ports PL_UART_RX]
set_property IOSTANDARD LVCMOS33 [get_ports PL_UART_RX]
