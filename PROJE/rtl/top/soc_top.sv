// filepath: rtl/top/soc_top.sv
// SoC Üst Modül
// RISC-V Core → AXI Master IF → AXI Interconnect → Slave'ler
// Şu an aktif slave: DMEM. UART/SPI/I2C/DSP slave portları dışarıya açık.
`timescale 1ns / 1ps

module soc_top
  import riscv_pkg::*;
  import axi_pkg::*;
#(
  parameter string IMEM_INIT_FILE = "C:/Users/DELL/Downloads/HexaCore-V2/PROJE/imem.mem",
  parameter string DMEM_INIT_FILE = "C:/Users/DELL/Downloads/HexaCore-V2/PROJE/dmem.mem"
)(
  input  logic             clk_i,
  input  logic             rstn_i,

  // ── Debug / Scoreboard portları ─────────────────
  input  logic [XLEN-1:0]  dbg_addr_i,
  output logic [XLEN-1:0]  dbg_data_o,

  output logic              update_o,
  output logic [XLEN-1:0]  pc_o,
  output logic [XLEN-1:0]  instr_o,
  output logic [4:0]       reg_addr_o,
  output logic [XLEN-1:0]  reg_data_o,
  output logic [XLEN-1:0]  mem_addr_o,
  output logic [XLEN-1:0]  mem_data_o,
  output logic              mem_wrt_o,
  output logic              mem_read_o,

  // ── Periferal dış bağlantı portları (ileride bağlanacak) ──
  // UART
  output logic              uart_tx_o,
  input  logic              uart_rx_i,
  output logic              uart_irq_o,

  // SPI
  output logic              spi_sck_o,
  output logic              spi_mosi_o,
  input  logic              spi_miso_i,
  output logic [3:0]        spi_ss_o,

  // I2C
  inout  wire               i2c_sda_io,
  inout  wire               i2c_scl_io,

  // DSP AXI-Stream (opsiyonel — ileride bağlanacak)
  input  logic [31:0]       dsp_s_tdata_i,
  input  logic              dsp_s_tvalid_i,
  output logic              dsp_s_tready_o,
  input  logic              dsp_s_tlast_i,
  output logic [31:0]       dsp_m_tdata_o,
  output logic              dsp_m_tvalid_o,
  input  logic              dsp_m_tready_i,
  output logic              dsp_m_tlast_o
);

  // ════════════════════════════════════════════════
  // Varsayılan atamalar — henüz bağlanmamış portlar
  // ════════════════════════════════════════════════
  assign uart_tx_o      = 1'b1;     // idle-high
  assign uart_irq_o     = 1'b0;
  assign spi_sck_o      = 1'b0;
  assign spi_mosi_o     = 1'b0;
  assign spi_ss_o       = 4'b1111;  // tüm CS deassert
  assign dsp_s_tready_o = 1'b0;
  assign dsp_m_tdata_o  = '0;
  assign dsp_m_tvalid_o = 1'b0;
  assign dsp_m_tlast_o  = 1'b0;

  // ════════════════════════════════════════════════
  // AXI Master IF ↔ Interconnect arası sinyaller
  // ════════════════════════════════════════════════
  logic [AXI_ADDR_WIDTH-1:0]   mst_awaddr;
  logic [2:0]                  mst_awprot;
  logic                        mst_awvalid;
  logic                        mst_awready;

  logic [AXI_DATA_WIDTH-1:0]   mst_wdata;
  logic [AXI_STRB_WIDTH-1:0]   mst_wstrb;
  logic                        mst_wvalid;
  logic                        mst_wready;

  logic [1:0]                  mst_bresp;
  logic                        mst_bvalid;
  logic                        mst_bready;

  logic [AXI_ADDR_WIDTH-1:0]   mst_araddr;
  logic [2:0]                  mst_arprot;
  logic                        mst_arvalid;
  logic                        mst_arready;

  logic [AXI_DATA_WIDTH-1:0]   mst_rdata;
  logic [1:0]                  mst_rresp;
  logic                        mst_rvalid;
  logic                        mst_rready;

  // ════════════════════════════════════════════════
  // Interconnect ↔ Slave sinyalleri
  // ════════════════════════════════════════════════
  logic [AXI_ADDR_WIDTH-1:0]   slv_awaddr  [NUM_SLAVES];
  logic [2:0]                  slv_awprot  [NUM_SLAVES];
  logic                        slv_awvalid [NUM_SLAVES];
  logic                        slv_awready [NUM_SLAVES];

  logic [AXI_DATA_WIDTH-1:0]   slv_wdata   [NUM_SLAVES];
  logic [AXI_STRB_WIDTH-1:0]   slv_wstrb   [NUM_SLAVES];
  logic                        slv_wvalid  [NUM_SLAVES];
  logic                        slv_wready  [NUM_SLAVES];

  logic [1:0]                  slv_bresp   [NUM_SLAVES];
  logic                        slv_bvalid  [NUM_SLAVES];
  logic                        slv_bready  [NUM_SLAVES];

  logic [AXI_ADDR_WIDTH-1:0]   slv_araddr  [NUM_SLAVES];
  logic [2:0]                  slv_arprot  [NUM_SLAVES];
  logic                        slv_arvalid [NUM_SLAVES];
  logic                        slv_arready [NUM_SLAVES];

  logic [AXI_DATA_WIDTH-1:0]   slv_rdata   [NUM_SLAVES];
  logic [1:0]                  slv_rresp   [NUM_SLAVES];
  logic                        slv_rvalid  [NUM_SLAVES];
  logic                        slv_rready  [NUM_SLAVES];

  // ════════════════════════════════════════════════
  // RISC-V Core Instance
  // (riscv_pipeline portlarını mevcut haliyle kullanıyoruz)
  // ════════════════════════════════════════════════
  riscv_pipeline #(
    .IMemInitFile (IMEM_INIT_FILE),
    .DMemInitFile (DMEM_INIT_FILE)
  ) u_core (
    .clk_i      (clk_i),
    .rstn_i     (rstn_i),
    .addr_i     (dbg_addr_i),
    .data_o     (dbg_data_o),
    .update_o   (update_o),
    .pc_o       (pc_o),
    .instr_o    (instr_o),
    .reg_addr_o (reg_addr_o),
    .reg_data_o (reg_data_o),
    .mem_addr_o (mem_addr_o),
    .mem_data_o (mem_data_o),
    .mem_wrt_o  (mem_wrt_o),
    .mem_read_o (mem_read_o)
  );

  // ════════════════════════════════════════════════
  // NOT: Mevcut riscv_pipeline DMEM'i dahili olarak kullanıyor.
  // AXI Master Bridge'e geçiş için pipeline'a yeni portlar eklemek
  // veya pipeline'ı wrapper ile sarmak gerekecek.
  //
  // ŞİMDİLİK: AXI altyapısı hazır, ama Core hâlâ kendi DMEM'ini
  // dahili olarak kullanmaya devam ediyor.
  // Aşağıdaki AXI Master IF örnek olarak bağlanmıştır;
  // pipeline modifiye edildiğinde aktif hale gelecektir.
  // ════════════════════════════════════════════════

  // Placeholder sinyaller — pipeline AXI portlarına sahip olduğunda bunlar bağlanacak
  logic             core_mem_read;
  logic             core_mem_write;
  logic [1:0]       core_mem_size;
  logic             core_mem_unsigned;
  logic [XLEN-1:0]  core_mem_addr;
  logic [XLEN-1:0]  core_mem_wdata;
  logic [XLEN-1:0]  core_mem_rdata;
  logic             core_mem_ready;

  // Şimdilik idle — pipeline dönüştürüldüğünde bağlanacak
  assign core_mem_read     = 1'b0;
  assign core_mem_write    = 1'b0;
  assign core_mem_size     = 2'b10;
  assign core_mem_unsigned = 1'b0;
  assign core_mem_addr     = '0;
  assign core_mem_wdata    = '0;

  // ════════════════════════════════════════════════
  // AXI Master Interface
  // ════════════════════════════════════════════════
  axi_master_if u_axi_master (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    // Pipeline MEM-stage
    .mem_read_i       (core_mem_read),
    .mem_write_i      (core_mem_write),
    .mem_size_i       (core_mem_size),
    .mem_unsigned_i   (core_mem_unsigned),
    .addr_i           (core_mem_addr),
    .wdata_i          (core_mem_wdata),
    .rdata_o          (core_mem_rdata),
    .ready_o          (core_mem_ready),

    // AXI4-Lite Master
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
  // AXI Interconnect
  // ════════════════════════════════════════════════
  axi_interconnect u_interconnect (
    .clk_i         (clk_i),
    .rstn_i        (rstn_i),

    // Master
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

    // Slaves
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
  axi_dmem_slave #(
    .DMEM_INIT_FILE (DMEM_INIT_FILE),
    .DMEM_BASE      (32'h8001_0000),
    .DMEM_BYTES     (32768)
  ) u_axi_dmem (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

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

    .dbg_addr_i       (dbg_addr_i),
    .dbg_data_o       ()  // debug için ayrı kullanılabilir
  );
  // ════════════════════════════════════════════════
  // Slave 4: DSP FIR Filtre (AXI4-Lite Wrapper)
  // Adres: 0x4000_1000 – 0x4000_1FFF (4 KB)
  // ════════════════════════════════════════════════
  dsp_filter_wrapper u_dsp_filter (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

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
  // Slave 1–3: UART, SPI, I2C — henüz bağlanmadı
  // Varsayılan yanıtlar: SLVERR + sinyaller deassert
  // Periferaller eklendikçe bu bloklar gerçek modüllerle değiştirilecek.
  // ════════════════════════════════════════════════
  generate
    for (genvar i = 1; i <= 3; i++) begin : gen_stub_slaves
      // Her zaman hazır ol, hemen SLVERR yanıtı dön
      assign slv_awready[i] = 1'b1;
      assign slv_wready [i] = 1'b1;
      assign slv_bresp  [i] = AXI_RESP_SLVERR;
      assign slv_bvalid [i] = slv_awvalid[i] | slv_wvalid[i];

      assign slv_arready[i] = 1'b1;
      assign slv_rdata  [i] = 32'hDEAD_DEAD;
      assign slv_rresp  [i] = AXI_RESP_SLVERR;
      assign slv_rvalid [i] = slv_arvalid[i];
    end
  endgenerate

  // ════════════════════════════════════════════════
  // Slave 5: DQN Inference Accelerator (AXI4-Lite Wrapper)
  // Adres: 0x4000_2000 – 0x4000_2FFF (4 KB)
  // Kucuk DQN: 4->16->4, Q1.15, sadece inference
  // ════════════════════════════════════════════════
  dqn_accelerator u_dqn_accel (
    .clk_i            (clk_i),
    .rstn_i           (rstn_i),

    .s_axi_awaddr_i   (slv_awaddr  [SLV_DQN]),
    .s_axi_awprot_i   (slv_awprot  [SLV_DQN]),
    .s_axi_awvalid_i  (slv_awvalid [SLV_DQN]),
    .s_axi_awready_o  (slv_awready [SLV_DQN]),
    .s_axi_wdata_i    (slv_wdata   [SLV_DQN]),
    .s_axi_wstrb_i    (slv_wstrb   [SLV_DQN]),
    .s_axi_wvalid_i   (slv_wvalid  [SLV_DQN]),
    .s_axi_wready_o   (slv_wready  [SLV_DQN]),
    .s_axi_bresp_o    (slv_bresp   [SLV_DQN]),
    .s_axi_bvalid_o   (slv_bvalid  [SLV_DQN]),
    .s_axi_bready_i   (slv_bready  [SLV_DQN]),
    .s_axi_araddr_i   (slv_araddr  [SLV_DQN]),
    .s_axi_arprot_i   (slv_arprot  [SLV_DQN]),
    .s_axi_arvalid_i  (slv_arvalid [SLV_DQN]),
    .s_axi_arready_o  (slv_arready [SLV_DQN]),
    .s_axi_rdata_o    (slv_rdata   [SLV_DQN]),
    .s_axi_rresp_o    (slv_rresp   [SLV_DQN]),
    .s_axi_rvalid_o   (slv_rvalid  [SLV_DQN]),
    .s_axi_rready_i   (slv_rready  [SLV_DQN])
  );

endmodule
