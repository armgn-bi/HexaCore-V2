`timescale 1ns / 1ps
// ALINX AXU4EVB-P (xczu4ev-sfvc784-1-i) Zynq UltraScale+ Top-Level Wrapper
// 
// Connects board pins to soc_top:
//   - 200 MHz differential oscillator (AE5/AF5) -> sys_clk_p/n
//   - PL_KEY1 (AE14) -> Reset (active-low)
//   - PL_UART (AA11/AA10) -> uart_tx/rx
//   - PL_LED1 (AE15) -> update/heartbeat

module axu4evb_top (
  // ── System ──────────────────────────────────
  input  logic        sys_clk_p,       // AE5: 200 MHz diff clock
  input  logic        sys_clk_n,       // AF5: 200 MHz diff clock
  input  logic        PL_KEY1,         // AE14: Reset (active-low button)

  // ── UART ────────────────────────────────────
  output logic        PL_UART_TX,      // AA11: FPGA TX -> PC RX
  input  logic        PL_UART_RX,      // AA10: PC TX -> FPGA RX

  // ── LEDs ────────────────────────────────────
  output logic        PL_LED1          // AE15: Heartbeat
);

  // ════════════════════════════════════════════════
  // Clocking
  // ════════════════════════════════════════════════
  logic clk_200m;
  logic clk_100m;

  IBUFDS #(
    .DIFF_TERM("FALSE"),
    .IBUF_LOW_PWR("FALSE")
  ) ibufds_inst (
    .I(sys_clk_p),
    .IB(sys_clk_n),
    .O(clk_200m)
  );

  // Zynq UltraScale+ divide by 2 to get 100MHz
  BUFGCE_DIV #(
    .BUFGCE_DIVIDE(2)
  ) bufgce_div_inst (
    .I(clk_200m),
    .CE(1'b1),
    .CLR(1'b0),
    .O(clk_100m)
  );

  // ════════════════════════════════════════════════
  // Reset Synchronization
  // ════════════════════════════════════════════════
  logic rstn_ibuf;
  IBUF rstn_ibuf_inst (
    .I (PL_KEY1),
    .O (rstn_ibuf)
  );

  logic rstn_meta, rstn_sync;
  always_ff @(posedge clk_100m or negedge rstn_ibuf) begin
    if (!rstn_ibuf) begin
      rstn_meta <= 1'b0;
      rstn_sync <= 1'b0;
    end else begin
      rstn_meta <= 1'b1;
      rstn_sync <= rstn_meta;
    end
  end

  // ════════════════════════════════════════════════
  // SoC Instance
  // ════════════════════════════════════════════════
  logic [31:0] dbg_data;
  logic        update;
  logic [31:0] pc, instr;
  logic [4:0]  reg_addr;
  logic [31:0] reg_data, mem_addr, mem_data;
  logic        mem_wrt, mem_read_sig;
  logic        uart_tx, uart_irq;

  soc_top #(
    .IMEM_INIT_FILE ("C:/Users/DELL/Desktop/Yazilim/HexaCore-V2/PROJE/imem.mem"),
    .DMEM_INIT_FILE ("C:/Users/DELL/Desktop/Yazilim/HexaCore-V2/PROJE/dmem.mem")
  ) u_soc (
    .clk_i          (clk_100m),
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
    .uart_rx_i      (PL_UART_RX),
    .uart_irq_o     (uart_irq),

    // SPI (Tied off)
    .spi_sck_o      (),
    .spi_mosi_o     (),
    .spi_miso_i     (1'b0),
    .spi_ss_o       (),

    // I2C (Tied off)
    .i2c_sda_io     (),
    .i2c_scl_io     (),

    // DSP (Tied off)
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
  // Output Mapping
  // ════════════════════════════════════════════════
  logic uart_tx_int;
  logic led_int;

  always_ff @(posedge clk_100m) begin
    uart_tx_int <= uart_tx;
    led_int     <= update; // Heartbeat (update retires instruction)
  end

  OBUF uart_tx_obuf_inst (
    .I (uart_tx_int),
    .O (PL_UART_TX)
  );

  OBUF led_obuf_inst (
    .I (led_int),
    .O (PL_LED1)
  );

endmodule
