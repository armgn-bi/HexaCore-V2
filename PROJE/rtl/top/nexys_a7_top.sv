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
  // IO Buffering - Xilinx 7-series IO primitives
  // ════════════════════════════════════════════════

  // Clock Input Buffer
  logic clk_ibuf;
  IBUF clk_ibuf_inst (
    .I (CLK100MHZ),
    .O (clk_ibuf)
  );

  // Clock Buffering - Use BUFG for global clock distribution
  logic clk_buf;
  BUFG clk_bufg (
    .I (clk_ibuf),
    .O (clk_buf)
  );

  // Reset Input Buffer
  logic rstn_ibuf;
  IBUF rstn_ibuf_inst (
    .I (CPU_RESETN),
    .O (rstn_ibuf)
  );

  // UART Input Buffer
  logic uart_rx_ibuf;
  IBUF uart_rx_ibuf_inst (
    .I (UART_TXD_IN),
    .O (uart_rx_ibuf)
  );

  // Switch Input Buffers
  logic [3:0] sw_ibuf;
  genvar i;
  generate
    for (i = 0; i < 4; i = i + 1) begin : sw_buf_gen
      IBUF sw_ibuf_inst (
        .I (SW[i]),
        .O (sw_ibuf[i])
      );
    end
  endgenerate

  // SPI MISO Input Buffer
  logic jb3_ibuf;
  IBUF jb3_ibuf_inst (
    .I (JB3),
    .O (jb3_ibuf)
  );

  // ════════════════════════════════════════════════
  // Reset Senkronizasyonu (2-FF synchronizer)
  // Board butonu zaten active-low, dogrudan kullanalim
  // ama metastabilite icin 2 FF'den gecirelim.
  // ════════════════════════════════════════════════
  logic rstn_meta, rstn_sync;

  always_ff @(posedge clk_buf or negedge rstn_ibuf) begin
    if (!rstn_ibuf) begin
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
    .IMEM_INIT_FILE ("C:/Users/DELL/Downloads/HexaCore-V2/PROJE/imem.mem"),
    .DMEM_INIT_FILE ("C:/Users/DELL/Downloads/HexaCore-V2/PROJE/dmem.mem")
  ) u_soc (
    .clk_i          (clk_buf),      // Use buffered clock
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
    .uart_rx_i      (uart_rx_ibuf),  // Use buffered input
    .uart_irq_o     (uart_irq),

    // SPI
    .spi_sck_o      (spi_sck),
    .spi_mosi_o     (spi_mosi),
    .spi_miso_i     (jb3_ibuf),      // Use buffered input
    .spi_ss_o       (spi_ss),

    // I2C
    .i2c_sda_io     (JA1),  // Direct connection (IOBUF handles buffering)
    .i2c_scl_io     (JA2),  // Direct connection (IOBUF handles buffering)

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
  // Internal signals for output buffering
  logic uart_tx_int, jb1_int, jb2_int;
  logic [3:0] jb4_7_int;

  // Output registers for proper IO buffering
  always_ff @(posedge clk_buf) begin
    uart_tx_int <= uart_tx;
    jb1_int     <= spi_sck;
    jb2_int     <= spi_mosi;
    jb4_7_int   <= spi_ss;
  end

  // Output Buffers
  OBUF uart_tx_obuf_inst (
    .I (uart_tx_int),
    .O (UART_RXD_OUT)
  );

  OBUF jb1_obuf_inst (
    .I (jb1_int),
    .O (JB1)
  );

  OBUF jb2_obuf_inst (
    .I (jb2_int),
    .O (JB2)
  );

  genvar j;
  generate
    for (j = 0; j < 4; j = j + 1) begin : jb4_7_buf_gen
      OBUF jb4_7_obuf_inst (
        .I (jb4_7_int[j]),
        .O (JB4_7[j])
      );
    end
  endgenerate

  // ════════════════════════════════════════════════
  // LED Atamalari
  // ════════════════════════════════════════════════
  // LED[0]     : update (pipeline retire sinyali, heartbeat)
  // LED[1]     : UART IRQ
  // LED[3:2]   : (reserved)
  // LED[7:4]   : PC[5:2] (instruction address low bits)
  // LED[11:8]  : SW echo (switch degerlerini yansit)
  // LED[15:12] : reg_addr (son yazilan register)

  // Intermediate signals to avoid direct IO-to-IO connections
  logic [15:0] led_int;

  // Combinational logic for LED values
  always_comb begin
    led_int[0]     = update;
    led_int[1]     = uart_irq;
    led_int[3:2]   = 2'b00;
    led_int[7:4]   = pc[5:2];
    led_int[11:8]  = sw_ibuf;      // Use buffered switch values
    led_int[15:12] = {reg_addr[3:0]};
  end

  // Output registers for proper IO buffering
  logic [15:0] led_reg;
  always_ff @(posedge clk_buf) begin
    led_reg <= led_int;
  end

  // LED Output Buffers
  genvar k;
  generate
    for (k = 0; k < 16; k = k + 1) begin : led_buf_gen
      OBUF led_obuf_inst (
        .I (led_reg[k]),
        .O (LED[k])
      );
    end
  endgenerate

endmodule
