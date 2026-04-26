// filepath: rtl/bus/axi_pkg.sv
// AXI4-Lite parametre ve typedef tanımları
// Tüm AXI modülleri bu paketi import eder
`timescale 1ns / 1ps

package axi_pkg;

  // ────────────────────────────────────────────────
  // Genel AXI Parametreleri
  // ────────────────────────────────────────────────
  localparam int AXI_ADDR_WIDTH  = 32;
  localparam int AXI_DATA_WIDTH  = 32;
  localparam int AXI_STRB_WIDTH  = AXI_DATA_WIDTH / 8;  // 4

  // ────────────────────────────────────────────────
  // AXI Response Kodları (RRESP / BRESP)
  // ────────────────────────────────────────────────
  localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
  localparam logic [1:0] AXI_RESP_EXOKAY = 2'b01;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
  localparam logic [1:0] AXI_RESP_DECERR = 2'b11;

  // ────────────────────────────────────────────────
  // Memory Map — Slave Sayısı ve Adres Aralıkları
  // ────────────────────────────────────────────────
  localparam int NUM_SLAVES = 8;   // DMEM, UART, SPI, I2C, DSP, DQN, GPIO, INT_GEN

  // Slave indeksleri
  localparam int SLV_DMEM    = 0;
  localparam int SLV_UART    = 1;
  localparam int SLV_SPI     = 2;
  localparam int SLV_I2C     = 3;
  localparam int SLV_DSP     = 4;
  localparam int SLV_DQN     = 5;
  localparam int SLV_GPIO    = 6;
  localparam int SLV_INTGEN  = 7;

  // Her slave'in base ve mask değeri (addr & ~MASK == BASE ise eşleşir)
  // DMEM     : 0x8001_0000 – 0x8001_7FFF  (32 KB)
  // UART     : 0x4000_0000 – 0x4000_00FF  (256 B)
  // SPI      : 0x4000_0100 – 0x4000_01FF  (256 B)
  // I2C      : 0x4000_0200 – 0x4000_02FF  (256 B)
  // DSP      : 0x4000_1000 – 0x4000_1FFF  (4 KB)
  // DQN      : 0x4000_2000 – 0x4000_2FFF  (4 KB)
  // GPIO     : 0xA000_0000 – 0xA000_0FFF  (4 KB)
  // INT_GEN  : 0xC000_0000 – 0xC000_0FFF  (4 KB)

  localparam logic [AXI_ADDR_WIDTH-1:0] SLV_BASE [NUM_SLAVES] = '{
    32'h8001_0000,  // DMEM
    32'h4000_0000,  // UART
    32'h4000_0100,  // SPI
    32'h4000_0200,  // I2C
    32'h4000_1000,  // DSP
    32'h4000_2000,  // DQN
    32'hA000_0000,  // GPIO
    32'hC000_0000   // INT_GEN
  };

  localparam logic [AXI_ADDR_WIDTH-1:0] SLV_MASK [NUM_SLAVES] = '{
    32'h0000_7FFF,  // DMEM     32 KB
    32'h0000_00FF,  // UART     256 B
    32'h0000_00FF,  // SPI      256 B
    32'h0000_00FF,  // I2C      256 B
    32'h0000_0FFF,  // DSP      4 KB
    32'h0000_0FFF,  // DQN      4 KB
    32'h0000_0FFF,  // GPIO     4 KB
    32'h0000_0FFF   // INT_GEN  4 KB
  };

  // ────────────────────────────────────────────────
  // AXI4-Lite Write Address Channel
  // ────────────────────────────────────────────────
  typedef struct packed {
    logic [AXI_ADDR_WIDTH-1:0] awaddr;
    logic [2:0]                awprot;
    logic                      awvalid;
  } axi_aw_m2s_t;   // master → slave

  typedef struct packed {
    logic                      awready;
  } axi_aw_s2m_t;   // slave → master

  // ────────────────────────────────────────────────
  // AXI4-Lite Write Data Channel
  // ────────────────────────────────────────────────
  typedef struct packed {
    logic [AXI_DATA_WIDTH-1:0] wdata;
    logic [AXI_STRB_WIDTH-1:0] wstrb;
    logic                      wvalid;
  } axi_w_m2s_t;

  typedef struct packed {
    logic                      wready;
  } axi_w_s2m_t;

  // ────────────────────────────────────────────────
  // AXI4-Lite Write Response Channel
  // ────────────────────────────────────────────────
  typedef struct packed {
    logic [1:0]                bresp;
    logic                      bvalid;
  } axi_b_s2m_t;

  typedef struct packed {
    logic                      bready;
  } axi_b_m2s_t;

  // ────────────────────────────────────────────────
  // AXI4-Lite Read Address Channel
  // ────────────────────────────────────────────────
  typedef struct packed {
    logic [AXI_ADDR_WIDTH-1:0] araddr;
    logic [2:0]                arprot;
    logic                      arvalid;
  } axi_ar_m2s_t;

  typedef struct packed {
    logic                      arready;
  } axi_ar_s2m_t;

  // ────────────────────────────────────────────────
  // AXI4-Lite Read Data Channel
  // ────────────────────────────────────────────────
  typedef struct packed {
    logic [AXI_DATA_WIDTH-1:0] rdata;
    logic [1:0]                rresp;
    logic                      rvalid;
  } axi_r_s2m_t;

  typedef struct packed {
    logic                      rready;
  } axi_r_m2s_t;

  // ────────────────────────────────────────────────
  // Toplu master-to-slave / slave-to-master struct'ları
  // ────────────────────────────────────────────────
  typedef struct packed {
    axi_aw_m2s_t aw;
    axi_w_m2s_t  w;
    axi_b_m2s_t  b;
    axi_ar_m2s_t ar;
    axi_r_m2s_t  r;
  } axi_lite_m2s_t;

  typedef struct packed {
    axi_aw_s2m_t aw;
    axi_w_s2m_t  w;
    axi_b_s2m_t  b;
    axi_ar_s2m_t ar;
    axi_r_s2m_t  r;
  } axi_lite_s2m_t;

endpackage
