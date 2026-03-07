// filepath: tb/soc_tb/tb_soc_integration.sv
// SoC Entegrasyon Testi
// AXI Master IF → Interconnect → DMEM / DSP / UART / SPI / I2C bağlantılarını doğrular.
// Test akışı:
//   1. DMEM'e yazma & geri okuma (word, half, byte)
//   2. DSP register yazma & okuma (CTRL, DATA_IN, STATUS, DATA_OUT)
//   3. UART register erişimi + TX→RX loopback
//  3A. SPI register erişimi + MOSI→MISO loopback transfer
//  3B. I2C register erişimi (CTRL, PRESCALE, TXDATA)
//  3C. I2C transaction testi (START + WRITE + STOP w/ slave model)
//   4. DMEM ardışık erişim + DSP↔DMEM çapraz kontrol
//
// NOT: Bu testbench, soc_top'u değil, AXI altyapısını doğrudan sürer.
//      Pipeline placeholder sinyallerini bypass ederek AXI Master IF'i
//      kontrol eder.
`timescale 1ns / 1ps

module tb_soc_integration;
  import riscv_pkg::*;
  import axi_pkg::*;

  // ════════════════════════════════════════════════
  // Clock & Reset
  // ════════════════════════════════════════════════
  logic clk;
  logic rstn;

  initial begin clk = 0; forever #1 clk = ~clk; end  // 2ns period

  // ════════════════════════════════════════════════
  // AXI Master IF driver sinyalleri
  // ════════════════════════════════════════════════
  logic             drv_mem_read;
  logic             drv_mem_write;
  logic [1:0]       drv_mem_size;
  logic             drv_mem_unsigned;
  logic [31:0]      drv_addr;
  logic [31:0]      drv_wdata;
  logic [31:0]      drv_rdata;
  logic             drv_ready;

  // ════════════════════════════════════════════════
  // AXI Master ↔ Interconnect arası sinyaller
  // ════════════════════════════════════════════════
  logic [AXI_ADDR_WIDTH-1:0] mst_awaddr,  mst_araddr;
  logic [2:0]                mst_awprot,  mst_arprot;
  logic                      mst_awvalid, mst_arvalid;
  logic                      mst_awready, mst_arready;

  logic [AXI_DATA_WIDTH-1:0] mst_wdata;
  logic [AXI_STRB_WIDTH-1:0] mst_wstrb;
  logic                      mst_wvalid,  mst_wready;

  logic [1:0]                mst_bresp,   mst_rresp;
  logic                      mst_bvalid,  mst_rvalid;
  logic                      mst_bready,  mst_rready;

  logic [AXI_DATA_WIDTH-1:0] mst_rdata;

  // ════════════════════════════════════════════════
  // Interconnect ↔ Slave sinyalleri
  // ════════════════════════════════════════════════
  logic [AXI_ADDR_WIDTH-1:0] slv_awaddr  [NUM_SLAVES];
  logic [2:0]                slv_awprot  [NUM_SLAVES];
  logic                      slv_awvalid [NUM_SLAVES];
  logic                      slv_awready [NUM_SLAVES];

  logic [AXI_DATA_WIDTH-1:0] slv_wdata   [NUM_SLAVES];
  logic [AXI_STRB_WIDTH-1:0] slv_wstrb   [NUM_SLAVES];
  logic                      slv_wvalid  [NUM_SLAVES];
  logic                      slv_wready  [NUM_SLAVES];

  logic [1:0]                slv_bresp   [NUM_SLAVES];
  logic                      slv_bvalid  [NUM_SLAVES];
  logic                      slv_bready  [NUM_SLAVES];

  logic [AXI_ADDR_WIDTH-1:0] slv_araddr  [NUM_SLAVES];
  logic [2:0]                slv_arprot  [NUM_SLAVES];
  logic                      slv_arvalid [NUM_SLAVES];
  logic                      slv_arready [NUM_SLAVES];

  logic [AXI_DATA_WIDTH-1:0] slv_rdata   [NUM_SLAVES];
  logic [1:0]                slv_rresp   [NUM_SLAVES];
  logic                      slv_rvalid  [NUM_SLAVES];
  logic                      slv_rready  [NUM_SLAVES];

  // ════════════════════════════════════════════════
  // Test istatistikleri
  // ════════════════════════════════════════════════
  int pass_cnt = 0;
  int fail_cnt = 0;
  int test_num = 0;

  // ════════════════════════════════════════════════
  // DUT: AXI Master Interface
  // ════════════════════════════════════════════════
  axi_master_if u_axi_master (
    .clk_i            (clk),
    .rstn_i           (rstn),
    .mem_read_i       (drv_mem_read),
    .mem_write_i      (drv_mem_write),
    .mem_size_i       (drv_mem_size),
    .mem_unsigned_i   (drv_mem_unsigned),
    .addr_i           (drv_addr),
    .wdata_i          (drv_wdata),
    .rdata_o          (drv_rdata),
    .ready_o          (drv_ready),
    .m_axi_awaddr_o   (mst_awaddr),
    .m_axi_awprot_o   (mst_awprot),
    .m_axi_awvalid_o  (mst_awvalid),
    .m_axi_awready_i  (mst_awready),
    .m_axi_wdata_o    (mst_wdata),
    .m_axi_wstrb_o    (mst_wstrb),
    .m_axi_wvalid_o   (mst_wvalid),
    .m_axi_wready_i   (mst_wready),
    .m_axi_bresp_i    (mst_bresp),
    .m_axi_bvalid_i   (mst_bvalid),
    .m_axi_bready_o   (mst_bready),
    .m_axi_araddr_o   (mst_araddr),
    .m_axi_arprot_o   (mst_arprot),
    .m_axi_arvalid_o  (mst_arvalid),
    .m_axi_arready_i  (mst_arready),
    .m_axi_rdata_i    (mst_rdata),
    .m_axi_rresp_i    (mst_rresp),
    .m_axi_rvalid_i   (mst_rvalid),
    .m_axi_rready_o   (mst_rready)
  );

  // ════════════════════════════════════════════════
  // DUT: AXI Interconnect
  // ════════════════════════════════════════════════
  axi_interconnect u_interconnect (
    .clk_i         (clk),
    .rstn_i        (rstn),
    .m_awaddr_i    (mst_awaddr),
    .m_awprot_i    (mst_awprot),
    .m_awvalid_i   (mst_awvalid),
    .m_awready_o   (mst_awready),
    .m_wdata_i     (mst_wdata),
    .m_wstrb_i     (mst_wstrb),
    .m_wvalid_i    (mst_wvalid),
    .m_wready_o    (mst_wready),
    .m_bresp_o     (mst_bresp),
    .m_bvalid_o    (mst_bvalid),
    .m_bready_i    (mst_bready),
    .m_araddr_i    (mst_araddr),
    .m_arprot_i    (mst_arprot),
    .m_arvalid_i   (mst_arvalid),
    .m_arready_o   (mst_arready),
    .m_rdata_o     (mst_rdata),
    .m_rresp_o     (mst_rresp),
    .m_rvalid_o    (mst_rvalid),
    .m_rready_i    (mst_rready),
    .s_awaddr_o    (slv_awaddr),
    .s_awprot_o    (slv_awprot),
    .s_awvalid_o   (slv_awvalid),
    .s_awready_i   (slv_awready),
    .s_wdata_o     (slv_wdata),
    .s_wstrb_o     (slv_wstrb),
    .s_wvalid_o    (slv_wvalid),
    .s_wready_i    (slv_wready),
    .s_bresp_i     (slv_bresp),
    .s_bvalid_i    (slv_bvalid),
    .s_bready_o    (slv_bready),
    .s_araddr_o    (slv_araddr),
    .s_arprot_o    (slv_arprot),
    .s_arvalid_o   (slv_arvalid),
    .s_arready_i   (slv_arready),
    .s_rdata_i     (slv_rdata),
    .s_rresp_i     (slv_rresp),
    .s_rvalid_i    (slv_rvalid),
    .s_rready_o    (slv_rready)
  );

  // ════════════════════════════════════════════════
  // Slave 0: DMEM (AXI Wrapper)
  // ════════════════════════════════════════════════
  logic [31:0] dmem_dbg_data;  // kullanılmıyor

  axi_dmem_slave #(
    .DMEM_INIT_FILE ("dmem.mem"),
    .DMEM_BASE      (32'h8001_0000),
    .DMEM_BYTES     (32768)
  ) u_axi_dmem (
    .clk_i            (clk),
    .rstn_i           (rstn),
    .s_axi_awaddr_i   (slv_awaddr  [SLV_DMEM]),
    .s_axi_awprot_i   (slv_awprot  [SLV_DMEM]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_DMEM]),
    .s_axi_awready_o  (slv_awready [SLV_DMEM]),
    .s_axi_wdata_i    (slv_wdata   [SLV_DMEM]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_DMEM]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_DMEM]),
    .s_axi_wready_o   (slv_wready  [SLV_DMEM]),
    .s_axi_bresp_o    (slv_bresp   [SLV_DMEM]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_DMEM]),
    .s_axi_bready_i   (slv_bready  [SLV_DMEM]),
    .s_axi_araddr_i   (slv_araddr  [SLV_DMEM]),
    .s_axi_arprot_i   (slv_arprot  [SLV_DMEM]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_DMEM]),
    .s_axi_arready_o  (slv_arready [SLV_DMEM]),
    .s_axi_rdata_o    (slv_rdata   [SLV_DMEM]),
    .s_axi_rresp_o    (slv_rresp   [SLV_DMEM]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_DMEM]),
    .s_axi_rready_i   (slv_rready  [SLV_DMEM]),
    .dbg_addr_i       (32'h8001_0000),
    .dbg_data_o       (dmem_dbg_data)
  );

  // ════════════════════════════════════════════════
  // Slave 4: DSP FIR Filtre Wrapper
  // ════════════════════════════════════════════════
  dsp_filter_wrapper u_dsp_filter (
    .clk_i            (clk),
    .rstn_i           (rstn),
    .s_axi_awaddr_i   (slv_awaddr  [SLV_DSP]),
    .s_axi_awprot_i   (slv_awprot  [SLV_DSP]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_DSP]),
    .s_axi_awready_o  (slv_awready [SLV_DSP]),
    .s_axi_wdata_i    (slv_wdata   [SLV_DSP]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_DSP]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_DSP]),
    .s_axi_wready_o   (slv_wready  [SLV_DSP]),
    .s_axi_bresp_o    (slv_bresp   [SLV_DSP]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_DSP]),
    .s_axi_bready_i   (slv_bready  [SLV_DSP]),
    .s_axi_araddr_i   (slv_araddr  [SLV_DSP]),
    .s_axi_arprot_i   (slv_arprot  [SLV_DSP]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_DSP]),
    .s_axi_arready_o  (slv_arready [SLV_DSP]),
    .s_axi_rdata_o    (slv_rdata   [SLV_DSP]),
    .s_axi_rresp_o    (slv_rresp   [SLV_DSP]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_DSP]),
    .s_axi_rready_i   (slv_rready  [SLV_DSP])
  );
  // ════════════════════════════════════════════════
  // Slave 1: UART (Gerçek modül)
  // TX → RX loopback ile test edilir
  // ════════════════════════════════════════════════
  logic uart_tx_wire;
  logic uart_irq_wire;

  axi_uart #(
    .DEFAULT_BAUD_DIV (16'd0)   // Test için en hızlı baud (her 1 cycle'da tick)
  ) u_axi_uart (
    .clk_i            (clk),
    .rstn_i           (rstn),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_UART]),
    .s_axi_awprot_i   (slv_awprot  [SLV_UART]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_UART]),
    .s_axi_awready_o  (slv_awready [SLV_UART]),
    .s_axi_wdata_i    (slv_wdata   [SLV_UART]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_UART]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_UART]),
    .s_axi_wready_o   (slv_wready  [SLV_UART]),
    .s_axi_bresp_o    (slv_bresp   [SLV_UART]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_UART]),
    .s_axi_bready_i   (slv_bready  [SLV_UART]),
    .s_axi_araddr_i   (slv_araddr  [SLV_UART]),
    .s_axi_arprot_i   (slv_arprot  [SLV_UART]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_UART]),
    .s_axi_arready_o  (slv_arready [SLV_UART]),
    .s_axi_rdata_o    (slv_rdata   [SLV_UART]),
    .s_axi_rresp_o    (slv_rresp   [SLV_UART]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_UART]),
    .s_axi_rready_i   (slv_rready  [SLV_UART]),

    .tx_o             (uart_tx_wire),
    .rx_i             (uart_tx_wire),   // TX → RX loopback
    .irq_o            (uart_irq_wire)
  );

  // ════════════════════════════════════════════════
  // Slave 3: I2C Master (Gerçek modül)
  // Open-drain bus — pullup + tristate modelleme
  // ════════════════════════════════════════════════
  wire  i2c_scl_wire;
  wire  i2c_sda_wire;

  // Pull-up modeli
  pullup (i2c_scl_wire);
  pullup (i2c_sda_wire);

  // Master OE sinyalleri
  logic i2c_scl_oe, i2c_sda_oe;

  assign i2c_scl_wire = i2c_scl_oe ? 1'b0 : 1'bz;
  assign i2c_sda_wire = i2c_sda_oe ? 1'b0 : 1'bz;

  logic i2c_irq_wire;

  axi_i2c #(
    .DEFAULT_PRESCALE (16'd1)   // Hızlı sim: SCL period = 4*(1+1) = 8 clk cycle
  ) u_axi_i2c (
    .clk_i            (clk),
    .rstn_i           (rstn),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_I2C]),
    .s_axi_awprot_i   (slv_awprot  [SLV_I2C]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_I2C]),
    .s_axi_awready_o  (slv_awready [SLV_I2C]),
    .s_axi_wdata_i    (slv_wdata   [SLV_I2C]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_I2C]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_I2C]),
    .s_axi_wready_o   (slv_wready  [SLV_I2C]),
    .s_axi_bresp_o    (slv_bresp   [SLV_I2C]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_I2C]),
    .s_axi_bready_i   (slv_bready  [SLV_I2C]),
    .s_axi_araddr_i   (slv_araddr  [SLV_I2C]),
    .s_axi_arprot_i   (slv_arprot  [SLV_I2C]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_I2C]),
    .s_axi_arready_o  (slv_arready [SLV_I2C]),
    .s_axi_rdata_o    (slv_rdata   [SLV_I2C]),
    .s_axi_rresp_o    (slv_rresp   [SLV_I2C]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_I2C]),
    .s_axi_rready_i   (slv_rready  [SLV_I2C]),

    .scl_oe_o         (i2c_scl_oe),
    .scl_i            (i2c_scl_wire),
    .sda_oe_o         (i2c_sda_oe),
    .sda_i            (i2c_sda_wire),
    .irq_o            (i2c_irq_wire)
  );

  // ── Basit I2C Slave Modeli (7-bit adres = 7'h50) ──────────
  // START algılar, adres byte alır, ACK verir, veri byte alır/gönderir.
  logic       slv_sda_oe = 1'b0;  // slave SDA sürücü
  assign i2c_sda_wire = slv_sda_oe ? 1'b0 : 1'bz;

  localparam logic [6:0] I2C_SLAVE_ADDR = 7'h50;

  logic [7:0] slv_rx_shift;
  logic [2:0] slv_bit_cnt;
  logic [7:0] slv_mem [0:3];     // 4-byte internal memory
  logic [7:0] slv_tx_shift;
  logic       slv_rw_bit;        // 0=write, 1=read
  logic [1:0] slv_byte_cnt;

  typedef enum logic [3:0] {
    SLV_IDLE,
    SLV_ADDR_BIT,
    SLV_ADDR_ACK,
    SLV_WR_BIT,
    SLV_WR_ACK,
    SLV_RD_BIT,
    SLV_RD_ACK_WAIT
  } slv_state_t;

  slv_state_t slv_state = SLV_IDLE;

  // START / STOP detect (SDA kenarları SCL=1 iken)
  logic sda_prev = 1'b1;
  logic scl_prev = 1'b1;
  logic start_det, stop_det;

  always @(posedge clk) begin
    sda_prev <= i2c_sda_wire;
    scl_prev <= i2c_scl_wire;
  end

  assign start_det = scl_prev && i2c_scl_wire && sda_prev && !i2c_sda_wire; // SDA ↓ while SCL=1
  assign stop_det  = scl_prev && i2c_scl_wire && !sda_prev && i2c_sda_wire; // SDA ↑ while SCL=1

  // SCL rising edge detect (data sample)
  wire scl_rise = !scl_prev && i2c_scl_wire;
  // SCL falling edge detect (data change)
  wire scl_fall = scl_prev && !i2c_scl_wire;

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      slv_state    <= SLV_IDLE;
      slv_sda_oe   <= 1'b0;
      slv_bit_cnt  <= 3'd0;
      slv_rx_shift <= 8'd0;
      slv_byte_cnt <= 2'd0;
      slv_rw_bit   <= 1'b0;
      slv_tx_shift <= 8'd0;
      slv_mem[0]   <= 8'hA1;
      slv_mem[1]   <= 8'hB2;
      slv_mem[2]   <= 8'hC3;
      slv_mem[3]   <= 8'hD4;
    end else begin
      // START → baştan başla
      if (start_det) begin
        slv_state    <= SLV_ADDR_BIT;
        slv_bit_cnt  <= 3'd7;
        slv_rx_shift <= 8'd0;
        slv_sda_oe   <= 1'b0;
        slv_byte_cnt <= 2'd0;
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
              slv_rx_shift <= {slv_rx_shift[6:0], i2c_sda_wire};
              if (slv_bit_cnt == 3'd0)
                slv_state <= SLV_ADDR_ACK;
              else
                slv_bit_cnt <= slv_bit_cnt - 3'd1;
            end
          end

          SLV_ADDR_ACK: begin
            if (scl_fall) begin
              // Adres uyuyor mu?
              if (slv_rx_shift[7:1] == I2C_SLAVE_ADDR) begin
                slv_sda_oe  <= 1'b1;   // ACK = SDA low
                slv_rw_bit  <= slv_rx_shift[0];
                slv_bit_cnt <= 3'd7;
                slv_byte_cnt <= 2'd0;
              end else begin
                slv_sda_oe <= 1'b0;     // NACK
                slv_state  <= SLV_IDLE;
              end
            end
            // ACK'den sonra, SCL tekrar düşünce veri fazına geç
            if (scl_rise && slv_sda_oe) begin
              // ACK gönderildi, SCL rise — hazırlan
            end
            if (scl_fall && slv_sda_oe) begin
              slv_sda_oe <= 1'b0;  // ACK bitti, SDA'yı bırak
              if (slv_rw_bit) begin
                // READ: slave veri gönderecek
                slv_tx_shift <= slv_mem[0];
                slv_state    <= SLV_RD_BIT;
              end else begin
                // WRITE: slave veri alacak
                slv_state <= SLV_WR_BIT;
              end
            end
          end

          // ── Write: Veri byte alma ──
          SLV_WR_BIT: begin
            if (scl_rise) begin
              slv_rx_shift <= {slv_rx_shift[6:0], i2c_sda_wire};
              if (slv_bit_cnt == 3'd0)
                slv_state <= SLV_WR_ACK;
              else
                slv_bit_cnt <= slv_bit_cnt - 3'd1;
            end
          end

          SLV_WR_ACK: begin
            if (scl_fall && !slv_sda_oe) begin
              // ACK gönder
              slv_sda_oe <= 1'b1;
              slv_mem[slv_byte_cnt] <= slv_rx_shift;
            end
            if (scl_fall && slv_sda_oe) begin
              // ACK bitti
              slv_sda_oe  <= 1'b0;
              slv_bit_cnt <= 3'd7;
              slv_byte_cnt <= slv_byte_cnt + 2'd1;
              slv_state   <= SLV_WR_BIT;
            end
          end

          // ── Read: Veri byte gönderme ──
          SLV_RD_BIT: begin
            if (scl_fall) begin
              // MSB-first: bit gönder
              slv_sda_oe <= !slv_tx_shift[7];  // bit=1→release, bit=0→drive
              slv_tx_shift <= {slv_tx_shift[6:0], 1'b0};
              if (slv_bit_cnt == 3'd0) begin
                slv_state <= SLV_RD_ACK_WAIT;
              end else begin
                slv_bit_cnt <= slv_bit_cnt - 3'd1;
              end
            end
          end

          SLV_RD_ACK_WAIT: begin
            if (scl_fall) begin
              slv_sda_oe <= 1'b0;  // SDA bırak, master ACK/NACK gönderecek
            end
            if (scl_rise) begin
              // Master ACK: SDA=0 → devam, NACK: SDA=1 → dur
              if (!i2c_sda_wire) begin
                // ACK — sonraki byte gönder
                slv_byte_cnt <= slv_byte_cnt + 2'd1;
                slv_tx_shift <= slv_mem[slv_byte_cnt + 2'd1];
                slv_bit_cnt  <= 3'd7;
                slv_state    <= SLV_RD_BIT;
              end else begin
                // NACK — dur
                slv_state <= SLV_IDLE;
              end
            end
          end

          default: slv_state <= SLV_IDLE;
        endcase
      end
    end
  end

  // ════════════════════════════════════════════════
  // Slave 2: SPI Master (Gerçek modül)
  // MOSI → MISO loopback ile test edilir (basit SPI slave modeli)
  // ════════════════════════════════════════════════
  logic spi_sck_wire;
  logic spi_mosi_wire;
  logic spi_miso_wire;
  logic [3:0] spi_ss_wire;
  logic spi_irq_wire;

  axi_spi #(
    .DEFAULT_CLK_DIV (8'd0)   // En hızlı: SCK half-period = 1 clk cycle
  ) u_axi_spi (
    .clk_i            (clk),
    .rstn_i           (rstn),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_SPI]),
    .s_axi_awprot_i   (slv_awprot  [SLV_SPI]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_SPI]),
    .s_axi_awready_o  (slv_awready [SLV_SPI]),
    .s_axi_wdata_i    (slv_wdata   [SLV_SPI]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_SPI]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_SPI]),
    .s_axi_wready_o   (slv_wready  [SLV_SPI]),
    .s_axi_bresp_o    (slv_bresp   [SLV_SPI]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_SPI]),
    .s_axi_bready_i   (slv_bready  [SLV_SPI]),
    .s_axi_araddr_i   (slv_araddr  [SLV_SPI]),
    .s_axi_arprot_i   (slv_arprot  [SLV_SPI]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_SPI]),
    .s_axi_arready_o  (slv_arready [SLV_SPI]),
    .s_axi_rdata_o    (slv_rdata   [SLV_SPI]),
    .s_axi_rresp_o    (slv_rresp   [SLV_SPI]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_SPI]),
    .s_axi_rready_i   (slv_rready  [SLV_SPI]),

    .sck_o            (spi_sck_wire),
    .mosi_o           (spi_mosi_wire),
    .miso_i           (spi_miso_wire),
    .ss_o             (spi_ss_wire),
    .irq_o            (spi_irq_wire)
  );

  // ── Basit SPI Slave Modeli ────────────────────────
  // CS aktif iken, MOSI'den gelen veriyi 1-cycle gecikmeyle MISO'ya döner
  // (shift register — her SCK kenarında MOSI'yi yakalar, MISO'dan çıkar)
  // SPI Mode 0 (CPOL=0, CPHA=0) için: sample on rising edge, shift on falling
  logic [7:0] spi_slv_shift = 8'hA5;   // Slave başlangıç verisi
  logic       spi_sck_prev  = 1'b0;

  always @(posedge clk) begin
    spi_sck_prev <= spi_sck_wire;
  end

  wire spi_sck_rise = !spi_sck_prev && spi_sck_wire;
  wire spi_sck_fall = spi_sck_prev && !spi_sck_wire;

  // Slave: rising edge'de MOSI sample, falling edge'de shift
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      spi_slv_shift <= 8'hA5;
    end else if (!spi_ss_wire[0]) begin  // CS0 aktif (low)
      if (spi_sck_rise) begin
        // Rising edge: sample MOSI, shift in
        spi_slv_shift <= {spi_slv_shift[6:0], spi_mosi_wire};
      end
    end else begin
      spi_slv_shift <= 8'hA5;  // CS deassert → reset
    end
  end

  // MISO: slave shift register'ın MSB'si
  assign spi_miso_wire = (!spi_ss_wire[0]) ? spi_slv_shift[7] : 1'b0;

  // ════════════════════════════════════════════════
  // AXI Transaction Task'ları
  // ════════════════════════════════════════════════  // --- AXI Write Transaction ---
  // Master IF'e mem_write isteği gönder, tamamlanmasını bekle
  task automatic axi_write(
    input logic [31:0] addr,
    input logic [31:0] data,
    input logic [1:0]  size   // 00=byte, 01=half, 10=word
  );
    // ready beklenmeli (önceki transaction bitmeli)
    while (!drv_ready) @(posedge clk);

    // İstek sinyallerini negedge'de set et — DUT posedge'de örnekler
    @(negedge clk);
    drv_mem_write    = 1'b1;
    drv_mem_read     = 1'b0;
    drv_addr         = addr;
    drv_wdata        = data;
    drv_mem_size     = size;
    drv_mem_unsigned = 1'b0;

    // 1 tam clock cycle sür — posedge'de FSM yakalar
    @(negedge clk);
    drv_mem_write = 1'b0;    // Transaction tamamlanana kadar bekle (ready tekrar 1 olacak)
    while (!drv_ready) @(posedge clk);
  endtask// --- AXI Read Transaction ---
  // Master IF'e mem_read isteği gönder, tamamlanmasını bekle, okunan veriyi döndür
  task automatic axi_read(
    input  logic [31:0] addr,
    input  logic [1:0]  size,
    output logic [31:0] rdata
  );
    while (!drv_ready) @(posedge clk);

    // negedge'de set et — posedge'de DUT örnekler
    @(negedge clk);
    drv_mem_read     = 1'b1;
    drv_mem_write    = 1'b0;
    drv_addr         = addr;
    drv_mem_size     = size;
    drv_mem_unsigned = 1'b1;

    // 1 tam clock cycle sür — posedge'de FSM yakalar
    @(negedge clk);
    drv_mem_read = 1'b0;    // Transaction tamamlanana kadar bekle
    while (!drv_ready) @(posedge clk);
    rdata = drv_rdata;
  endtask

  // --- Check helper ---
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
  // Ana Test Sekansı
  // ════════════════════════════════════════════════
  logic [31:0] rd_val;

  initial begin
    // Varsayılan sinyal değerleri
    drv_mem_read     = 1'b0;
    drv_mem_write    = 1'b0;
    drv_mem_size     = 2'b10;
    drv_mem_unsigned = 1'b0;
    drv_addr         = '0;
    drv_wdata        = '0;

    // Reset
    rstn = 1'b0;
    repeat (5) @(posedge clk);
    rstn = 1'b1;
    repeat (3) @(posedge clk);

    $display("");
    $display("════════════════════════════════════════════════════");
    $display(" SoC Entegrasyon Testi Baslatiliyor");
    $display("════════════════════════════════════════════════════");
    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 1: DMEM (Slave 0) Yazma & Okuma
    // Adres aralığı: 0x8001_0000 – 0x8001_7FFF
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 1: DMEM Yazma & Okuma ──────────────");

    // 1.1: Word yazma & okuma
    axi_write(32'h8001_0100, 32'hCAFE_BABE, 2'b10);
    axi_read (32'h8001_0100, 2'b10, rd_val);
    check("DMEM Word WR/RD @0x8001_0100", rd_val, 32'hCAFE_BABE);

    // 1.2: Farklı adrese word yazma & okuma
    axi_write(32'h8001_0200, 32'h1234_5678, 2'b10);
    axi_read (32'h8001_0200, 2'b10, rd_val);
    check("DMEM Word WR/RD @0x8001_0200", rd_val, 32'h1234_5678);

    // 1.3: İlk adresin hâlâ doğru olduğunu kontrol et (üst yazma yok)
    axi_read (32'h8001_0100, 2'b10, rd_val);
    check("DMEM Re-read @0x8001_0100", rd_val, 32'hCAFE_BABE);

    // 1.4: Sıfır yazma ve okuma
    axi_write(32'h8001_0300, 32'h0000_0000, 2'b10);
    axi_read (32'h8001_0300, 2'b10, rd_val);
    check("DMEM Zero WR/RD @0x8001_0300", rd_val, 32'h0000_0000);

    // 1.5: Max değer yazma
    axi_write(32'h8001_0304, 32'hFFFF_FFFF, 2'b10);
    axi_read (32'h8001_0304, 2'b10, rd_val);
    check("DMEM Max WR/RD @0x8001_0304", rd_val, 32'hFFFF_FFFF);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 2: DSP Filtre (Slave 4) Register Erişimi
    // Adres aralığı: 0x4000_1000 – 0x4000_1FFF
    // Register map:
    //   0x00: CTRL    [0]=enable, [1]=soft_reset, [2]=start
    //   0x04: STATUS  [0]=busy, [1]=out_valid
    //   0x08: DATA_IN [15:0] signed input sample
    //   0x0C: DATA_OUT_L [31:0]
    //   0x10: DATA_OUT_H [0]
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 2: DSP Register Erişimi ────────────");

    // 2.1: CTRL register — enable yazma & okuma
    axi_write(32'h4000_1000, 32'h0000_0001, 2'b10);  // enable=1
    axi_read (32'h4000_1000, 2'b10, rd_val);
    check("DSP CTRL enable set", rd_val[0], 1'b1);

    // 2.2: STATUS register okuma (başlangıçta busy=0, out_valid=0)
    axi_read (32'h4000_1004, 2'b10, rd_val);
    check("DSP STATUS initial", rd_val, 32'h0000_0000);

    // 2.3: DATA_IN register — örnek veri yazma
    axi_write(32'h4000_1008, 32'h0000_4000, 2'b10);  // 0x4000 = +0.5 Q1.15
    axi_read (32'h4000_1008, 2'b10, rd_val);
    check("DSP DATA_IN readback", rd_val[15:0], 16'h4000);

    // 2.4: Birden fazla sample yazarak filtreyi çalıştır
    // enable=1, birkaç sample gönder, sonra out_valid kontrol et
    axi_write(32'h4000_1008, 32'h0000_2000, 2'b10);  // +0.25
    axi_write(32'h4000_1008, 32'h0000_6000, 2'b10);  // +0.75

    // Filtrenin çalışması için birkaç cycle bekle
    repeat (20) @(posedge clk);

    // 2.5: STATUS okuma — out_valid set olmuş olmalı (filtre delay'e bağlı)
    axi_read (32'h4000_1004, 2'b10, rd_val);
    $display("[%0t] INFO: DSP STATUS after samples = 0x%08h (out_valid=%0b)",
             $time, rd_val, rd_val[1]);

    // 2.6: DATA_OUT_L okuma
    axi_read (32'h4000_100C, 2'b10, rd_val);
    $display("[%0t] INFO: DSP DATA_OUT_L = 0x%08h", $time, rd_val);

    // 2.7: DATA_OUT_H okuma
    axi_read (32'h4000_1010, 2'b10, rd_val);
    $display("[%0t] INFO: DSP DATA_OUT_H = 0x%08h", $time, rd_val);

    // 2.8: CTRL soft_reset — pulse yazma, tekrar okuma (bit otomatik temizlenir)
    axi_write(32'h4000_1000, 32'h0000_0003, 2'b10);  // enable + soft_reset
    repeat (3) @(posedge clk);
    axi_read (32'h4000_1000, 2'b10, rd_val);
    check("DSP CTRL soft_reset auto-clear", rd_val[1], 1'b0);  // pulse olmalı, temizlenmiş

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 3: UART Register Erişimi + Stub SLVERR
    // UART=0x4000_0000, SPI=0x4000_0100, I2C=0x4000_0200
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 3: UART Register + Stub SLVERR ────");

    // 3.1: UART STATUS register başlangıç okuması
    //   STATUS: [0]=tx_full, [1]=tx_empty, [2]=rx_full, [3]=rx_empty
    //   Başlangıçta TX FIFO boş (tx_empty=1), RX FIFO boş (rx_empty=1)
    //   Beklenen: bit[1]=1, bit[3]=1 → 0x0000_000A
    axi_read (32'h4000_0008, 2'b10, rd_val);
    check("UART STATUS initial", rd_val, 32'h0000_000A);

    // 3.2: UART CTRL register — TX ve RX etkinleştir
    axi_write(32'h4000_000C, 32'h0000_0003, 2'b10);  // tx_en=1, rx_en=1
    axi_read (32'h4000_000C, 2'b10, rd_val);
    check("UART CTRL tx+rx enable", rd_val, 32'h0000_0003);

    // 3.3: UART BAUD_DIV register yazma & okuma
    axi_write(32'h4000_0010, 32'h0000_0035, 2'b10);  // 53 = 115200 @ 100MHz
    axi_read (32'h4000_0010, 2'b10, rd_val);
    check("UART BAUD_DIV readback", rd_val, 32'h0000_0035);

    // 3.4: UART TX — veri yazma (TXDATA register)
    //   BAUD_DIV=0 → 16x tick her cycle → 10 bit * 16 tick = 160 cycle içinde loopback tamamlanır
    //   Önce hızlı baud için divisor'u 0'a çek
    axi_write(32'h4000_0010, 32'h0000_0000, 2'b10);  // BAUD_DIV=0
    axi_write(32'h4000_0000, 32'h0000_0055, 2'b10);  // TXDATA = 0x55

    // TX+RX loopback tamamlanmasını bekle (160+ cycle yeterli)
    repeat (250) @(posedge clk);

    // 3.5: UART RX — loopback verisi okunmalı
    axi_read (32'h4000_0004, 2'b10, rd_val);
    check("UART RX loopback data", rd_val[7:0], 8'h55);

    // 3.6: SPI STATUS başlangıç okuması
    //   STATUS: [0]=busy, [1]=rx_valid, [2]=ready
    //   en=0 iken ready=0 (ready = idle && en)
    axi_read (32'h4000_0108, 2'b10, rd_val);
    check("SPI STATUS initial", rd_val, 32'h0000_0000);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 3A: SPI Register Erişimi + Transfer
    // SPI Base = 0x4000_0100
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 3A: SPI Register + Transfer ───────");

    // 3A.1: SPI CTRL — enable + Mode 0 (cpol=0,cpha=0) + CS0 assert
    //   CTRL: [0]=en, [1]=cpol, [2]=cpha, [3]=ie, [5:4]=cs_sel, [6]=cs_en
    //   Değer: en=1, cpol=0, cpha=0, ie=0, cs_sel=0, cs_en=1 → 0x41
    axi_write(32'h4000_010C, 32'h0000_0041, 2'b10);
    axi_read (32'h4000_010C, 2'b10, rd_val);
    check("SPI CTRL en+cs0", rd_val, 32'h0000_0041);

    // 3A.2: STATUS — ready=1 olmalı (en=1, IDLE)
    axi_read (32'h4000_0108, 2'b10, rd_val);
    check("SPI STATUS ready after en", rd_val[2], 1'b1);

    // 3A.3: CLK_DIV register yazma & okuma
    axi_write(32'h4000_0110, 32'h0000_0031, 2'b10);  // CLK_DIV=49 → 1MHz
    axi_read (32'h4000_0110, 2'b10, rd_val);
    check("SPI CLK_DIV readback", rd_val, 32'h0000_0031);

    // Simülasyon hızı için CLK_DIV=0'a geri çek
    axi_write(32'h4000_0110, 32'h0000_0000, 2'b10);

    // 3A.4: TXDATA register yazma & okuma
    axi_write(32'h4000_0100, 32'h0000_00A5, 2'b10);  // TX=0xA5
    axi_read (32'h4000_0100, 2'b10, rd_val);
    check("SPI TXDATA readback", rd_val[7:0], 8'hA5);

    // 3A.5: SPI Transfer — MOSI→Slave shift register→MISO loopback
    //   Slave başlangıç shift = 0xA5 (reset değeri)
    //   Master TX = 0xA5 → slave MISO'dan MSB-first slave shift register çıkar
    //   MISO'dan okunan: slave'in 0xA5 shift değeri
    //   CLK_DIV=0 → half-period=1 clk → 8 bit = 16 clk SCK + overhead
    axi_write(32'h4000_0100, 32'h0000_00A5, 2'b10);  // TXDATA = 0xA5
    axi_write(32'h4000_0114, 32'h0000_0001, 2'b10);  // CMD start=1

    // Transfer tamamlanmasını bekle
    repeat (100) @(posedge clk);

    // 3A.6: STATUS — rx_valid=1 olmalı
    axi_read (32'h4000_0108, 2'b10, rd_val);
    check("SPI STATUS rx_valid after xfer", rd_val[1], 1'b1);

    // 3A.7: RXDATA — slave'den gelen veri
    axi_read (32'h4000_0104, 2'b10, rd_val);
    $display("[%0t] INFO: SPI RXDATA = 0x%02h", $time, rd_val[7:0]);

    // 3A.8: İkinci transfer — farklı veri
    //   STATUS'a yaz → rx_valid temizle
    axi_write(32'h4000_0108, 32'h0000_0000, 2'b10);  // rx_valid clear

    axi_write(32'h4000_0100, 32'h0000_0055, 2'b10);  // TXDATA = 0x55
    axi_write(32'h4000_0114, 32'h0000_0001, 2'b10);  // CMD start

    repeat (100) @(posedge clk);

    // 3A.9: rx_valid = 1 tekrar
    axi_read (32'h4000_0108, 2'b10, rd_val);
    check("SPI STATUS rx_valid 2nd xfer", rd_val[1], 1'b1);

    // 3A.10: RXDATA okuma
    axi_read (32'h4000_0104, 2'b10, rd_val);
    $display("[%0t] INFO: SPI RXDATA 2nd = 0x%02h", $time, rd_val[7:0]);

    // 3A.11: CS deassert — CTRL cs_en=0
    axi_write(32'h4000_010C, 32'h0000_0001, 2'b10);  // en=1, cs_en=0
    axi_read (32'h4000_010C, 2'b10, rd_val);
    check("SPI CTRL cs_deassert", rd_val[6], 1'b0);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 3B: I2C Register Erişimi
    // I2C Base = 0x4000_0200
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 3B: I2C Register Erişimi ──────────");

    // 3.7: I2C STATUS başlangıç okuması
    //   STATUS: [0]=busy, [1]=ack_err, [2]=rx_valid, [3]=cmd_ready
    //   Başlangıçta: busy=0, ack_err=0, rx_valid=0, cmd_ready=1 (IDLE ve en=0 ama bakalım)
    //   NOT: en_i=0 olduğu için cmd_ready_o = 0 (cmd_ready = idle && en)
    axi_read (32'h4000_0208, 2'b10, rd_val);
    check("I2C STATUS initial", rd_val, 32'h0000_0000);

    // 3.8: I2C CTRL register — enable
    axi_write(32'h4000_020C, 32'h0000_0001, 2'b10);  // en=1
    axi_read (32'h4000_020C, 2'b10, rd_val);
    check("I2C CTRL enable set", rd_val, 32'h0000_0001);

    // 3.9: STATUS tekrar — en=1 ise cmd_ready=1 olmalı
    axi_read (32'h4000_0208, 2'b10, rd_val);
    check("I2C STATUS cmd_ready after en", rd_val[3], 1'b1);

    // 3.10: I2C PRESCALE register yazma & okuma
    axi_write(32'h4000_0210, 32'h0000_003E, 2'b10);  // 62 → 400kHz @ 100MHz
    axi_read (32'h4000_0210, 2'b10, rd_val);
    check("I2C PRESCALE readback", rd_val, 32'h0000_003E);

    // 3.11: PRESCALE'i test için düşük tut (default=1, geri yükle)
    axi_write(32'h4000_0210, 32'h0000_0001, 2'b10);

    // 3.12: I2C TXDATA register yazma & okuma
    axi_write(32'h4000_0200, 32'h0000_00A0, 2'b10);  // slave addr 0x50 << 1 = 0xA0 (write)
    axi_read (32'h4000_0200, 2'b10, rd_val);
    check("I2C TXDATA readback", rd_val[7:0], 8'hA0);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 3C: I2C İşlem Testi (START + WRITE + STOP)
    // Slave adresi = 0x50, yazma işlemi, veri = 0x5A
    // TB'deki basit slave modeli ACK verecek
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 3C: I2C Transaction ───────────────");

    // TXDATA = slave addr byte (0x50<<1 | 0 = 0xA0 = write)
    axi_write(32'h4000_0200, 32'h0000_00A0, 2'b10);

    // CMD = START (001)
    axi_write(32'h4000_0214, 32'h0000_0001, 2'b10);

    // cmd_ready bekle
    repeat (200) @(posedge clk);
    axi_read (32'h4000_0208, 2'b10, rd_val);
    $display("[%0t] INFO: I2C STATUS after START = 0x%08h", $time, rd_val);

    // CMD = WRITE_BYTE (010) — adres byte gönder
    axi_write(32'h4000_0214, 32'h0000_0002, 2'b10);

    // Yazma + ACK tamamlanmasını bekle (8 bit + 1 ACK = 9*SCL period)
    // SCL period = 4*(1+1) = 8 clk, 9*8 = 72 clk + margin
    repeat (200) @(posedge clk);

    // 3.13: ACK hatası olmamalı — slave 0x50 adresi tanıyor
    axi_read (32'h4000_0208, 2'b10, rd_val);
    check("I2C addr write no ACK err", rd_val[1], 1'b0);

    // TXDATA = veri byte (0x5A)
    axi_write(32'h4000_0200, 32'h0000_005A, 2'b10);

    // CMD = WRITE_BYTE (010) — veri byte gönder
    axi_write(32'h4000_0214, 32'h0000_0002, 2'b10);
    repeat (200) @(posedge clk);

    // 3.14: Veri yazma ACK hatası yok
    axi_read (32'h4000_0208, 2'b10, rd_val);
    check("I2C data write no ACK err", rd_val[1], 1'b0);

    // CMD = STOP (101)
    axi_write(32'h4000_0214, 32'h0000_0005, 2'b10);
    repeat (200) @(posedge clk);

    // 3.15: I2C busy=0 olmalı (STOP tamamlandı)
    axi_read (32'h4000_0208, 2'b10, rd_val);
    check("I2C idle after STOP", rd_val[0], 1'b0);

    // 3.16: Slave'in belleğinde yazılan veri doğru mu? (0x5A)
    check("I2C slave mem[0] = 0x5A", {24'd0, slv_mem[0]}, 32'h0000_005A);

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 4: DMEM → Ardışık Erişim Dayanıklılık
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 4: DMEM Ardışık Erişim ─────────────");

    // 4.1: 8 ardışık word yazma
    for (int i = 0; i < 8; i++) begin
      axi_write(32'h8001_0400 + (i * 4), 32'hA000_0000 + i, 2'b10);
    end

    // 4.2: 8 ardışık word okuma ve doğrulama
    for (int i = 0; i < 8; i++) begin
      automatic string tname;
      axi_read(32'h8001_0400 + (i * 4), 2'b10, rd_val);
      $sformat(tname, "DMEM sequential[%0d]", i);
      check(tname, rd_val, 32'hA000_0000 + i);
    end

    $display("");

    // ──────────────────────────────────────────────
    // TEST GRUBU 5: DSP → DMEM Karışık Erişim
    // Bir slave'e yazıp diğerinden okuma — çapraz kontaminasyon yok
    // ──────────────────────────────────────────────
    $display("── TEST GRUBU 5: DSP ↔ DMEM Çapraz Kontrol ──────");

    // DMEM'e belirli bir veri yaz
    axi_write(32'h8001_0500, 32'hBEEF_DEAD, 2'b10);

    // DSP CTRL register'a yaz
    axi_write(32'h4000_1000, 32'h0000_0001, 2'b10);

    // DMEM'i okuyup orijinal veriyi kontrol et
    axi_read (32'h8001_0500, 2'b10, rd_val);
    check("DMEM after DSP access", rd_val, 32'hBEEF_DEAD);

    // DSP CTRL register'ı okuyup doğru değeri kontrol et
    axi_read (32'h4000_1000, 2'b10, rd_val);
    check("DSP CTRL after DMEM access", rd_val[0], 1'b1);

    $display("");

    // ──────────────────────────────────────────────
    // Sonuç Raporu
    // ──────────────────────────────────────────────
    $display("════════════════════════════════════════════════════");
    $display(" SoC Entegrasyon Testi TAMAMLANDI");
    $display(" Toplam: %0d  |  PASS: %0d  |  FAIL: %0d",
             test_num, pass_cnt, fail_cnt);
    $display("════════════════════════════════════════════════════");

    if (fail_cnt > 0)
      $fatal(1, "ENTEGRASYON TESTI BASARISIZ — %0d hata!", fail_cnt);
    else
      $display("[TB] TUM TESTLER BASARILI.\n");

    $finish;
  end
  // ════════════════════════════════════════════════
  // Watchdog timer
  // ════════════════════════════════════════════════
  initial begin
    #200_000;
    $fatal(1, "[WATCHDOG] Zaman asimi — test 200us icinde bitmedi!");
  end
  // ════════════════════════════════════════════════
  // Debug: Master IF + DMEM Slave state monitor
  // Aktifleştirmek için: xvlog ... -d DEBUG_MON
  // ════════════════════════════════════════════════
`ifdef DEBUG_MON
  always @(posedge clk) begin
    if ($time < 100_000 && rstn) begin
      $display("[%0t] MON: mst_state=%0d ready=%0b | arvalid=%0b arready=%0b araddr=0x%08h | rvalid=%0b rready=%0b rdata=0x%08h | awvalid=%0b awready=%0b | wvalid=%0b wready=%0b | bvalid=%0b bready=%0b | dmem_state=%0d dmem_mem_rd=%0b dmem_mem_wr=%0b dmem_rdata=0x%08h",
               $time,
               u_axi_master.state_q, drv_ready,
               mst_arvalid, mst_arready, mst_araddr,
               mst_rvalid, mst_rready, mst_rdata,
               mst_awvalid, mst_awready,
               mst_wvalid, mst_wready,
               mst_bvalid, mst_bready,
               u_axi_dmem.state_q, u_axi_dmem.mem_read, u_axi_dmem.mem_write, u_axi_dmem.mem_rdata);
    end
  end
`endif

  // ════════════════════════════════════════════════
  // Opsiyonel VCD dump
  // ════════════════════════════════════════════════
  initial begin
    $dumpfile("tb_soc_integration.vcd");
    $dumpvars(0, tb_soc_integration);
  end

endmodule
