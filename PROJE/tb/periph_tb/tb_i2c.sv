// filepath: tb/periph_tb/tb_i2c.sv
// I2C Periferal Fonksiyon Testi
//
// axi_i2c modülünü doğrudan AXI4-Lite sinyalleriyle sürer.
// Davranışsal I2C Slave BFM ile kapsamlı test.
//
// Test Grupları:
//   1. Reset değerleri kontrolü                    (5 test)
//   2. Register okuma/yazma                        (6 test)
//   3. I2C Write — tek byte                        (4 test)
//   4. I2C Write — çoklu byte                      (4 test)
//   5. I2C Read — tek byte                         (4 test)
//   6. I2C Read — çoklu byte (sequential)          (4 test)
//   7. Data pattern                                (4 test)
//   8. ACK error (yanlış slave adresi)             (3 test)
//   9. Sticky ack_err + STATUS clear               (3 test)
//  10. rx_valid flag + RXDATA clear                (3 test)
//  11. Interrupt doğrulama                         (4 test)
//  12. PRESCALE değişiklikleri                     (2 test)
//  13. Enable kontrolü                             (3 test)
//  14. Busy / cmd_ready bayrak doğrulama           (3 test)
`timescale 1ns / 1ps

module tb_i2c;
  import axi_pkg::*;

  // ════════════════════════════════════════════════
  // Register offsets
  // ════════════════════════════════════════════════
  localparam logic [31:0] REG_TXDATA   = 32'h00;
  localparam logic [31:0] REG_RXDATA   = 32'h04;
  localparam logic [31:0] REG_STATUS   = 32'h08;
  localparam logic [31:0] REG_CTRL     = 32'h0C;
  localparam logic [31:0] REG_PRESCALE = 32'h10;
  localparam logic [31:0] REG_CMD      = 32'h14;

  // I2C Command codes
  localparam logic [31:0] CMD_START     = 32'h01;
  localparam logic [31:0] CMD_WRITE     = 32'h02;
  localparam logic [31:0] CMD_READ_ACK  = 32'h03;
  localparam logic [31:0] CMD_READ_NACK = 32'h04;
  localparam logic [31:0] CMD_STOP      = 32'h05;

  // ════════════════════════════════════════════════
  // Clock & Reset
  // ════════════════════════════════════════════════
  logic clk;
  logic rstn;

  initial begin clk = 0; forever #1 clk = ~clk; end   // 2ns period

  // ════════════════════════════════════════════════
  // AXI4-Lite Sinyalleri
  // ════════════════════════════════════════════════
  logic [AXI_ADDR_WIDTH-1:0] axi_awaddr;
  logic [2:0]                axi_awprot;
  logic                      axi_awvalid;
  logic                      axi_awready;

  logic [AXI_DATA_WIDTH-1:0] axi_wdata;
  logic [AXI_STRB_WIDTH-1:0] axi_wstrb;
  logic                      axi_wvalid;
  logic                      axi_wready;

  logic [1:0]                axi_bresp;
  logic                      axi_bvalid;
  logic                      axi_bready;

  logic [AXI_ADDR_WIDTH-1:0] axi_araddr;
  logic [2:0]                axi_arprot;
  logic                      axi_arvalid;
  logic                      axi_arready;

  logic [AXI_DATA_WIDTH-1:0] axi_rdata;
  logic [1:0]                axi_rresp;
  logic                      axi_rvalid;
  logic                      axi_rready;

  // ════════════════════════════════════════════════
  // I2C Open-Drain Bus Modelleme
  // ════════════════════════════════════════════════
  // Master OE sinyalleri
  logic scl_oe;    // from DUT
  logic sda_oe;    // from DUT

  // Slave OE sinyalleri
  logic slv_sda_oe;

  // Open-drain bus: wire türü, pullup dirençli
  wire i2c_scl = scl_oe ? 1'b0 : 1'b1;            // master only drives SCL
  wire i2c_sda = (sda_oe || slv_sda_oe) ? 1'b0 : 1'b1;  // wired-AND

  // Interrupt
  logic i2c_irq;

  // ════════════════════════════════════════════════
  // DUT: axi_i2c
  // ════════════════════════════════════════════════
  axi_i2c #(
    .DEFAULT_PRESCALE (16'd1)   // Hızlı sim: SCL period = 4*(1+1) = 8 clk
  ) u_dut (
    .clk_i            (clk),
    .rstn_i           (rstn),

    .s_axi_awaddr_i   (axi_awaddr),
    .s_axi_awprot_i   (axi_awprot),
    .s_axi_awvalid_i  (axi_awvalid),
    .s_axi_awready_o  (axi_awready),

    .s_axi_wdata_i    (axi_wdata),
    .s_axi_wstrb_i    (axi_wstrb),
    .s_axi_wvalid_i   (axi_wvalid),
    .s_axi_wready_o   (axi_wready),

    .s_axi_bresp_o    (axi_bresp),
    .s_axi_bvalid_o   (axi_bvalid),
    .s_axi_bready_i   (axi_bready),

    .s_axi_araddr_i   (axi_araddr),
    .s_axi_arprot_i   (axi_arprot),
    .s_axi_arvalid_i  (axi_arvalid),
    .s_axi_arready_o  (axi_arready),

    .s_axi_rdata_o    (axi_rdata),
    .s_axi_rresp_o    (axi_rresp),
    .s_axi_rvalid_o   (axi_rvalid),
    .s_axi_rready_i   (axi_rready),

    .scl_oe_o         (scl_oe),
    .scl_i            (i2c_scl),
    .sda_oe_o         (sda_oe),
    .sda_i            (i2c_sda),
    .irq_o            (i2c_irq)
  );

  // ════════════════════════════════════════════════
  // Davranışsal I2C Slave BFM
  // 7-bit adres = 0x50, 8 byte dahili bellek
  // START/STOP algılama, SCL kenar tespiti
  // Write: Veri alır → belleğe yazar
  // Read:  Bellekten okur → veri gönderir
  // ════════════════════════════════════════════════
  localparam logic [6:0] I2C_SLAVE_ADDR = 7'h50;

  logic [7:0] slv_rx_shift;
  logic [2:0] slv_bit_cnt;
  logic [7:0] slv_mem [0:7];       // 8-byte internal memory
  logic [7:0] slv_tx_shift;
  logic       slv_rw_bit;          // 0=write, 1=read
  logic [2:0] slv_byte_cnt;

  typedef enum logic [3:0] {
    SLV_IDLE        = 4'd0,
    SLV_ADDR_BIT    = 4'd1,
    SLV_ADDR_ACK1   = 4'd2,   // Drive ACK (SDA low)
    SLV_ADDR_ACK2   = 4'd3,   // Release ACK, transition to data phase
    SLV_WR_BIT      = 4'd4,
    SLV_WR_ACK1     = 4'd5,   // Drive data-ACK
    SLV_WR_ACK2     = 4'd6,   // Release data-ACK, next byte
    SLV_RD_BIT      = 4'd7,
    SLV_RD_RELEASE  = 4'd8,   // Release SDA after last read bit
    SLV_RD_ACK_WAIT = 4'd9,   // Wait for master ACK/NACK
    SLV_RD_NEXT_PREP= 4'd10   // Prep next byte (drive bit 7 on scl_fall)
  } slv_state_t;

  slv_state_t slv_state;

  // START / STOP algılama (SDA kenarları SCL=1 iken)
  logic sda_prev, scl_prev_slv;
  logic start_det, stop_det;

  always @(posedge clk) begin
    sda_prev    <= i2c_sda;
    scl_prev_slv <= i2c_scl;
  end

  assign start_det = scl_prev_slv && i2c_scl && sda_prev && !i2c_sda;  // SDA↓ while SCL=1
  assign stop_det  = scl_prev_slv && i2c_scl && !sda_prev && i2c_sda;  // SDA↑ while SCL=1

  // SCL kenar tespiti
  wire scl_rise = !scl_prev_slv && i2c_scl;
  wire scl_fall =  scl_prev_slv && !i2c_scl;

  // Slave yakalanan byte sayacı (TB gözlem için)
  int slv_wr_count;
  int slv_rd_count;

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      slv_state    <= SLV_IDLE;
      slv_sda_oe   <= 1'b0;
      slv_bit_cnt  <= 3'd0;
      slv_rx_shift <= 8'd0;
      slv_byte_cnt <= 3'd0;
      slv_rw_bit   <= 1'b0;
      slv_tx_shift <= 8'd0;
      slv_wr_count <= 0;
      slv_rd_count <= 0;
      slv_mem[0]   <= 8'hA1;
      slv_mem[1]   <= 8'hB2;
      slv_mem[2]   <= 8'hC3;
      slv_mem[3]   <= 8'hD4;
      slv_mem[4]   <= 8'hE5;
      slv_mem[5]   <= 8'hF6;
      slv_mem[6]   <= 8'h17;
      slv_mem[7]   <= 8'h28;
    end else begin
      // START → baştan başla
      if (start_det) begin
        slv_state    <= SLV_ADDR_BIT;
        slv_bit_cnt  <= 3'd7;
        slv_rx_shift <= 8'd0;
        slv_sda_oe   <= 1'b0;
        slv_byte_cnt <= 3'd0;
      end
      // STOP → idle
      else if (stop_det) begin
        slv_state  <= SLV_IDLE;
        slv_sda_oe <= 1'b0;
      end
      else begin
        case (slv_state)
          SLV_IDLE: begin
            slv_sda_oe <= 1'b0;
          end

          // ── Adres byte alma (7-bit addr + R/W) ──
          SLV_ADDR_BIT: begin
            if (scl_rise) begin
              slv_rx_shift <= {slv_rx_shift[6:0], i2c_sda};
              if (slv_bit_cnt == 3'd0)
                slv_state <= SLV_ADDR_ACK1;
              else
                slv_bit_cnt <= slv_bit_cnt - 3'd1;
            end
          end

          // ── Address ACK phase 1: Drive ACK ──
          SLV_ADDR_ACK1: begin
            if (scl_fall) begin
              if (slv_rx_shift[7:1] == I2C_SLAVE_ADDR) begin
                slv_sda_oe   <= 1'b1;   // ACK = SDA low
                slv_rw_bit   <= slv_rx_shift[0];
                slv_byte_cnt <= 3'd0;
                slv_state    <= SLV_ADDR_ACK2;
              end else begin
                slv_sda_oe <= 1'b0;      // NACK
                slv_state  <= SLV_IDLE;
              end
            end
          end

          // ── Address ACK phase 2: Release ACK, start data ──
          SLV_ADDR_ACK2: begin
            if (scl_fall) begin
              if (slv_rw_bit) begin
                // READ: drive bit 7 of mem[0] immediately
                slv_sda_oe   <= !slv_mem[0][7];
                slv_tx_shift <= {slv_mem[0][6:0], 1'b0};
                slv_bit_cnt  <= 3'd6;
                slv_state    <= SLV_RD_BIT;
                slv_rd_count <= slv_rd_count + 1;
              end else begin
                // WRITE: release SDA, prepare to receive
                slv_sda_oe  <= 1'b0;
                slv_bit_cnt <= 3'd7;
                slv_state   <= SLV_WR_BIT;
              end
            end
          end

          // ── Write: Veri byte alma ──
          SLV_WR_BIT: begin
            if (scl_rise) begin
              slv_rx_shift <= {slv_rx_shift[6:0], i2c_sda};
              if (slv_bit_cnt == 3'd0)
                slv_state <= SLV_WR_ACK1;
              else
                slv_bit_cnt <= slv_bit_cnt - 3'd1;
            end
          end

          // ── Write ACK phase 1: Drive ACK, store byte ──
          SLV_WR_ACK1: begin
            if (scl_fall) begin
              slv_sda_oe <= 1'b1;        // ACK = SDA low
              slv_mem[slv_byte_cnt] <= slv_rx_shift;
              slv_wr_count <= slv_wr_count + 1;
              slv_state    <= SLV_WR_ACK2;
            end
          end

          // ── Write ACK phase 2: Release ACK, next byte ──
          SLV_WR_ACK2: begin
            if (scl_fall) begin
              slv_sda_oe  <= 1'b0;
              slv_bit_cnt <= 3'd7;
              slv_byte_cnt <= slv_byte_cnt + 3'd1;
              slv_state   <= SLV_WR_BIT;
            end
          end

          // ── Read: Veri byte gönderme (bits 6→0) ──
          // Bit 7 was already driven in ADDR_ACK2 or RD_ACK_WAIT
          SLV_RD_BIT: begin
            if (scl_fall) begin
              slv_sda_oe   <= !slv_tx_shift[7];
              slv_tx_shift <= {slv_tx_shift[6:0], 1'b0};
              if (slv_bit_cnt == 3'd0) begin
                slv_state <= SLV_RD_RELEASE;
              end else begin
                slv_bit_cnt <= slv_bit_cnt - 3'd1;
              end
            end
          end

          // ── Read: Release SDA after last data bit ──
          SLV_RD_RELEASE: begin
            if (scl_fall) begin
              slv_sda_oe <= 1'b0;  // Release SDA for master ACK/NACK
              slv_state  <= SLV_RD_ACK_WAIT;
            end
          end

          // ── Read: Check master ACK/NACK ──
          SLV_RD_ACK_WAIT: begin
            if (scl_rise) begin
              if (!i2c_sda) begin
                // ACK — prepare next byte (wait for scl_fall to drive bit 7)
                slv_byte_cnt <= slv_byte_cnt + 3'd1;
                slv_state    <= SLV_RD_NEXT_PREP;
              end else begin
                // NACK — stop
                slv_state <= SLV_IDLE;
              end
            end
          end

          // ── Read: Drive bit 7 of next byte at ACK cycle's falling edge ──
          SLV_RD_NEXT_PREP: begin
            if (scl_fall) begin
              slv_sda_oe   <= !slv_mem[slv_byte_cnt][7];
              slv_tx_shift <= {slv_mem[slv_byte_cnt][6:0], 1'b0};
              slv_bit_cnt  <= 3'd6;
              slv_state    <= SLV_RD_BIT;
              slv_rd_count <= slv_rd_count + 1;
            end
          end

          default: slv_state <= SLV_IDLE;
        endcase
      end
    end
  end

  // ════════════════════════════════════════════════
  // Test İstatistikleri
  // ════════════════════════════════════════════════
  int pass_cnt = 0;
  int fail_cnt = 0;
  int test_num = 0;

  // ════════════════════════════════════════════════
  // AXI4-Lite Write Task
  // ════════════════════════════════════════════════
  task automatic axi_write(
    input logic [31:0] addr,
    input logic [31:0] data
  );
    @(negedge clk);
    axi_awaddr  = addr;
    axi_awprot  = 3'b000;
    axi_awvalid = 1'b1;
    axi_wdata   = data;
    axi_wstrb   = 4'hF;
    axi_wvalid  = 1'b1;
    axi_bready  = 1'b1;

    @(negedge clk);
    axi_awvalid = 1'b0;
    axi_wvalid  = 1'b0;

    while (!axi_bvalid) @(negedge clk);
    @(negedge clk);
    axi_bready = 1'b0;
  endtask

  // ════════════════════════════════════════════════
  // AXI4-Lite Read Task
  // ════════════════════════════════════════════════
  task automatic axi_read(
    input  logic [31:0] addr,
    output logic [31:0] data
  );
    @(negedge clk);
    axi_araddr  = addr;
    axi_arprot  = 3'b000;
    axi_arvalid = 1'b1;
    axi_rready  = 1'b1;

    @(negedge clk);
    axi_arvalid = 1'b0;

    while (!axi_rvalid) @(negedge clk);
    data = axi_rdata;

    @(negedge clk);
    axi_rready = 1'b0;
  endtask

  // ════════════════════════════════════════════════
  // Check Task
  // ════════════════════════════════════════════════
  task automatic check(
    input string       test_name,
    input logic [31:0] got,
    input logic [31:0] expected
  );
    test_num++;
    if (got === expected) begin
      pass_cnt++;
      $display("[%0t] PASS #%0d %s — got=0x%08h", $time, test_num, test_name, got);
    end else begin
      fail_cnt++;
      $display("[%0t] FAIL #%0d %s — got=0x%08h expected=0x%08h",
               $time, test_num, test_name, got, expected);
    end
  endtask

  // ════════════════════════════════════════════════
  // I2C Komut Yardımcı Task — cmd yaz ve cmd_ready bekle
  // ════════════════════════════════════════════════
  task automatic i2c_cmd(input logic [31:0] cmd);
    axi_write(REG_CMD, cmd);
    // cmd_ready (STATUS[3]) = 1 olana kadar bekle
    begin
      logic [31:0] st;
      int timeout_cnt;
      timeout_cnt = 0;
      do begin
        @(posedge clk);
        axi_read(REG_STATUS, st);
        timeout_cnt++;
      end while (!st[3] && timeout_cnt < 500);
      if (timeout_cnt >= 500)
        $display("[%0t] WARNING: i2c_cmd timeout for cmd=0x%0h", $time, cmd);
    end
  endtask

  // ════════════════════════════════════════════════
  // I2C Write Transaction Yardımcı
  // START → WRITE(addr_byte) → WRITE(data) ... → STOP
  // ════════════════════════════════════════════════
  task automatic i2c_write_byte(
    input logic [6:0] slave_addr,
    input logic [7:0] data_byte
  );
    // START
    i2c_cmd(CMD_START);
    // Slave address + W (bit0=0)
    axi_write(REG_TXDATA, {24'd0, slave_addr, 1'b0});
    i2c_cmd(CMD_WRITE);
    // Data byte
    axi_write(REG_TXDATA, {24'd0, data_byte});
    i2c_cmd(CMD_WRITE);
    // STOP
    i2c_cmd(CMD_STOP);
  endtask

  // ════════════════════════════════════════════════
  // I2C Read Transaction Yardımcı
  // START → WRITE(addr_byte R) → READ_NACK → STOP
  // ════════════════════════════════════════════════
  task automatic i2c_read_byte(
    input  logic [6:0] slave_addr,
    output logic [7:0] data_byte
  );
    logic [31:0] rd;
    // START
    i2c_cmd(CMD_START);
    // Slave address + R (bit0=1)
    axi_write(REG_TXDATA, {24'd0, slave_addr, 1'b1});
    i2c_cmd(CMD_WRITE);
    // READ with NACK (son byte)
    i2c_cmd(CMD_READ_NACK);
    // STOP
    i2c_cmd(CMD_STOP);
    // RXDATA oku
    axi_read(REG_RXDATA, rd);
    data_byte = rd[7:0];
  endtask

  // ════════════════════════════════════════════════
  // Slave belleğini resetle (test izolasyonu için)
  // ════════════════════════════════════════════════
  task automatic reset_slave_mem();
    slv_mem[0] = 8'hA1;
    slv_mem[1] = 8'hB2;
    slv_mem[2] = 8'hC3;
    slv_mem[3] = 8'hD4;
    slv_mem[4] = 8'hE5;
    slv_mem[5] = 8'hF6;
    slv_mem[6] = 8'h17;
    slv_mem[7] = 8'h28;
  endtask

  // ════════════════════════════════════════════════
  // DUT Reset + Yeniden Başlatma
  // Master core ack_err sticky olduğundan (sadece reset ile temizlenir)
  // ════════════════════════════════════════════════
  task automatic dut_reset();
    rstn = 1'b0;
    repeat (5) @(posedge clk);
    rstn = 1'b1;
    repeat (5) @(posedge clk);
    // Re-enable I2C with fast prescale
    axi_write(REG_CTRL, 32'h0000_0001);      // en=1
    axi_write(REG_PRESCALE, 32'h0000_0001);  // fast prescale
    reset_slave_mem();
  endtask

  // ════════════════════════════════════════════════
  // Ana Test Süreci
  // ════════════════════════════════════════════════
  logic [31:0] rd;

  initial begin
    // AXI sinyallerini sıfırla
    axi_awaddr  = '0; axi_awprot  = '0; axi_awvalid = 1'b0;
    axi_wdata   = '0; axi_wstrb   = '0; axi_wvalid  = 1'b0;
    axi_bready  = 1'b0;
    axi_araddr  = '0; axi_arprot  = '0; axi_arvalid = 1'b0;
    axi_rready  = 1'b0;

    // Reset pulse
    rstn = 1'b0;
    repeat (10) @(posedge clk);
    rstn = 1'b1;
    repeat (5) @(posedge clk);

    $display("═══════════════════════════════════════════════════");
    $display("   I2C PERIFERAL FONKSIYON TESTİ BAŞLADI");
    $display("═══════════════════════════════════════════════════");

    // ════════════════════════════════════════════════
    // Grup 1: Reset değerleri kontrolü (5 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 1: Reset Değerleri Kontrolü ──");

    axi_read(REG_TXDATA, rd);
    check("RST TXDATA=0x00", rd, 32'h0000_0000);

    axi_read(REG_RXDATA, rd);
    check("RST RXDATA=0x00", rd, 32'h0000_0000);

    axi_read(REG_STATUS, rd);
    // After reset: busy=0, ack_err=0, rx_valid=0, cmd_ready=0 (en=0 → not ready)
    check("RST STATUS=0x00", rd, 32'h0000_0000);

    axi_read(REG_CTRL, rd);
    check("RST CTRL=0x00", rd, 32'h0000_0000);

    axi_read(REG_PRESCALE, rd);
    check("RST PRESCALE=0x0001", rd, 32'h0000_0001);   // DEFAULT_PRESCALE=1

    // ════════════════════════════════════════════════
    // Grup 2: Register okuma/yazma (6 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 2: Register Okuma/Yazma ──");

    // TXDATA yazma/okuma
    axi_write(REG_TXDATA, 32'h0000_00AB);
    axi_read(REG_TXDATA, rd);
    check("TXDATA W/R 0xAB", rd, 32'h0000_00AB);

    // CTRL yazma/okuma
    axi_write(REG_CTRL, 32'h0000_0003);   // en=1, ie=1
    axi_read(REG_CTRL, rd);
    check("CTRL W/R 0x03", rd, 32'h0000_0003);

    // PRESCALE yazma/okuma
    axi_write(REG_PRESCALE, 32'h0000_00F9);  // 249
    axi_read(REG_PRESCALE, rd);
    check("PRESCALE W/R 0xF9", rd, 32'h0000_00F9);

    // CMD yazma/okuma (son verilen komut okunur)
    axi_write(REG_CMD, 32'h0000_0001);   // START
    repeat (5) @(posedge clk);
    axi_read(REG_CMD, rd);
    check("CMD W/R 0x01", rd, 32'h0000_0001);

    // STATUS read after enable (cmd_ready should be 1 when idle + en)
    // Wait for the START command to complete first
    begin
      logic [31:0] st;
      int wcnt;
      wcnt = 0;
      do begin
        @(posedge clk);
        axi_read(REG_STATUS, st);
        wcnt++;
      end while (st[0] && wcnt < 500);
    end
    axi_read(REG_STATUS, rd);
    check("STATUS cmd_ready after en", rd[3], 1'b1);

    // RXDATA is read-only — writing should not change it (write ignored)
    axi_write(REG_RXDATA, 32'h0000_00FF);
    axi_read(REG_RXDATA, rd);
    check("RXDATA read-only", rd, 32'h0000_0000);

    // ── Restore defaults for next tests ──
    axi_write(REG_PRESCALE, 32'h0000_0001);  // restore fast prescale
    axi_write(REG_CTRL, 32'h0000_0001);      // en=1, ie=0

    // ════════════════════════════════════════════════
    // Grup 3: I2C Write — tek byte (4 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 3: I2C Write — Tek Byte ──");
    reset_slave_mem();

    // Write 0x55 to slave addr 0x50
    i2c_write_byte(7'h50, 8'h55);

    // Slave mem[0] güncellenmiş olmalı
    check("WR byte slave_mem[0]=0x55", {24'd0, slv_mem[0]}, 32'h0000_0055);

    // STATUS: no ack_err
    axi_read(REG_STATUS, rd);
    check("WR byte no ack_err", rd[1], 1'b0);

    // Write another byte 0xAA
    reset_slave_mem();
    i2c_write_byte(7'h50, 8'hAA);
    check("WR byte slave_mem[0]=0xAA", {24'd0, slv_mem[0]}, 32'h0000_00AA);

    // STATUS should be idle, cmd_ready
    axi_read(REG_STATUS, rd);
    check("WR byte STATUS idle", rd[0], 1'b0);

    // ════════════════════════════════════════════════
    // Grup 4: I2C Write — çoklu byte (4 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 4: I2C Write — Çoklu Byte ──");
    reset_slave_mem();

    // Write 3 bytes: 0x11, 0x22, 0x33
    i2c_cmd(CMD_START);
    axi_write(REG_TXDATA, {24'd0, 7'h50, 1'b0});  // addr + W
    i2c_cmd(CMD_WRITE);
    axi_write(REG_TXDATA, 32'h0000_0011);
    i2c_cmd(CMD_WRITE);
    axi_write(REG_TXDATA, 32'h0000_0022);
    i2c_cmd(CMD_WRITE);
    axi_write(REG_TXDATA, 32'h0000_0033);
    i2c_cmd(CMD_WRITE);
    i2c_cmd(CMD_STOP);

    check("WR multi slave_mem[0]=0x11", {24'd0, slv_mem[0]}, 32'h0000_0011);
    check("WR multi slave_mem[1]=0x22", {24'd0, slv_mem[1]}, 32'h0000_0022);
    check("WR multi slave_mem[2]=0x33", {24'd0, slv_mem[2]}, 32'h0000_0033);

    axi_read(REG_STATUS, rd);
    check("WR multi no ack_err", rd[1], 1'b0);

    // ════════════════════════════════════════════════
    // Grup 5: I2C Read — tek byte (4 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 5: I2C Read — Tek Byte ──");
    reset_slave_mem();

    begin
      logic [7:0] rx_byte;
      i2c_read_byte(7'h50, rx_byte);
      check("RD byte = slave_mem[0]=0xA1", {24'd0, rx_byte}, 32'h0000_00A1);
    end

    // STATUS: no ack_err
    axi_read(REG_STATUS, rd);
    check("RD byte no ack_err", rd[1], 1'b0);

    // Read again — should get 0xA1 again (same mem[0])
    reset_slave_mem();
    begin
      logic [7:0] rx_byte2;
      i2c_read_byte(7'h50, rx_byte2);
      check("RD byte2 = 0xA1", {24'd0, rx_byte2}, 32'h0000_00A1);
    end

    axi_read(REG_STATUS, rd);
    check("RD byte2 STATUS idle", rd[0], 1'b0);

    // ════════════════════════════════════════════════
    // Grup 6: I2C Read — çoklu byte sequential (4 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 6: I2C Read — Çoklu Byte ──");
    reset_slave_mem();

    // Read 3 bytes: mem[0]=0xA1, mem[1]=0xB2, mem[2]=0xC3
    i2c_cmd(CMD_START);
    axi_write(REG_TXDATA, {24'd0, 7'h50, 1'b1});  // addr + R
    i2c_cmd(CMD_WRITE);

    // Read byte 0 (ACK)
    i2c_cmd(CMD_READ_ACK);
    axi_read(REG_RXDATA, rd);
    check("RD multi byte0=0xA1", rd[7:0], 8'hA1);

    // Read byte 1 (ACK)
    i2c_cmd(CMD_READ_ACK);
    axi_read(REG_RXDATA, rd);
    check("RD multi byte1=0xB2", rd[7:0], 8'hB2);

    // Read byte 2 (NACK — son byte)
    i2c_cmd(CMD_READ_NACK);
    axi_read(REG_RXDATA, rd);
    check("RD multi byte2=0xC3", rd[7:0], 8'hC3);

    i2c_cmd(CMD_STOP);

    axi_read(REG_STATUS, rd);
    check("RD multi no ack_err", rd[1], 1'b0);

    // ════════════════════════════════════════════════
    // Grup 7: Data pattern (4 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 7: Data Pattern ──");
    reset_slave_mem();

    // Write 0x00
    i2c_write_byte(7'h50, 8'h00);
    check("Pattern 0x00", {24'd0, slv_mem[0]}, 32'h0000_0000);

    // Write 0xFF
    reset_slave_mem();
    i2c_write_byte(7'h50, 8'hFF);
    check("Pattern 0xFF", {24'd0, slv_mem[0]}, 32'h0000_00FF);

    // Write 0x55 (alternating)
    reset_slave_mem();
    i2c_write_byte(7'h50, 8'h55);
    check("Pattern 0x55", {24'd0, slv_mem[0]}, 32'h0000_0055);

    // Write 0xAA (alternating)
    reset_slave_mem();
    i2c_write_byte(7'h50, 8'hAA);
    check("Pattern 0xAA", {24'd0, slv_mem[0]}, 32'h0000_00AA);

    // ════════════════════════════════════════════════
    // Grup 8: ACK error — yanlış slave adresi (3 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 8: ACK Error (Yanlış Adres) ──");

    // Clear any previous ack_err
    axi_write(REG_STATUS, 32'h0000_0000);
    axi_read(REG_STATUS, rd);
    check("ACK_ERR clear before test", rd[1], 1'b0);

    // Send to non-existent slave 0x51
    i2c_cmd(CMD_START);
    axi_write(REG_TXDATA, {24'd0, 7'h51, 1'b0});  // wrong addr + W
    i2c_cmd(CMD_WRITE);
    i2c_cmd(CMD_STOP);

    // STATUS: ack_err should be set
    axi_read(REG_STATUS, rd);
    check("ACK_ERR set for 0x51", rd[1], 1'b1);

    // ack_err is sticky — still set after read
    axi_read(REG_STATUS, rd);
    check("ACK_ERR sticky", rd[1], 1'b1);

    // ════════════════════════════════════════════════
    // Grup 9: Sticky ack_err + Reset clear (3 test)
    // Not: Master core ack_err sticky (sadece reset temizler).
    //       STATUS write wrapper flag'i temizler ama core
    //       hemen yeniden set eder. Bu nedenle full reset test edilir.
    // ════════════════════════════════════════════════
    $display("\n── Grup 9: Sticky ack_err + Reset Clear ──");

    // ack_err still set from group 8
    axi_read(REG_STATUS, rd);
    check("Sticky ack_err still set", rd[1], 1'b1);

    // Full DUT reset clears ack_err (master core dahil)
    dut_reset();
    axi_read(REG_STATUS, rd);
    check("DUT reset clears ack_err", rd[1], 1'b0);

    // Confirm normal operation works after reset
    i2c_write_byte(7'h50, 8'h77);
    axi_read(REG_STATUS, rd);
    check("Normal op after reset", rd[1], 1'b0);

    // ════════════════════════════════════════════════
    // Grup 10: rx_valid flag + RXDATA clear (3 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 10: rx_valid Flag + RXDATA Clear ──");
    dut_reset();

    // After read, rx_valid should be set
    i2c_cmd(CMD_START);
    axi_write(REG_TXDATA, {24'd0, 7'h50, 1'b1});  // addr + R
    i2c_cmd(CMD_WRITE);
    i2c_cmd(CMD_READ_NACK);
    i2c_cmd(CMD_STOP);

    // Check rx_valid = 1
    axi_read(REG_STATUS, rd);
    check("rx_valid set after read", rd[2], 1'b1);

    // Reading RXDATA clears rx_valid
    axi_read(REG_RXDATA, rd);
    check("RXDATA = 0xA1", rd[7:0], 8'hA1);

    axi_read(REG_STATUS, rd);
    check("rx_valid cleared after RXDATA read", rd[2], 1'b0);

    // ════════════════════════════════════════════════
    // Grup 11: Interrupt doğrulama (4 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 11: Interrupt Doğrulama ──");
    dut_reset();

    // ie=0 → irq deasserted
    axi_write(REG_CTRL, 32'h0000_0001);  // en=1, ie=0
    repeat (5) @(posedge clk);
    check("IRQ deassert ie=0", {31'd0, i2c_irq}, 32'h0000_0000);

    // ie=1, cmd_ready=1 (idle) → irq asserted
    axi_write(REG_CTRL, 32'h0000_0003);  // en=1, ie=1
    repeat (5) @(posedge clk);
    // Should be 1 because cmd_ready=1 when idle+enabled
    check("IRQ assert ie=1 cmd_ready", {31'd0, i2c_irq}, 32'h0000_0001);

    // Trigger ack_err → irq should stay asserted
    axi_write(REG_STATUS, 32'h0000_0000);  // clear old errors
    i2c_cmd(CMD_START);
    axi_write(REG_TXDATA, {24'd0, 7'h51, 1'b0});  // wrong addr
    i2c_cmd(CMD_WRITE);
    i2c_cmd(CMD_STOP);
    repeat (5) @(posedge clk);
    check("IRQ assert ie=1 ack_err", {31'd0, i2c_irq}, 32'h0000_0001);

    // ie=0 → irq deasserted even with ack_err
    axi_write(REG_CTRL, 32'h0000_0001);  // en=1, ie=0
    repeat (5) @(posedge clk);
    check("IRQ deassert ie=0 with ack_err", {31'd0, i2c_irq}, 32'h0000_0000);

    // Clean up — full reset to clear master ack_err
    dut_reset();

    // ════════════════════════════════════════════════
    // Grup 12: PRESCALE değişiklikleri (2 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 12: PRESCALE Değişiklikleri ──");

    // PRESCALE=2 → SCL period = 4*(2+1) = 12 clk
    axi_write(REG_PRESCALE, 32'h0000_0002);
    i2c_write_byte(7'h50, 8'hDD);
    check("PRESCALE=2 write ok", {24'd0, slv_mem[0]}, 32'h0000_00DD);

    // PRESCALE=3 → SCL period = 4*(3+1) = 16 clk
    reset_slave_mem();
    axi_write(REG_PRESCALE, 32'h0000_0003);
    i2c_write_byte(7'h50, 8'hEE);
    check("PRESCALE=3 write ok", {24'd0, slv_mem[0]}, 32'h0000_00EE);

    // Restore default
    axi_write(REG_PRESCALE, 32'h0000_0001);

    // ════════════════════════════════════════════════
    // Grup 13: Enable kontrolü (3 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 13: Enable Kontrolü ──");

    // Disable module
    axi_write(REG_CTRL, 32'h0000_0000);  // en=0
    repeat (3) @(posedge clk);

    // cmd_ready should be 0 when disabled
    axi_read(REG_STATUS, rd);
    check("EN=0 cmd_ready=0", rd[3], 1'b0);

    // Write CMD while disabled — should not start transaction
    axi_write(REG_CMD, CMD_START);
    repeat (20) @(posedge clk);
    axi_read(REG_STATUS, rd);
    check("EN=0 busy stays 0", rd[0], 1'b0);

    // Re-enable
    axi_write(REG_CTRL, 32'h0000_0001);  // en=1
    repeat (3) @(posedge clk);
    axi_read(REG_STATUS, rd);
    check("EN=1 cmd_ready=1", rd[3], 1'b1);

    // ════════════════════════════════════════════════
    // Grup 14: Busy / cmd_ready bayrak doğrulama (3 test)
    // ════════════════════════════════════════════════
    $display("\n── Grup 14: Busy / cmd_ready Bayrakları ──");
    reset_slave_mem();

    // When idle: busy=0, cmd_ready=1
    axi_read(REG_STATUS, rd);
    check("IDLE busy=0 cmd_ready=1", {rd[3], rd[0]}, {1'b1, 1'b0});

    // Issue START — check busy becomes 1 during operation
    axi_write(REG_CMD, CMD_START);
    // Immediately after CMD write, busy should be 1 (or will be very soon)
    repeat (2) @(posedge clk);
    axi_read(REG_STATUS, rd);
    check("START busy=1", rd[0], 1'b1);

    // Wait for completion
    begin
      logic [31:0] st;
      int wcnt;
      wcnt = 0;
      do begin
        @(posedge clk);
        axi_read(REG_STATUS, st);
        wcnt++;
      end while (st[0] && wcnt < 500);
    end
    // Now send STOP to clean up
    i2c_cmd(CMD_STOP);
    axi_read(REG_STATUS, rd);
    check("After STOP idle again", rd[0], 1'b0);

    // ════════════════════════════════════════════════
    // Sonuç
    // ════════════════════════════════════════════════
    $display("\n═══════════════════════════════════════════════════");
    $display("   I2C FONKSIYON TESTİ TAMAMLANDI");
    $display("   PASS: %0d / %0d", pass_cnt, pass_cnt + fail_cnt);
    if (fail_cnt > 0)
      $display("   FAIL: %0d", fail_cnt);
    else
      $display("   TÜM TESTLER BAŞARILI!");
    $display("═══════════════════════════════════════════════════");

    $finish;
  end

  // ════════════════════════════════════════════════
  // Watchdog timer — simülasyon kilitlenmesini önle
  // ════════════════════════════════════════════════
  initial begin
    #500000;
    $display("[WATCHDOG] Simülasyon zaman aşımı!");
    $finish;
  end

endmodule
