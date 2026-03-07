// filepath: tb/soc_tb/tb_soc_system.sv
// ═══════════════════════════════════════════════════════════════
// Kapsamlı SoC Sistem Testi
// ═══════════════════════════════════════════════════════════════
// RISC-V Core → AXI Bus → Tüm Periferaller
//   • İç DMEM + AXI DMEM çoklu pattern ve kalıcılık
//   • UART TX→RX loopback (gerçek seri veri yolu)
//   • SPI full-duplex transfer (Mode 0, slave BFM)
//   • I2C yazma transaction (START+WRITE+WRITE+STOP, slave BFM, polling)
//   • DSP register erişimi
//   • Cross-peripheral veri taşıma (periph→AXI_DMEM→readback)
//   • Hızlı periferal geçişleri
//
// Test programı: imem_soc_sys.mem (112 RISC-V talimatı, 22 doğrulama)
// BFM'ler: UART loopback, SPI slave (init 0x5A), I2C slave (addr 0x50)
`timescale 1ns / 1ps

module tb_soc_system;
  import riscv_pkg::*;
  import axi_pkg::*;

  // ════════════════════════════════════════════════════════════
  // Clock & Reset
  // ════════════════════════════════════════════════════════════
  logic clk, rstn;
  initial begin clk = 0; forever #5 clk = ~clk; end  // 100 MHz (T=10ns)

  initial begin
    rstn = 1'b0;
    repeat (4) @(posedge clk);
    rstn = 1'b1;
  end

  // ════════════════════════════════════════════════════════════
  // DUT Sinyalleri
  // ════════════════════════════════════════════════════════════
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
  assign dsp_s_tdata   = '0;
  assign dsp_s_tvalid  = 1'b0;
  assign dsp_s_tlast   = 1'b0;
  assign dsp_m_tready  = 1'b0;

  // ════════════════════════════════════════════════════════════
  // UART Loopback: uart_tx → uart_rx
  // ════════════════════════════════════════════════════════════
  assign uart_rx = uart_tx;

  // ════════════════════════════════════════════════════════════
  // I2C Pull-up'lar
  // ════════════════════════════════════════════════════════════
  pullup (i2c_sda);
  pullup (i2c_scl);

  // ════════════════════════════════════════════════════════════
  // DUT: soc_top
  // ════════════════════════════════════════════════════════════
  soc_top #(
    .IMEM_INIT_FILE ("imem_soc_sys.mem"),
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

  // ════════════════════════════════════════════════════════════
  // SPI Slave BFM (Mode 0: CPOL=0, CPHA=0)
  // Shift register init = 0x5A
  // ════════════════════════════════════════════════════════════
  logic [7:0] spi_slv_shift;
  logic       spi_mosi_sampled;

  initial begin
    spi_slv_shift   = 8'h5A;
    spi_miso         = 1'b1;          // idle high (MISO tri-state yanıtı)
    spi_mosi_sampled = 1'b0;
  end

  // CS aktif olduğunda ilk MSB'yi sürerek başla
  always @(negedge spi_ss[0]) begin
    spi_miso <= spi_slv_shift[7];
  end

  // CS pasif olduğunda MISO'yu serbest bırak
  always @(posedge spi_ss[0]) begin
    spi_miso <= 1'b1;
  end

  // Mode 0: Rising edge'de MOSI örnekle
  always @(posedge spi_sck) begin
    if (!spi_ss[0])
      spi_mosi_sampled <= spi_mosi;
  end

  // Mode 0: Falling edge'de kaydır + yeni MSB süre
  always @(negedge spi_sck) begin
    if (!spi_ss[0]) begin
      spi_slv_shift <= {spi_slv_shift[6:0], spi_mosi_sampled};
      spi_miso      <= spi_slv_shift[6];  // shift sonrası [7] = eski [6]
    end
  end

  // ════════════════════════════════════════════════════════════
  // I2C Slave BFM (Addr = 0x50, Write-only ACK)
  // ════════════════════════════════════════════════════════════
  localparam [6:0] I2C_SLV_ADDR = 7'h50;

  // Slave SDA open-drain sürücüsü
  logic i2c_slv_sda_oe;
  initial i2c_slv_sda_oe = 1'b0;
  assign i2c_sda = i2c_slv_sda_oe ? 1'b0 : 1'bz;

  // Edge detection
  logic scl_d, sda_d;
  wire  scl_rise = i2c_scl & ~scl_d;
  wire  scl_fall = ~i2c_scl & scl_d;

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      scl_d <= 1'b1;
      sda_d <= 1'b1;
    end else begin
      scl_d <= i2c_scl;
      sda_d <= i2c_sda;
    end
  end

  // START/STOP detection
  wire i2c_start_det = sda_d & ~i2c_sda & i2c_scl;   // SDA ↓ while SCL high
  wire i2c_stop_det  = ~sda_d & i2c_sda & i2c_scl;   // SDA ↑ while SCL high

  // Slave FSM
  typedef enum logic [3:0] {
    SLV_IDLE       = 4'd0,
    SLV_ADDR_BIT   = 4'd1,
    SLV_ADDR_ACK1  = 4'd2,
    SLV_ADDR_ACK2  = 4'd3,
    SLV_WR_BIT     = 4'd4,
    SLV_WR_ACK1    = 4'd5,
    SLV_WR_ACK2    = 4'd6,
    SLV_STOP_WAIT  = 4'd7
  } i2c_slv_state_t;

  i2c_slv_state_t slv_state;
  logic [7:0] slv_rx_shift;
  logic [3:0] slv_bit_cnt;
  logic       slv_addr_match;

  // I2C Slave BFM — internal memory (4 byte)
  logic [7:0] slv_mem [0:3];
  logic [1:0] slv_mem_ptr;

  initial begin
    slv_state      = SLV_IDLE;
    slv_rx_shift   = 8'd0;
    slv_bit_cnt    = 4'd0;
    slv_addr_match = 1'b0;
    slv_mem_ptr    = 2'd0;
    slv_mem[0]     = 8'h00;
    slv_mem[1]     = 8'h00;
    slv_mem[2]     = 8'h00;
    slv_mem[3]     = 8'h00;
  end

  always @(posedge clk) begin
    if (!rstn) begin
      slv_state      <= SLV_IDLE;
      i2c_slv_sda_oe <= 1'b0;
      slv_bit_cnt    <= 4'd0;
      slv_addr_match <= 1'b0;
      slv_mem_ptr    <= 2'd0;
    end else begin

      // START condition — herhangi state'den yakalanır
      if (i2c_start_det) begin
        slv_state   <= SLV_ADDR_BIT;
        slv_bit_cnt <= 4'd7;
        i2c_slv_sda_oe <= 1'b0;
      end

      // STOP condition
      else if (i2c_stop_det) begin
        slv_state      <= SLV_IDLE;
        i2c_slv_sda_oe <= 1'b0;
      end

      else begin
        case (slv_state)

          SLV_IDLE: begin
            i2c_slv_sda_oe <= 1'b0;
          end

          // ── Adres byte'ı alma (8 bit: 7-bit addr + R/W) ──
          SLV_ADDR_BIT: begin
            if (scl_rise) begin
              slv_rx_shift <= {slv_rx_shift[6:0], i2c_sda};
              if (slv_bit_cnt == 0) begin
                // Tüm 8 bit alındı — adres kontrolü
                slv_addr_match <= ({slv_rx_shift[6:0], i2c_sda} >> 1) == I2C_SLV_ADDR;
                slv_state      <= SLV_ADDR_ACK1;
              end else begin
                slv_bit_cnt <= slv_bit_cnt - 1;
              end
            end
          end

          // ACK: SCL düşerken SDA'yı low süre
          SLV_ADDR_ACK1: begin
            if (scl_fall) begin
              if (slv_addr_match)
                i2c_slv_sda_oe <= 1'b1;   // ACK = drive low
              else
                i2c_slv_sda_oe <= 1'b0;   // NACK = release
              slv_state <= SLV_ADDR_ACK2;
            end
          end

          // ACK phase 2: sonraki SCL düşüşünde SDA'yı serbest bırak
          SLV_ADDR_ACK2: begin
            if (scl_fall) begin
              i2c_slv_sda_oe <= 1'b0;     // release SDA
              if (slv_addr_match) begin
                slv_state   <= SLV_WR_BIT;
                slv_bit_cnt <= 4'd7;
                slv_mem_ptr <= 2'd0;
              end else begin
                slv_state <= SLV_STOP_WAIT;
              end
            end
          end

          // ── Veri byte'ı alma (8 bit) ──
          SLV_WR_BIT: begin
            if (scl_rise) begin
              slv_rx_shift <= {slv_rx_shift[6:0], i2c_sda};
              if (slv_bit_cnt == 0) begin
                // Byte tamamlandı — belleğe yaz
                slv_mem[slv_mem_ptr] <= {slv_rx_shift[6:0], i2c_sda};
                slv_mem_ptr          <= slv_mem_ptr + 1;
                slv_state            <= SLV_WR_ACK1;
              end else begin
                slv_bit_cnt <= slv_bit_cnt - 1;
              end
            end
          end

          // Data ACK: SCL düşerken SDA low
          SLV_WR_ACK1: begin
            if (scl_fall) begin
              i2c_slv_sda_oe <= 1'b1;   // ACK
              slv_state <= SLV_WR_ACK2;
            end
          end

          // Data ACK phase 2: sonraki SCL düşüşünde release
          SLV_WR_ACK2: begin
            if (scl_fall) begin
              i2c_slv_sda_oe <= 1'b0;
              slv_state   <= SLV_WR_BIT;
              slv_bit_cnt <= 4'd7;
            end
          end

          SLV_STOP_WAIT: begin
            i2c_slv_sda_oe <= 1'b0;
            // STOP condition yukarıda yakalanıyor
          end

          default: slv_state <= SLV_IDLE;

        endcase
      end
    end
  end

  // ════════════════════════════════════════════════════════════
  // Test Altyapısı
  // ════════════════════════════════════════════════════════════
  int test_pass = 0;
  int test_fail = 0;
  int test_num  = 0;

  task automatic check(
    input string   name,
    input [31:0]   got,
    input [31:0]   expected
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

  // ════════════════════════════════════════════════════════════
  // Halt Detection + Doğrulama
  // ════════════════════════════════════════════════════════════
  localparam int TIMEOUT_CYCLES = 50000;
  localparam logic [XLEN-1:0] HALT_PC = 32'h8000_01C0;

  int halt_count;

  initial begin
    halt_count = 0;

    @(posedge rstn);
    repeat (4) @(posedge clk);

    for (int i = 0; i < TIMEOUT_CYCLES; i++) begin
      @(posedge clk);
      if (update && pc == HALT_PC) begin
        halt_count++;
        if (halt_count >= 3) begin
          $display("");
          $display("╔═══════════════════════════════════════════════════╗");
          $display("║  Program sonsuz döngüye girdi (PC=0x%08h)  ║", pc);
          $display("║  Çalışma süresi: %0d cycle                       ║", i);
          $display("╚═══════════════════════════════════════════════════╝");
          break;
        end
      end

      if (i == TIMEOUT_CYCLES - 1) begin
        $display("");
        $display("╔═══════════════════════════════════════════════════╗");
        $display("║  TIMEOUT! %0d cycle içinde tamamlanmadı           ║", TIMEOUT_CYCLES);
        $display("║  Son PC = 0x%08h                             ║", pc);
        $display("╚═══════════════════════════════════════════════════╝");
      end
    end

    repeat (10) @(posedge clk);

    // ──────────────────────────────────────────────────────────
    // Register Doğrulama: register_file[x10..x31]
    // ──────────────────────────────────────────────────────────
    $display("");
    $display("╔═══════════════════════════════════════════════════╗");
    $display("║  KAPSAMLI SoC SİSTEM TESTİ — DOĞRULAMA           ║");
    $display("╚═══════════════════════════════════════════════════╝");

    // ── Faz 1: İç DMEM ────────────────────────────
    $display("");
    $display("── Faz 1: İç DMEM Çoklu Pattern ──");
    check("DMEM pattern1 (x10=0xDEADBEEF)",
          u_dut.u_core.u_rf.regs[10], 32'hDEAD_BEEF);
    check("DMEM pattern2 (x11=0x12345678)",
          u_dut.u_core.u_rf.regs[11], 32'h1234_5678);
    check("DMEM persist  (x12=0xDEADBEEF)",
          u_dut.u_core.u_rf.regs[12], 32'hDEAD_BEEF);

    // ── Faz 2: AXI DMEM ──────────────────────────
    $display("");
    $display("── Faz 2: AXI DMEM Çoklu Pattern ──");
    check("AXI pattern1  (x13=0xCAFEBABE)",
          u_dut.u_core.u_rf.regs[13], 32'hCAFE_BABE);
    check("AXI pattern2  (x14=0xA5A5A5A5)",
          u_dut.u_core.u_rf.regs[14], 32'hA5A5_A5A5);
    check("AXI small     (x15=0x55)",
          u_dut.u_core.u_rf.regs[15], 32'h0000_0055);
    check("AXI persist   (x16=0xCAFEBABE)",
          u_dut.u_core.u_rf.regs[16], 32'hCAFE_BABE);

    // ── Faz 3: UART Loopback ─────────────────────
    $display("");
    $display("── Faz 3: UART TX→RX Loopback ──");
    check("UART reset STATUS (x17=0x0A)",
          u_dut.u_core.u_rf.regs[17], 32'h0000_000A);
    check("UART loopback RX  (x18=0x55)",
          u_dut.u_core.u_rf.regs[18], 32'h0000_0055);
    check("UART clean STATUS (x19=0x0A)",
          u_dut.u_core.u_rf.regs[19], 32'h0000_000A);

    // ── Faz 4: SPI Transfer ──────────────────────
    $display("");
    $display("── Faz 4: SPI Mode0 Transfer ──");
    check("SPI STATUS rdy+rxv (x20=0x06)",
          u_dut.u_core.u_rf.regs[20], 32'h0000_0006);
    check("SPI RXDATA slave   (x21=0x5A)",
          u_dut.u_core.u_rf.regs[21], 32'h0000_005A);
    check("SPI CTRL persist   (x22=0x41)",
          u_dut.u_core.u_rf.regs[22], 32'h0000_0041);

    // ── Faz 5: I2C Transaction ───────────────────
    $display("");
    $display("── Faz 5: I2C Write Transaction ──");
    check("I2C cmd_ready      (x23=0x08)",
          u_dut.u_core.u_rf.regs[23], 32'h0000_0008);
    check("I2C STATUS no err  (x24=0x08)",
          u_dut.u_core.u_rf.regs[24], 32'h0000_0008);
    check("I2C ack_err=0      (x25=0x00)",
          u_dut.u_core.u_rf.regs[25], 32'h0000_0000);

    // ── Faz 6: DSP ───────────────────────────────
    $display("");
    $display("── Faz 6: DSP Register Erişimi ──");
    check("DSP CTRL enable    (x26=0x01)",
          u_dut.u_core.u_rf.regs[26], 32'h0000_0001);
    check("DSP DATA_IN        (x27=0x1234)",
          u_dut.u_core.u_rf.regs[27], 32'h0000_1234);

    // ── Faz 7: Cross-Peripheral ──────────────────
    $display("");
    $display("── Faz 7: Cross-Peripheral Veri Taşıma ──");
    check("UART→DMEM→readback (x28=0x0A)",
          u_dut.u_core.u_rf.regs[28], 32'h0000_000A);
    check("I2C→DMEM→readback  (x29=0x08)",
          u_dut.u_core.u_rf.regs[29], 32'h0000_0008);

    // ── Faz 8: Hızlı Geçiş ──────────────────────
    $display("");
    $display("── Faz 8: Hızlı Periferal Geçişi ──");
    check("DMEM rapid persist (x30=0x77)",
          u_dut.u_core.u_rf.regs[30], 32'h0000_0077);
    check("DMEM final persist (x31=0xCAFEBABE)",
          u_dut.u_core.u_rf.regs[31], 32'hCAFE_BABE);

    // ── I2C Slave bellek doğrulaması (bonus) ──────
    $display("");
    $display("── Bonus: I2C Slave Bellek Doğrulama ──");
    check("I2C slave mem[0]=0xBB",
          {24'd0, slv_mem[0]}, 32'h0000_00BB);

    // ── Sonuç ────────────────────────────────────
    $display("");
    $display("╔═══════════════════════════════════════════════════╗");
    $display("║  KAPSAMLI SoC SİSTEM TESTİ TAMAMLANDI            ║");
    $display("║  Toplam: %0d  |  PASS: %0d  |  FAIL: %0d",
             test_num, test_pass, test_fail);
    if (test_fail == 0) begin
    $display("║  TÜM TESTLER BAŞARILI!                            ║");
    end
    $display("╚═══════════════════════════════════════════════════╝");

    if (test_fail > 0) begin
      $display("SISTEM TESTI BASARISIZ — %0d hata!", test_fail);
      $fatal;
    end else begin
      $display("[TB] TUM TESTLER BASARILI.");
    end

    $finish;
  end

  // ════════════════════════════════════════════════════════════
  // Watchdog
  // ════════════════════════════════════════════════════════════
  initial begin
    #2_000_000;  // 2 ms
    $display("WATCHDOG TIMEOUT!");
    $fatal;
  end

  // ════════════════════════════════════════════════════════════
  // Debug Monitor (opsiyonel)
  // ════════════════════════════════════════════════════════════
`ifdef DEBUG_MON
  always @(posedge clk) begin
    if (rstn && update) begin
      $display("[%0t] PC=%08h INSTR=%08h rd=x%0d val=%08h | mem_addr=%08h wr=%b rd=%b",
               $time, pc, instr, reg_addr, reg_data, mem_addr, mem_wrt, mem_rd);
    end
  end
`endif

endmodule
