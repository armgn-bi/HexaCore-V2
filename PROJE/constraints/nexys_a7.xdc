## ─────────────────────────────────────────────────────
## nexys_a7.xdc — Nexys A7-100T Constraint Dosyasi
## Kart: Digilent Nexys A7-100T (xc7a100tcsg324-1)
## HexaCore-V2 SoC Projesi
## ─────────────────────────────────────────────────────

## ══════════════════════════════════════════════════════
## Clock — 100 MHz Osilator
## ══════════════════════════════════════════════════════
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }];
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports { CLK100MHZ }];

## ══════════════════════════════════════════════════════
## Reset — CPU_RESETN Butonu (Active-Low)
## ══════════════════════════════════════════════════════
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { CPU_RESETN }];

## ══════════════════════════════════════════════════════
## USB-UART Bridge (FTDI FT2232HQ)
## ══════════════════════════════════════════════════════
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { UART_RXD_OUT }];
set_property -dict { PACKAGE_PIN C4    IOSTANDARD LVCMOS33 } [get_ports { UART_TXD_IN }];

## ══════════════════════════════════════════════════════
## LED'ler (Active-High)
## ══════════════════════════════════════════════════════
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { LED[0] }];
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { LED[1] }];
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { LED[2] }];
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { LED[3] }];
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { LED[4] }];
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { LED[5] }];
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { LED[6] }];
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { LED[7] }];
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { LED[8] }];
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { LED[9] }];
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { LED[10] }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { LED[11] }];
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { LED[12] }];
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { LED[13] }];
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { LED[14] }];
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { LED[15] }];

## ══════════════════════════════════════════════════════
## Switch'ler (Active-High)
## ══════════════════════════════════════════════════════
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { SW[0] }];
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { SW[1] }];
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { SW[2] }];
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { SW[3] }];

## ══════════════════════════════════════════════════════
## Pmod Header JA — I2C (3.3V LVCMOS)
## Pin 1: SDA, Pin 2: SCL
## ══════════════════════════════════════════════════════
set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 } [get_ports { JA1 }];
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { JA2 }];

## ══════════════════════════════════════════════════════
## Pmod Header JB — SPI (3.3V LVCMOS)
## Pin 1: SCK, Pin 2: MOSI, Pin 3: MISO, Pin 4+7-9: SS[3:0]
## ══════════════════════════════════════════════════════
set_property -dict { PACKAGE_PIN D14   IOSTANDARD LVCMOS33 } [get_ports { JB1 }];
set_property -dict { PACKAGE_PIN F16   IOSTANDARD LVCMOS33 } [get_ports { JB2 }];
set_property -dict { PACKAGE_PIN G16   IOSTANDARD LVCMOS33 } [get_ports { JB3 }];
set_property -dict { PACKAGE_PIN H14   IOSTANDARD LVCMOS33 } [get_ports { JB4_7[0] }];
set_property -dict { PACKAGE_PIN E16   IOSTANDARD LVCMOS33 } [get_ports { JB4_7[1] }];
set_property -dict { PACKAGE_PIN F13   IOSTANDARD LVCMOS33 } [get_ports { JB4_7[2] }];
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { JB4_7[3] }];

## ══════════════════════════════════════════════════════
## Timing Constraints
## ══════════════════════════════════════════════════════

## Input delay (asenkron girisler icin, max 5ns varsayim)
set_input_delay -clock sys_clk_pin -max 5.000 [get_ports { CPU_RESETN UART_TXD_IN SW[*] JB3 }];
set_input_delay -clock sys_clk_pin -min 0.000 [get_ports { CPU_RESETN UART_TXD_IN SW[*] JB3 }];

## Output delay (LED ve UART icin, basit constraint)
set_output_delay -clock sys_clk_pin -max 5.000 [get_ports { LED[*] UART_RXD_OUT JB1 JB2 JB4_7[*] }];
set_output_delay -clock sys_clk_pin -min 0.000 [get_ports { LED[*] UART_RXD_OUT JB1 JB2 JB4_7[*] }];

## I2C bidirectional pinler icin false path (asenkron)
set_false_path -from [get_ports { JA1 JA2 }];
set_false_path -to   [get_ports { JA1 JA2 }];

## Reset false path (asenkron reset, timing analiz disinda)
set_false_path -from [get_ports { CPU_RESETN }];

## ══════════════════════════════════════════════════════
## Bitstream Konfigurasyonu
## ══════════════════════════════════════════════════════
set_property CFGBVS VCCO [current_design];
set_property CONFIG_VOLTAGE 3.3 [current_design];
