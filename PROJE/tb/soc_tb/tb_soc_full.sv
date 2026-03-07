// filepath: tb/soc_tb/tb_soc_full.sv
// Tam SoC Entegrasyon Testi
// RISC-V Core → AXI Master IF → Interconnect → Periferal (DMEM/UART/SPI/I2C/DSP)
// Gerçek instruction'lar (imem_soc_full.mem) ile tam veri yolu doğrulaması.
//
// Test senaryosu:
//   Faz 1: İç DMEM yazma/okuma → x10 = 0xAB
//   Faz 2: AXI DMEM yazma/okuma → x11 = 0x5A
//   Faz 3: UART STATUS okuma → x12 = 0x0A
//   Faz 4: SPI CTRL yazma/okuma → x13 = 0x41
//   Faz 5: I2C CTRL yazma/okuma → x14 = 0x01
//   Faz 6: DSP CTRL yazma/okuma → x15 = 0x01
//   Faz 7: AXI DMEM kalıcılık → x16 = 0x5A
`timescale 1ns / 1ps

module tb_soc_full;
  import riscv_pkg::*;
  import axi_pkg::*;

  // ════════════════════════════════════════════════
  // Clock & Reset
  // ════════════════════════════════════════════════
  logic clk, rstn;
  initial begin clk = 0; forever #5 clk = ~clk; end  // 100 MHz

  initial begin
    rstn = 1'b0;
    repeat (4) @(posedge clk);
    rstn = 1'b1;
  end

  // ════════════════════════════════════════════════
  // DUT: soc_top
  // ════════════════════════════════════════════════
  logic [XLEN-1:0] dbg_addr, dbg_data;
  logic            update;
  logic [XLEN-1:0] pc, instr;
  logic [4:0]      reg_addr;
  logic [XLEN-1:0] reg_data;
  logic [XLEN-1:0] mem_addr, mem_data;
  logic            mem_wrt, mem_rd;

  // Periferal bağlantı sinyalleri
  logic            uart_tx, uart_rx, uart_irq;
  logic            spi_sck, spi_mosi, spi_miso;
  logic [3:0]      spi_ss;
  wire             i2c_sda, i2c_scl;
  logic [31:0]     dsp_s_tdata;
  logic            dsp_s_tvalid, dsp_s_tready, dsp_s_tlast;
  logic [31:0]     dsp_m_tdata;
  logic            dsp_m_tvalid, dsp_m_tready, dsp_m_tlast;

  assign dbg_addr      = '0;
  assign uart_rx       = 1'b1;    // UART idle = high
  assign spi_miso      = 1'b0;    // SPI MISO — test SPI transferi yok, varsayılan
  assign dsp_s_tdata   = '0;
  assign dsp_s_tvalid  = 1'b0;
  assign dsp_s_tlast   = 1'b0;
  assign dsp_m_tready  = 1'b0;

  // I2C pull-up'lar  (tristate → varsayılan high)
  pullup (i2c_sda);
  pullup (i2c_scl);

  soc_top #(
    .IMEM_INIT_FILE ("imem_soc_full.mem"),
    .DMEM_INIT_FILE ("dmem.mem")
  ) u_dut (
    .clk_i          (clk),
    .rstn_i         (rstn),
    .dbg_addr_i     (dbg_addr),
    .dbg_data_o     (dbg_data),
    .update_o       (update),
    .pc_o           (pc),
    .instr_o        (instr),
    .reg_addr_o     (reg_addr),
    .reg_data_o     (reg_data),
    .mem_addr_o     (mem_addr),
    .mem_data_o     (mem_data),
    .mem_wrt_o      (mem_wrt),
    .mem_read_o     (mem_rd),
    .uart_tx_o      (uart_tx),
    .uart_rx_i      (uart_rx),
    .uart_irq_o     (uart_irq),
    .spi_sck_o      (spi_sck),
    .spi_mosi_o     (spi_mosi),
    .spi_miso_i     (spi_miso),
    .spi_ss_o       (spi_ss),
    .i2c_sda_io     (i2c_sda),
    .i2c_scl_io     (i2c_scl),
    .dsp_s_tdata_i  (dsp_s_tdata),
    .dsp_s_tvalid_i (dsp_s_tvalid),
    .dsp_s_tready_o (dsp_s_tready),
    .dsp_s_tlast_i  (dsp_s_tlast),
    .dsp_m_tdata_o  (dsp_m_tdata),
    .dsp_m_tvalid_o (dsp_m_tvalid),
    .dsp_m_tready_i (dsp_m_tready),
    .dsp_m_tlast_o  (dsp_m_tlast)
  );

  // ════════════════════════════════════════════════
  // Test Doğrulama
  // ════════════════════════════════════════════════
  // program sonsuz döngüye girdiğinde (PC sabit) doğrulama yapar.

  int test_pass = 0;
  int test_fail = 0;
  int test_num  = 0;

  task automatic check(
    input string name,
    input logic [31:0] got,
    input logic [31:0] expected
  );
    test_num++;
    if (got === expected) begin
      test_pass++;
      $display("[%0t] PASS #%0d %s — got=0x%08h", $time, test_num, name, got);
    end else begin
      test_fail++;
      $display("[%0t] FAIL #%0d %s — got=0x%08h expected=0x%08h",
               $time, test_num, name, got, expected);
    end
  endtask

  // ════════════════════════════════════════════════
  // Sonsuz döngü tespiti ve sonuç doğrulaması
  // ════════════════════════════════════════════════
  localparam int TIMEOUT_CYCLES = 5000;
  localparam logic [XLEN-1:0] HALT_PC = 32'h8000_0060;  // jal x0, 0 adresi

  logic [XLEN-1:0] prev_pc;
  int stable_count;

  initial begin
    prev_pc      = '0;
    stable_count = 0;

    // Reset bitene kadar bekle
    @(posedge rstn);
    repeat (4) @(posedge clk);

    // Program tamamlanmasını bekle (PC = HALT_PC sonsuz döngü adresi)
    // JAL x0,0 pipeline'da sürekli flush yarattığı için ardışık match aramak yerine
    // toplam 3 match yeterli sayılır (bubble cycle'lar arasında).
    for (int i = 0; i < TIMEOUT_CYCLES; i++) begin
      @(posedge clk);
      if (update && pc == HALT_PC) begin
        stable_count++;
        if (stable_count >= 3) begin
          $display("");
          $display("====================================================");
          $display(" Program sonsuz donguye girdi (PC=0x%08h)", pc);
          $display(" Calisma suresi: %0d cycle", i);
          $display("====================================================");
          break;
        end
      end
      // stable_count sıfırlanmaz — toplam sayılır

      if (i == TIMEOUT_CYCLES - 1) begin
        $display("");
        $display("====================================================");
        $display(" TIMEOUT! Program %0d cycle icinde tamamlanmadi", TIMEOUT_CYCLES);
        $display(" Son PC = 0x%08h", pc);
        $display("====================================================");
      end
    end

    // Birkaç cycle daha bekle (WB stage flush)
    repeat (10) @(posedge clk);

    // ── Register dosyasından sonuçları oku ──────
    // Hiyerarşik erişim: soc_top → u_core → u_rf → regs[]
    $display("");
    $display("====================================================");
    $display(" Tam SoC Entegrasyon Testi — Sonuc Dogrulamasi");
    $display("====================================================");

    // Faz 1: İç DMEM
    check("Faz1: Ic DMEM okuma (x10)",
          u_dut.u_core.u_rf.regs[10], 32'h0000_00AB);

    // Faz 2: AXI DMEM
    check("Faz2: AXI DMEM okuma (x11)",
          u_dut.u_core.u_rf.regs[11], 32'h0000_005A);

    // Faz 3: UART STATUS
    check("Faz3: UART STATUS (x12)",
          u_dut.u_core.u_rf.regs[12], 32'h0000_000A);

    // Faz 4: SPI CTRL
    check("Faz4: SPI CTRL readback (x13)",
          u_dut.u_core.u_rf.regs[13], 32'h0000_0041);

    // Faz 5: I2C CTRL
    check("Faz5: I2C CTRL readback (x14)",
          u_dut.u_core.u_rf.regs[14], 32'h0000_0001);

    // Faz 6: DSP CTRL
    check("Faz6: DSP CTRL readback (x15)",
          u_dut.u_core.u_rf.regs[15], 32'h0000_0001);

    // Faz 7: AXI DMEM kalıcılık
    check("Faz7: AXI DMEM kalicilik (x16)",
          u_dut.u_core.u_rf.regs[16], 32'h0000_005A);

    // ── Ek kontroller: Ara register'lar ──────────
    // x5 (son değer: 0x8001_0000 — Faz 7 lui)
    check("x5 son deger (0x80010000)",
          u_dut.u_core.u_rf.regs[5], 32'h8001_0000);

    // x6 (son değer: 0x01 — Faz 6 addi)
    check("x6 son deger (0x01)",
          u_dut.u_core.u_rf.regs[6], 32'h0000_0001);

    $display("");
    $display("====================================================");
    $display(" Tam SoC Testi TAMAMLANDI");
    $display(" Toplam: %0d  |  PASS: %0d  |  FAIL: %0d",
             test_num, test_pass, test_fail);
    $display("====================================================");

    if (test_fail > 0) begin
      $display("ENTEGRASYON TESTI BASARISIZ — %0d hata!", test_fail);
      $fatal;
    end else begin
      $display("[TB] TUM TESTLER BASARILI.");
    end

    $finish;
  end

  // ════════════════════════════════════════════════
  // Watchdog — mutlak timeout
  // ════════════════════════════════════════════════
  initial begin
    #500_000;  // 500 us
    $display("WATCHDOG TIMEOUT!");
    $fatal;
  end

  // ════════════════════════════════════════════════
  // Debug: her WB update'i logla (opsiyonel)
  // ════════════════════════════════════════════════
`ifdef DEBUG_MON
  always @(posedge clk) begin
    if (rstn && update) begin
      $display("[%0t] PC=%08h INSTR=%08h rd=x%0d val=%08h | mem_addr=%08h mem_data=%08h wr=%b rd=%b",
               $time, pc, instr, reg_addr, reg_data, mem_addr, mem_data, mem_wrt, mem_rd);
    end
  end
`endif

endmodule
