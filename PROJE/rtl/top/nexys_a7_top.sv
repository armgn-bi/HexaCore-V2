// filepath: rtl/top/nexys_a7_top.sv
// Nexys A7-100T FPGA Top-Level Wrapper
// Board: Digilent Nexys A7-100T (xc7a100tcsg324-1)
//
// Bu modul board pinlerini soc_top'a baglar:
//   - 100 MHz board oscillator -> clk_i
//   - CPU_RESETN butonu -> rstn_i (active-low)
//   - USB-UART bridge (FTDI) -> uart_tx/rx
//   - LED[15:0] -> durum gostergeleri
//   - SW[3:0] -> opsiyonel giris
`timescale 1ns / 1ps

module nexys_a7_top (
  // ── Sistem ──────────────────────────────────
  input  logic        CLK100MHZ,       // E3: 100 MHz osilator
  input  logic        CPU_RESETN,      // C12: Reset (active-low)

  // ── USB-UART Bridge ─────────────────────────
  output logic        UART_RXD_OUT,    // D4: FPGA TX -> PC RX
  input  logic        UART_TXD_IN,     // C4: PC TX -> FPGA RX

  // ── LED'ler ─────────────────────────────────
  output logic [15:0] LED,

  // ── Switch'ler ──────────────────────────────
  input  logic [3:0]  SW,

  // ── I2C (Pmod Header JA) ───────────────────
  inout  wire         JA1,             // I2C SDA (Pmod JA pin 1)
  inout  wire         JA2,             // I2C SCL (Pmod JA pin 2)

  // ── SPI (Pmod Header JB) ───────────────────
  output logic        JB1,             // SPI SCK  (Pmod JB pin 1)
  output logic        JB2,             // SPI MOSI (Pmod JB pin 2)
  input  logic        JB3,             // SPI MISO (Pmod JB pin 3)
  output logic [3:0]  JB4_7            // SPI SS[3:0] (Pmod JB pins 4,7,8,9)
);

  // ════════════════════════════════════════════════
  // Reset Senkronizasyonu (2-FF synchronizer)
  // Board butonu zaten active-low, dogrudan kullanalim
  // ama metastabilite icin 2 FF'den gecirelim.
  // ════════════════════════════════════════════════
  logic rstn_meta, rstn_sync;

  always_ff @(posedge CLK100MHZ or negedge CPU_RESETN) begin
    if (!CPU_RESETN) begin
      rstn_meta <= 1'b0;
      rstn_sync <= 1'b0;
    end else begin
      rstn_meta <= 1'b1;
      rstn_sync <= rstn_meta;
    end
  end

  // ════════════════════════════════════════════════
  // SoC dahili sinyaller
  // ════════════════════════════════════════════════
  logic [31:0] dbg_data;
  logic        update;
  logic [31:0] pc, instr;
  logic [4:0]  reg_addr;
  logic [31:0] reg_data, mem_addr, mem_data;
  logic        mem_wrt, mem_read_sig;
  logic        uart_tx, uart_irq;
  logic        spi_sck, spi_mosi;
  logic [3:0]  spi_ss;

  // ════════════════════════════════════════════════
  // SoC Instance
  // ════════════════════════════════════════════════
  soc_top #(
    .IMEM_INIT_FILE ("imem.mem"),
    .DMEM_INIT_FILE ("dmem.mem")
  ) u_soc (
    .clk_i          (CLK100MHZ),
    .rstn_i         (rstn_sync),

    // Debug / Scoreboard
    .dbg_addr_i     (32'h0000_0000),
    .dbg_data_o     (dbg_data),
    .update_o       (update),
    .pc_o           (pc),
    .instr_o        (instr),
    .reg_addr_o     (reg_addr),
    .reg_data_o     (reg_data),
    .mem_addr_o     (mem_addr),
    .mem_data_o     (mem_data),
    .mem_wrt_o      (mem_wrt),
    .mem_read_o     (mem_read_sig),

    // UART
    .uart_tx_o      (uart_tx),
    .uart_rx_i      (UART_TXD_IN),
    .uart_irq_o     (uart_irq),

    // SPI
    .spi_sck_o      (spi_sck),
    .spi_mosi_o     (spi_mosi),
    .spi_miso_i     (JB3),
    .spi_ss_o       (spi_ss),

    // I2C
    .i2c_sda_io     (JA1),
    .i2c_scl_io     (JA2),

    // DSP AXI-Stream (kullanilmiyor, idle)
    .dsp_s_tdata_i  (32'd0),
    .dsp_s_tvalid_i (1'b0),
    .dsp_s_tready_o (),
    .dsp_s_tlast_i  (1'b0),
    .dsp_m_tdata_o  (),
    .dsp_m_tvalid_o (),
    .dsp_m_tready_i (1'b0),
    .dsp_m_tlast_o  ()
  );

  // ════════════════════════════════════════════════
  // Pin Atamalari
  // ════════════════════════════════════════════════
  assign UART_RXD_OUT = uart_tx;

  // SPI -> Pmod JB
  assign JB1   = spi_sck;
  assign JB2   = spi_mosi;
  assign JB4_7 = spi_ss;

  // ════════════════════════════════════════════════
  // LED Atamalari
  // ════════════════════════════════════════════════
  // LED[0]     : update (pipeline retire sinyali, heartbeat)
  // LED[1]     : UART IRQ
  // LED[3:2]   : (reserved)
  // LED[7:4]   : PC[5:2] (instruction address low bits)
  // LED[11:8]  : SW echo (switch degerlerini yansit)
  // LED[15:12] : reg_addr (son yazilan register)
  assign LED[0]     = update;
  assign LED[1]     = uart_irq;
  assign LED[3:2]   = 2'b00;
  assign LED[7:4]   = pc[5:2];
  assign LED[11:8]  = SW;
  assign LED[15:12] = {reg_addr[3:0]};

endmodule
