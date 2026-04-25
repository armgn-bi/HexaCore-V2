# ─────────────────────────────────────────────────────
# nexys_a7.xdc — Nexys A7-100T Constraint Dosyası
# Board: Digilent Nexys A7-100T (xc7a100tcsg324-1)
# ─────────────────────────────────────────────────────

# ══════════════════════════════════════════════════════
# Clock
# ══════════════════════════════════════════════════════
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports CLK100MHZ]

# ══════════════════════════════════════════════════════
# Reset
# ══════════════════════════════════════════════════════
set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports CPU_RESETN]

# ══════════════════════════════════════════════════════
# USB-UART (FTDI)
# ══════════════════════════════════════════════════════
set_property -dict {PACKAGE_PIN D4 IOSTANDARD LVCMOS33} [get_ports UART_RXD_OUT]
set_property -dict {PACKAGE_PIN C4 IOSTANDARD LVCMOS33} [get_ports UART_TXD_IN]

# ══════════════════════════════════════════════════════
# LED'ler
# ══════════════════════════════════════════════════════
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {LED[2]}]
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports {LED[3]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {LED[4]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {LED[5]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {LED[6]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {LED[7]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {LED[8]}]
set_property -dict {PACKAGE_PIN T15 IOSTANDARD LVCMOS33} [get_ports {LED[9]}]
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports {LED[10]}]
set_property -dict {PACKAGE_PIN T16 IOSTANDARD LVCMOS33} [get_ports {LED[11]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {LED[12]}]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports {LED[13]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {LED[14]}]
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports {LED[15]}]

# ══════════════════════════════════════════════════════
# Switch'ler
# ══════════════════════════════════════════════════════
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {SW[0]}]
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports {SW[1]}]
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports {SW[2]}]
set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS33} [get_ports {SW[3]}]

# ══════════════════════════════════════════════════════
# Pmod JA (I2C)
# ══════════════════════════════════════════════════════
set_property -dict {PACKAGE_PIN C17 IOSTANDARD LVCMOS33} [get_ports JA1]
set_property -dict {PACKAGE_PIN D17 IOSTANDARD LVCMOS33} [get_ports JA2]

# ══════════════════════════════════════════════════════
# Pmod JB (SPI)
# ══════════════════════════════════════════════════════
set_property -dict {PACKAGE_PIN U14 IOSTANDARD LVCMOS33} [get_ports JB1]
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports JB2]
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports JB3]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} [get_ports {JB4_7[0]}]
set_property -dict {PACKAGE_PIN V15 IOSTANDARD LVCMOS33} [get_ports {JB4_7[1]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {JB4_7[2]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {JB4_7[3]}]

# ══════════════════════════════════════════════════════
# Timing Constraints
# ══════════════════════════════════════════════════════
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
