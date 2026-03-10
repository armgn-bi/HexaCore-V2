// filepath: tb/soc_tb/tb_dsp_perf.sv
// ═══════════════════════════════════════════════════════════════
// DSP Performans Karşılaştırma Testbench'i
// CPU-only FIR vs DSP-accelerated FIR — Cycle-Accurate Measurement
//
// Kullanım:
//   Her test çalışmadan önce IMEM_FILE parametresi ilgili .mem
//   dosyasını gösterecek şekilde ayarlanır.
//
//   Program halt = "jal x0, 0" (PC sabit kalır) → testbench
//   cycle sayısını yakalar.
//
// Sonuç register'ları (register file'dan okunur):
//   x28 (t3) = N (işlenen sample sayısı)
//   x29 (t4) = test_type flag (0=CPU-only, 1=DSP-accelerated)
//   x30 (t5) = first output sample (doğrulama için)
//   x31 (t6) = last output sample (doğrulama için)
// ═══════════════════════════════════════════════════════════════
`timescale 1ns / 1ps

module tb_dsp_perf;
  import riscv_pkg::*;
  import axi_pkg::*;

  // ════════════════════════════════════════════════
  // Parameters — derleme zamanında ayarlanır
  // ════════════════════════════════════════════════
  parameter string IMEM_FILE   = "imem_perf.mem";
  parameter string TEST_LABEL  = "PERF_TEST";
  parameter int    EXPECTED_N  = 0;

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
  assign uart_rx       = 1'b1;
  assign spi_miso      = 1'b0;
  assign dsp_s_tdata   = '0;
  assign dsp_s_tvalid  = 1'b0;
  assign dsp_s_tlast   = 1'b0;
  assign dsp_m_tready  = 1'b0;

  pullup (i2c_sda);
  pullup (i2c_scl);

  soc_top #(
    .IMEM_INIT_FILE (IMEM_FILE),
    .DMEM_INIT_FILE ("dmem.mem"),
    .INT_DMEM_BYTES (131072)  // 128 KB — büyük testler için
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
  // Cycle Counter & Halt Detection
  // ════════════════════════════════════════════════
  int unsigned total_cycles;
  int unsigned exec_start_cycle;
  int unsigned exec_end_cycle;
  logic        exec_started;
  int          halt_count;

  // Phase tracking (v2 testler için — x1 register'ına yazılan marker'lar)
  int unsigned phase1_cycle;  // Marker 1: FIR / DSP+Copy start
  int unsigned phase2_cycle;  // Marker 2: Copy / Drain start
  int unsigned phase3_cycle;  // Marker 3: Done
  logic        phase1_seen, phase2_seen, phase3_seen;

  initial begin
    total_cycles    = 0;
    exec_start_cycle = 0;
    exec_end_cycle   = 0;
    exec_started     = 1'b0;
    halt_count       = 0;
    phase1_cycle = 0; phase2_cycle = 0; phase3_cycle = 0;
    phase1_seen = 0;  phase2_seen = 0;  phase3_seen = 0;
  end

  always @(posedge clk) begin
    if (rstn) begin
      total_cycles <= total_cycles + 1;

      if (update && !exec_started) begin
        exec_started     <= 1'b1;
        exec_start_cycle <= total_cycles;
      end
    end
  end

  // ════════════════════════════════════════════════
  // Phase Marker Detection (v2)
  // Program x1 (ra) register'ına 1,2,3 yazarak fazları işaretler
  // ════════════════════════════════════════════════
  always @(posedge clk) begin
    if (rstn && update && reg_addr == 5'd1) begin
      case (reg_data[2:0])
        3'd1: if (!phase1_seen) begin
          phase1_cycle <= total_cycles;
          phase1_seen  <= 1'b1;
          $display("");
          $display("[%0t] ╔═══════════════════════════════════════════════════╗", $time);
          $display("[%0t] ║  MARKER 1 — Faz 1 Basladi (cycle %0d)            ║", $time, total_cycles);
          $display("[%0t] ╚═══════════════════════════════════════════════════╝", $time);
        end
        3'd2: if (!phase2_seen) begin
          phase2_cycle <= total_cycles;
          phase2_seen  <= 1'b1;
          $display("");
          $display("[%0t] ╔═══════════════════════════════════════════════════╗", $time);
          $display("[%0t] ║  MARKER 2 — Faz 2 Basladi (cycle %0d)            ║", $time, total_cycles);
          $display("[%0t] ║  Faz 1 suresi: %0d cycle", $time, total_cycles - phase1_cycle);
          $display("[%0t] ╚═══════════════════════════════════════════════════╝", $time);
        end
        3'd3: if (!phase3_seen) begin
          phase3_cycle <= total_cycles;
          phase3_seen  <= 1'b1;
          $display("");
          $display("[%0t] ╔═══════════════════════════════════════════════════╗", $time);
          $display("[%0t] ║  MARKER 3 — Tum Islemler Tamamlandi (cycle %0d)  ║", $time, total_cycles);
          $display("[%0t] ║  Faz 2 suresi: %0d cycle", $time, total_cycles - phase2_cycle);
          $display("[%0t] ║  Toplam (M1→M3): %0d cycle", $time, total_cycles - phase1_cycle);
          $display("[%0t] ╚═══════════════════════════════════════════════════╝", $time);
        end
      endcase
    end
  end

  // ════════════════════════════════════════════════
  // Debug Monitor — Sadece ilk/son birkaç cycle logla (performans için)
  // ════════════════════════════════════════════════
  always @(posedge clk) begin
    if (rstn && update) begin
      if (total_cycles < 200 || (halt_count > 0))
        $display("[%0t] CYC=%0d PC=%08h INSTR=%08h rd=x%-2d val=%08h | MA=%08h MD=%08h wr=%b rd=%b",
                 $time, total_cycles, pc, instr, reg_addr, reg_data,
                 mem_addr, mem_data, mem_wrt, mem_rd);
    end
  end

  // AXI transaction izleme (ilk 1000 cycle)
  always @(posedge clk) begin
    if (rstn && total_cycles < 1000) begin
      // AXI Write monitor
      if (u_dut.u_axi_master.m_axi_awvalid_o && u_dut.u_axi_master.m_axi_awready_i)
        $display("[%0t] AXI-WR-ADDR: addr=%08h", $time, u_dut.u_axi_master.m_axi_awaddr_o);
      if (u_dut.u_axi_master.m_axi_wvalid_o && u_dut.u_axi_master.m_axi_wready_i)
        $display("[%0t] AXI-WR-DATA: data=%08h strb=%04b", $time,
                 u_dut.u_axi_master.m_axi_wdata_o, u_dut.u_axi_master.m_axi_wstrb_o);
      if (u_dut.u_axi_master.m_axi_bvalid_i && u_dut.u_axi_master.m_axi_bready_o)
        $display("[%0t] AXI-WR-RESP: bresp=%02b", $time, u_dut.u_axi_master.m_axi_bresp_i);

      // AXI Read monitor
      if (u_dut.u_axi_master.m_axi_arvalid_o && u_dut.u_axi_master.m_axi_arready_i)
        $display("[%0t] AXI-RD-ADDR: addr=%08h", $time, u_dut.u_axi_master.m_axi_araddr_o);
      if (u_dut.u_axi_master.m_axi_rvalid_i && u_dut.u_axi_master.m_axi_rready_o)
        $display("[%0t] AXI-RD-DATA: data=%08h rresp=%02b", $time,
                 u_dut.u_axi_master.m_axi_rdata_i, u_dut.u_axi_master.m_axi_rresp_i);
    end
  end

  // DSP filtre durumu izleme (ilk 1000 cycle)
  always @(posedge clk) begin
    if (rstn && total_cycles < 1000) begin
      if (u_dut.u_dsp_filter.filter_valid_in)
        $display("[%0t] DSP-FILTER-IN:  dataIn=%04h (signed=%0d)",
                 $time,
                 u_dut.u_dsp_filter.data_in_reg,
                 $signed(u_dut.u_dsp_filter.data_in_reg));
      if (u_dut.u_dsp_filter.filter_vout)
        $display("[%0t] DSP-FILTER-OUT: dataOut=%09h (signed=%0d) validOut=1",
                 $time,
                 u_dut.u_dsp_filter.filter_dout,
                 $signed(u_dut.u_dsp_filter.filter_dout));
    end
  end

  // Pipeline stall izleme (devre dışı — performans için)
  // always @(posedge clk) begin
  //   if (rstn && u_dut.u_core.ext_stall_w)
  //     $display("[%0t] PIPELINE-STALL: ext_stall active, PC frozen at %08h",
  //              $time, u_dut.u_core.pcF);
  // end

  // ════════════════════════════════════════════════
  // Halt Tespiti ve Sonuç Raporu
  // ════════════════════════════════════════════════
  localparam int TIMEOUT_CYCLES = 20_000_000;  // 20M cycle — 8192-sample CPU test için yeterli

  initial begin
    // Reset bitene kadar bekle
    @(posedge rstn);
    repeat (4) @(posedge clk);

    // Halt tespiti — PC sabit kaldığında (JAL x0,0)
    for (int i = 0; i < TIMEOUT_CYCLES; i++) begin
      @(posedge clk);
      // JAL x0,0 = 0x0000006F → PC yerinde sayar
      if (update && instr == 32'h0000_006F) begin
        halt_count++;
        if (halt_count >= 3) begin
          exec_end_cycle = total_cycles;
          $display("");
          $display("╔══════════════════════════════════════════════════════════╗");
          $display("║  PROGRAM HALT DETECTED                                 ║");
          $display("║  Halt PC     = 0x%08h                            ║", pc);
          $display("║  Total Cycle = %0d", total_cycles);
          $display("║  Exec Cycles = %0d (start=%0d, end=%0d)",
                   exec_end_cycle - exec_start_cycle,
                   exec_start_cycle, exec_end_cycle);
          $display("╚══════════════════════════════════════════════════════════╝");
          break;
        end
      end

      if (i == TIMEOUT_CYCLES - 1) begin
        $display("");
        $display("!!! TIMEOUT — Program %0d cycle icinde tamamlanamadi !!!", TIMEOUT_CYCLES);
        $display("    Son PC = 0x%08h, Son instr = 0x%08h", pc, instr);
      end
    end

    // Birkaç cycle daha bekle
    repeat (10) @(posedge clk);

    // ── Register dosyasından sonuçları oku ──────
    begin
      logic [31:0] reg_x28, reg_x29, reg_x30, reg_x31;
      int unsigned exec_cycles;
      int unsigned p1_cycles, p2_cycles, p_total;

      reg_x28 = u_dut.u_core.u_rf.regs[28];  // N (sample count)
      reg_x29 = u_dut.u_core.u_rf.regs[29];  // test_type (0=CPU, 1=DSP)
      reg_x30 = u_dut.u_core.u_rf.regs[30];  // first output
      reg_x31 = u_dut.u_core.u_rf.regs[31];  // last output

      exec_cycles = exec_end_cycle - exec_start_cycle;
      p1_cycles = (phase2_seen) ? (phase2_cycle - phase1_cycle) : 0;
      p2_cycles = (phase3_seen) ? (phase3_cycle - phase2_cycle) : 0;
      p_total   = (phase3_seen) ? (phase3_cycle - phase1_cycle) : 0;

      $display("");
      $display("==========================================================================");
      $display("               DSP PERFORMANS TEST RAPORU (v2 + Amdahl)                   ");
      $display("==========================================================================");
      $display("  Test Label     : %s", TEST_LABEL);
      $display("  IMEM File      : %s", IMEM_FILE);
      $display("  Test Type      : %s", (reg_x29 == 0) ? "CPU-SIRALI (FIR + Copy)" : "DSP-PARALEL (DSP FIR + CPU Copy)");
      $display("  Sample Count N : %0d", reg_x28);
      $display("--------------------------------------------------------------------------");
      $display("  CYCLE MEASUREMENT:");
      $display("    Exec Start   : cycle %0d", exec_start_cycle);
      $display("    Exec End     : cycle %0d", exec_end_cycle);
      $display("    Total Exec   : %0d cycles", exec_cycles);

      if (phase1_seen) begin
        $display("--------------------------------------------------------------------------");
        $display("  PHASE TIMING (Marker-based):");
        if (reg_x29 == 0) begin
          // CPU Sequential: Phase1=FIR, Phase2=Copy
          $display("    Faz 1 (FIR hesaplama)  : %0d cycles", p1_cycles);
          $display("    Faz 2 (Veri kopyalama) : %0d cycles", p2_cycles);
          $display("    Toplam (FIR + Copy)    : %0d cycles", p_total);
          if (p_total > 0) begin
            $display("    FIR orani (p)          : %0d / %0d = %f",
                     p1_cycles, p_total, real'(p1_cycles) / real'(p_total));
          end
        end else begin
          // DSP Parallel: Phase1=DSP+Copy interleaved, Phase2=Drain
          $display("    Faz 1 (DSP+Copy paralel): %0d cycles", p1_cycles);
          $display("    Faz 2 (DSP drain)       : %0d cycles", p2_cycles);
          $display("    Toplam (Paralel + Drain): %0d cycles", p_total);
        end
      end

      $display("--------------------------------------------------------------------------");
      $display("  OUTPUT VERIFICATION:");
      $display("    First Output : 0x%08h (%0d signed)", reg_x30, $signed(reg_x30));
      $display("    Last Output  : 0x%08h (%0d signed)", reg_x31, $signed(reg_x31));

      // ── Copy Doğrulama (v2 testler için) ──
      if (phase1_seen && reg_x28 > 0) begin
        int copy_errors;
        logic [31:0] src_val, dst_val;
        copy_errors = 0;
        $display("--------------------------------------------------------------------------");
        $display("  COPY VERIFICATION (copy_src[0x10000] -> copy_dst[0x18000]):");
        for (int ci = 0; ci < 5 && ci < reg_x28; ci++) begin
          src_val = {u_dut.u_core.u_dmem.mem[32'h10000 + ci*4 + 3],
                     u_dut.u_core.u_dmem.mem[32'h10000 + ci*4 + 2],
                     u_dut.u_core.u_dmem.mem[32'h10000 + ci*4 + 1],
                     u_dut.u_core.u_dmem.mem[32'h10000 + ci*4]};
          dst_val = {u_dut.u_core.u_dmem.mem[32'h18000 + ci*4 + 3],
                     u_dut.u_core.u_dmem.mem[32'h18000 + ci*4 + 2],
                     u_dut.u_core.u_dmem.mem[32'h18000 + ci*4 + 1],
                     u_dut.u_core.u_dmem.mem[32'h18000 + ci*4]};
          $display("    [%0d] src=0x%08h dst=0x%08h %s",
                   ci, src_val, dst_val,
                   (src_val === dst_val) ? "OK" : "MISMATCH!");
          if (src_val !== dst_val) copy_errors++;
        end
        // Son eleman
        if (reg_x28 > 5) begin
          int li;
          li = reg_x28 - 1;
          src_val = {u_dut.u_core.u_dmem.mem[32'h10000 + li*4 + 3],
                     u_dut.u_core.u_dmem.mem[32'h10000 + li*4 + 2],
                     u_dut.u_core.u_dmem.mem[32'h10000 + li*4 + 1],
                     u_dut.u_core.u_dmem.mem[32'h10000 + li*4]};
          dst_val = {u_dut.u_core.u_dmem.mem[32'h18000 + li*4 + 3],
                     u_dut.u_core.u_dmem.mem[32'h18000 + li*4 + 2],
                     u_dut.u_core.u_dmem.mem[32'h18000 + li*4 + 1],
                     u_dut.u_core.u_dmem.mem[32'h18000 + li*4]};
          $display("    [%0d] src=0x%08h dst=0x%08h %s",
                   li, src_val, dst_val,
                   (src_val === dst_val) ? "OK" : "MISMATCH!");
          if (src_val !== dst_val) copy_errors++;
        end
        $display("    Copy sonucu: %s (%0d hata)",
                 (copy_errors == 0) ? "PASS" : "FAIL", copy_errors);
      end

      if (reg_x28 != EXPECTED_N && EXPECTED_N != 0)
        $display("  WARNING: Sample count mismatch! Got %0d, expected %0d", reg_x28, EXPECTED_N);

      // Register dump
      $display("--------------------------------------------------------------------------");
      $display("  REGISTER FILE DUMP (non-zero):");
      for (int r = 1; r < 32; r++) begin
        if (u_dut.u_core.u_rf.regs[r] !== '0 && u_dut.u_core.u_rf.regs[r] !== 'x)
          $display("    x%-2d = 0x%08h (%0d)", r, u_dut.u_core.u_rf.regs[r],
                   $signed(u_dut.u_core.u_rf.regs[r]));
      end

      $display("==========================================================================");
      $display("  RESULT: %s | N=%0d | CYCLES=%0d",
               (reg_x29 == 0) ? "CPU" : "DSP", reg_x28, exec_cycles);
      if (phase1_seen)
        $display("  PHASES: P1=%0d | P2=%0d | TOTAL=%0d", p1_cycles, p2_cycles, p_total);
      $display("==========================================================================");

      // Makine-okunabilir satır (script parsing için)
      // Format: PERF_RESULT,mode,N,exec_cycles,label,first_out,last_out
      $display("PERF_RESULT,%s,%0d,%0d,%s,0x%08h,0x%08h",
               (reg_x29 == 0) ? "CPU" : "DSP",
               reg_x28, exec_cycles, TEST_LABEL, reg_x30, reg_x31);

      // V2 phase satırı (varsa)
      if (phase1_seen)
        $display("PERF_PHASES,%s,%0d,%0d,%0d,%0d",
                 (reg_x29 == 0) ? "CPU" : "DSP",
                 reg_x28, p1_cycles, p2_cycles, p_total);
    end

    $finish;
  end

  // ════════════════════════════════════════════════
  // Watchdog — Mutlak timeout
  // ════════════════════════════════════════════════
  initial begin
    #2_000_000_000;  // 2s sim time (büyük testler için)
    $display("!!! WATCHDOG TIMEOUT — 200ms !!!");
    $fatal;
  end

endmodule
