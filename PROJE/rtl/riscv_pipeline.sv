//`include "pkg/riscv_pkg.sv"
/* verilator lint_off IMPORTSTAR */


// A�a��da bulunan output siyalleri tasarlad���n�z risc-v i�lemcinin log dosyalas�n� doldurmak i�in kullan�lacak
// yani �rnek olarak update_o sinyali i�lemcideki de�i�imin logunun bas�lmas� i�in valid sinyali olacak,
// valid sinyaliniz 1 oldu�unda reg_addr_o sinyalinde gelen bilgi log dosyas�n�n ilgili k�s�m�na d�zg�n
// formatta bas�lacak.


// 
//  data_o ve addr_i sinyallerine bit uzunlu�una uygun "0" ba�lay�n.
// 

// retire terimi kullanma sebebimiz o cycle'daki i�lemin bitti�i noktada verilecek sinyaller olmas�d�r.
// Memory read ve write sinyali memory �zerindeki de�i�imi loglaman�z i�indir. Memory'nize ba�lamak kendi 
// tercihinize ba�l�d�r. Yani, memory'nizde de�i�im olaca��n� instructiondan anlay�p sinyal belirleyebilirsiniz.
//

//
// Kurman�z beklenen sistemde as�l olan de�i�imleri anlamak ve g�stermektir. ��lemci gibi b�y�k sistemlerin testlerini
// waveform �zerinden yapmak imkans�z olaca�� i�in burada otomatik bir kontrol sistemine uyum sa�layacak bir kontrol loglama
// sistemi kurman�z gerekiyor. ��lemci mimarisi ��renmenizin yan�nda bu �devin size kazand�rmas�n� hedefledi�imiz �ey budur.
//

module riscv_pipeline
  import riscv_pkg::*;
#(
  parameter string DMemInitFile = "dmem.mem",
  parameter string IMemInitFile = "imem.mem",
  parameter int    INT_DMEM_BYTES = 32768   // Dahili DMEM boyutu (byte)
)(
  input  logic             clk_i,
  input  logic             rstn_i,

  // debug arabirimi (DMEM i�inden okunur)
  input  logic  [XLEN-1:0] addr_i,
  output logic  [XLEN-1:0] data_o,

  // retire/scoreboard portlar�
  output logic             update_o,
  output logic [XLEN-1:0]  pc_o,
  output logic [XLEN-1:0]  instr_o,
  output logic [4:0]       reg_addr_o,
  output logic [XLEN-1:0]  reg_data_o,
  output logic [XLEN-1:0]  mem_addr_o,
  output logic [XLEN-1:0]  mem_data_o,
  output logic             mem_wrt_o,
  output logic             mem_read_o,

  // ── Harici bellek arayüzü (AXI yolu) ───────────
  // Dahili DMEM aralığı dışındaki adresler bu porttan yönlendirilir.
  // Varsayılan değerler: eski TB'ler (ext portları bağlamayan) için geri uyumlu.
  output logic              ext_mem_read_o,
  output logic              ext_mem_write_o,
  output logic [1:0]        ext_mem_size_o,
  output logic              ext_mem_unsigned_o,
  output logic [XLEN-1:0]  ext_mem_addr_o,
  output logic [XLEN-1:0]  ext_mem_wdata_o,
  input  logic [XLEN-1:0]  ext_mem_rdata_i  = '0,
  input  logic              ext_mem_ready_i  = 1'b1
);

  localparam logic [XLEN-1:0] IMEM_BASE = 32'h8000_0000;

  // ═══ Dahili DMEM adres aralığı ═══════════════════
  // [IMEM_BASE, IMEM_BASE + INT_DMEM_BYTES) → dahili DMEM
  // Bunun dışındaki tüm adresler → harici AXI yolu
  localparam logic [XLEN-1:0] INT_DMEM_END = IMEM_BASE + XLEN'(INT_DMEM_BYTES);

  // ═══ Harici bellek erişim kontrol sinyalleri ═════
  // (Tanımlar burada, atamalar MEM aşamasında)
  wire is_int_dmem;          // MEM adresi dahili DMEM aralığında mı?
  wire is_ext_access;        // AXI'ye yönlendirilecek erişim var mı?
  wire ext_stall_w;          // Pipeline dondurma: AXI yanıt bekliyor

  // ????????????????????????????????????????????????? IF ?????????????????????????????????????????????????
  logic [XLEN-1:0] pcF, pcPlus4F;
  logic [XLEN-1:0] instrF;
  logic            stallF, stallD, flushD, flushE;

  logic            pcSrcE;
  logic [XLEN-1:0] pcTargetE;

  assign pcPlus4F = pcF + 32'd4;

  // redirect geldi�inde stall, PC'yi engellemesin (redirect �ncelikli)
  wire stallF_eff = stallF && !pcSrcE;

  always_ff @(posedge clk_i) begin
    if (!rstn_i)            pcF <= IMEM_BASE;
    else if (ext_stall_w)   ;  // AXI bekleme — PC dondur
    else if (pcSrcE)        pcF <= pcTargetE;
    else if (!stallF_eff)   pcF <= pcPlus4F;
  end

  // IMEM
  imem #(.IMemInitFile(IMemInitFile), .BASE(IMEM_BASE)) u_imem (
    .addr_i (pcF),
    .instr_o(instrF)
  );

  // IF/ID
  logic [XLEN-1:0] pcD, pcPlus4D, instrD;
  logic            validD;

  always_ff @(posedge clk_i) begin
    if (!rstn_i || (!ext_stall_w && flushD)) begin
      pcD      <= '0;
      pcPlus4D <= '0;
      instrD   <= 32'h0000_0013; // NOP
      validD   <= 1'b0;
    end
    else if (!stallD && !ext_stall_w) begin
      pcD      <= pcF;
      pcPlus4D <= pcPlus4F;
      instrD   <= instrF;
      validD   <= 1'b1;
    end
  end

  // ????????????????????????????????????????????????? ID ????????????????????????????????????????????????
  // alanlar
  wire [6:0] opcodeD   = instrD[6:0];
  wire [2:0] funct3D   = instrD[14:12];
  wire       funct7b5D = instrD[30];
  wire [4:0] rs1D_w    = instrD[19:15];
  wire [4:0] rs2D_w    = instrD[24:20];
  wire [4:0] rdD_w     = instrD[11:7];

  // kontrol
  logic       reg_writeD;
  logic [2:0] imm_srcD;
  logic       alu_src_a_pcD;
  logic       alu_src_b_immD;
  logic [1:0] result_srcD;
  logic       mem_readD, mem_writeD;
  logic [1:0] mem_sizeD;
  logic       mem_unsignedD;
  logic       is_branchD, is_jalD, is_jalrD, is_luiD;

  main_control u_ctrl (
    .opcode_i       (opcodeD),
    .funct3_i       (funct3D),
    .reg_write_o    (reg_writeD),
    .imm_src_o      (imm_srcD),
    .alu_src_a_pc_o (alu_src_a_pcD),
    .alu_src_b_imm_o(alu_src_b_immD),
    .result_src_o   (result_srcD),
    .mem_read_o     (mem_readD),
    .mem_write_o    (mem_writeD),
    .mem_size_o     (mem_sizeD),
    .mem_unsigned_o (mem_unsignedD),
    .branch_o       (is_branchD),
    .jal_o          (is_jalD),
    .jalr_o         (is_jalrD),
    .lui_o          (is_luiD)
  );

  // Register File
  logic [XLEN-1:0] rd1D, rd2D;
  logic            reg_writeW;   // WB'den
  logic [4:0]      rdW;
  logic [XLEN-1:0] result_W;

  register_file u_rf (
    .clk_i (clk_i),
    .rstn_i(rstn_i),
    .we_i  (reg_writeW),
    .rs1_i (rs1D_w),
    .rs2_i (rs2D_w),
    .rd_i  (rdW),
    .wd_i  (result_W),
    .rd1_o (rd1D),
    .rd2_o (rd2D)
  );

  // WB?ID tek-cycle bypass (yaz�lan de�er hen�z RF'ye d��meden ID kullan�rsa)
  wire [XLEN-1:0] rs1D_byp = (reg_writeW && (rdW != 5'd0) && (rdW == rs1D_w)) ? result_W : rd1D;
  wire [XLEN-1:0] rs2D_byp = (reg_writeW && (rdW != 5'd0) && (rdW == rs2D_w)) ? result_W : rd2D;

  // Immediate
  logic [XLEN-1:0] immD;
  imm_gen u_imm (
    .instr_i (instrD),
    .immsrc_i(imm_srcD),
    .imm_o   (immD)
  );

  // Hazard: load-use (E'de load, D'de kullan)
  logic mem_readE;
  logic [4:0] rdE;

  hazard_unit u_hazard (
    .mem_readE(mem_readE),
    .rdE      (rdE),
    .rs1D     (rs1D_w),
    .rs2D     (rs2D_w),
    .stallF   (stallF),
    .stallD   (stallD),
    .flushE   (flushE)
  );

  // ????????????????????????????????????????????????? ID/EX ?????????????????????????????????????????????
  logic [XLEN-1:0] pcE, pcPlus4E, instrE;
  logic [XLEN-1:0] rd1E, rd2E, immE;
  logic [4:0]      rs1E, rs2E;
  logic [2:0]      funct3E;  logic funct7b5E;
  logic [6:0]      opcodeE;
  logic            validE;

  // kontrol E
  logic       reg_writeE;
  logic       alu_src_a_pcE;
  logic       alu_src_b_immE;
  logic [1:0] result_srcE;
  logic       mem_writeE;
  logic [1:0] mem_sizeE;
  logic       mem_unsignedE;
  logic       is_branchE, is_jalE, is_jalrE, is_luiE;

  // pc redirect oldu�unda da E'yi bubble'la
  always_ff @(posedge clk_i) begin
    if (!rstn_i || (!ext_stall_w && (flushE || pcSrcE))) begin
      reg_writeE     <= 1'b0;
      alu_src_a_pcE  <= 1'b0;
      alu_src_b_immE <= 1'b0;
      result_srcE    <= 2'b00;
      mem_writeE     <= 1'b0;
      mem_readE      <= 1'b0;
      mem_sizeE      <= 2'b10;
      mem_unsignedE  <= 1'b0;
      is_branchE     <= 1'b0;
      is_jalE        <= 1'b0;
      is_jalrE       <= 1'b0;
      is_luiE        <= 1'b0;

      pcE            <= '0;
      pcPlus4E       <= '0;
      instrE         <= 32'h0000_0013;
      rd1E           <= '0;
      rd2E           <= '0;
      immE           <= '0;
      rs1E           <= '0;
      rs2E           <= '0;
      funct3E        <= '0;
      funct7b5E      <= '0;
      opcodeE        <= '0;
      rdE            <= '0;
      validE         <= 1'b0;
    end
    else if (!ext_stall_w) begin
      // veri
      pcE      <= pcD;
      pcPlus4E <= pcPlus4D;
      instrE   <= instrD;
      rd1E     <= rs1D_byp;
      rd2E     <= rs2D_byp;
      immE     <= immD;
      rs1E     <= rs1D_w;
      rs2E     <= rs2D_w;
      funct3E  <= funct3D;
      funct7b5E<= funct7b5D;
      opcodeE  <= opcodeD;
      rdE      <= rdD_w;
      validE   <= validD;

      // kontrol
      reg_writeE     <= reg_writeD;
      alu_src_a_pcE  <= alu_src_a_pcD;
      alu_src_b_immE <= alu_src_b_immD;
      result_srcE    <= result_srcD;
      mem_readE      <= mem_readD;
      mem_writeE     <= mem_writeD;
      mem_sizeE      <= mem_sizeD;
      mem_unsignedE  <= mem_unsignedD;
      is_branchE     <= is_branchD;
      is_jalE        <= is_jalD;
      is_jalrE       <= is_jalrD;
      is_luiE        <= is_luiD;
    end
  end

  // ????????????????????????????????????????????????? EX ????????????????????????????????????????????????
  // ALU kontrol
  logic [3:0] alu_ctrlE;
  alu_control u_aluctrl (
    .opcode_i  (opcodeE),
    .funct3_i  (funct3E),
    .funct7b5_i(funct7b5E),
    .alu_ctrl_o(alu_ctrlE)
  );

  // Forwarding se�icileri
  logic [1:0] forwardA, forwardB;
  logic       reg_writeM;
  logic [4:0] rdM;

  forwarding_unit u_fwd (
    .reg_writeM(reg_writeM),
    .rdM       (rdM),
    .reg_writeW(reg_writeW),
    .rdW       (rdW),
    .rs1E      (rs1E),
    .rs2E      (rs2E),
    .forwardA  (forwardA),
    .forwardB  (forwardB)
  );

  // EX/MEM'den ileri verilebilecek de�er: klasik be� a�amal�da ALU sonucu
  logic [XLEN-1:0] aluY_M;

  // A ve B kaynaklar� (tek noktadan se�im)
  function automatic logic [XLEN-1:0] sel_fwd(
    input logic [1:0] sel,
    input logic [XLEN-1:0] idex,
    input logic [XLEN-1:0] exmem,
    input logic [XLEN-1:0] memwb
  );
    unique case (sel)
      2'b10: sel_fwd = exmem; // EX/MEM
      2'b01: sel_fwd = memwb; // MEM/WB
      default: sel_fwd = idex; // ID/EX
    endcase
  endfunction

  wire [XLEN-1:0] aFwd = sel_fwd(forwardA, rd1E, aluY_M, result_W);
  wire [XLEN-1:0] bFwd = sel_fwd(forwardB, rd2E, aluY_M, result_W);

  // LUI & ALU operand se�imi
  wire [XLEN-1:0] srcA = is_luiE ? '0 : (alu_src_a_pcE ? pcE : aFwd);
  wire [XLEN-1:0] srcB = (alu_src_b_immE ? immE : bFwd);

  // ALU
  logic [XLEN-1:0] aluY_E;
  logic zeroE, lt_sE, lt_uE;

  alu u_alu (
    .a_i        (srcA),
    .b_i        (srcB),
    .alu_ctrl_i (alu_ctrlE),
    .y_o        (aluY_E),
    .zero_o     (zeroE),
    .lt_signed_o(lt_sE),
    .lt_unsigned_o(lt_uE)
  );

  // Branch compare (forwarded rs1/rs2 ile)
  logic takeBranchE;
  branch_compare u_brcmp (
    .rs1_i   (aFwd),     // e�itlik ve < kar��la�t�rmalar� forwarded de�erlerle
    .rs2_i   (bFwd),
    .funct3_i(funct3E),
    .take_o  (takeBranchE)
  );

  // Jump/branch hedefleri + redirect
  wire [XLEN-1:0] pcTargetBrE   = pcE + immE;
  wire [XLEN-1:0] pcTargetJalrE = (aFwd + immE) & 32'hFFFF_FFFE;

  assign pcSrcE    = (is_branchE & takeBranchE) | is_jalE | is_jalrE;
  assign pcTargetE = is_jalrE ? pcTargetJalrE : pcTargetBrE;

  // IF/ID flush
  assign flushD = pcSrcE;

  // ????????????????????????????????????????????????? EX/MEM ????????????????????????????????????????????
  logic [XLEN-1:0] pcM, instrM;
  logic [1:0]      result_srcM;
  logic            mem_readM, mem_writeM;
  logic [1:0]      mem_sizeM;
  logic            mem_unsignedM;
  logic            reg_writeM_r;
  logic            validM;

  logic [XLEN-1:0] storeDataM;

  always_ff @(posedge clk_i) begin
    if (!rstn_i) begin
      aluY_M        <= '0;
      storeDataM    <= '0;
      rdM           <= '0;
      pcM           <= '0;
      instrM        <= 32'h0000_0013;
      result_srcM   <= 2'b00;
      mem_readM     <= 1'b0;
      mem_writeM    <= 1'b0;
      mem_sizeM     <= 2'b10;
      mem_unsignedM <= 1'b0;
      reg_writeM_r  <= 1'b0;
      validM        <= 1'b0;
    end
    else if (!ext_stall_w) begin
      aluY_M        <= aluY_E;
      storeDataM    <= bFwd;         // store verisi
      rdM           <= rdE;
      pcM           <= pcE;
      instrM        <= instrE;
      result_srcM   <= result_srcE;
      mem_readM     <= mem_readE;
      mem_writeM    <= mem_writeE;
      mem_sizeM     <= mem_sizeE;
      mem_unsignedM <= mem_unsignedE;
      reg_writeM_r  <= reg_writeE;
      validM        <= validE;
    end
  end
  assign reg_writeM = reg_writeM_r;

  // ═══ Adres Yönlendirme: Dahili DMEM vs Harici AXI ═══
  // Dahili DMEM aralığı: [IMEM_BASE, IMEM_BASE + INT_DMEM_BYTES)
  assign is_int_dmem   = (aluY_M >= IMEM_BASE) && (aluY_M < INT_DMEM_END);
  assign is_ext_access = (mem_readM || mem_writeM) && !is_int_dmem;

  // ═══ Harici Bellek İstek Takibi ══════════════════
  // AXI Master IF'e tek cycle pulse gönder, sonra yanıt bekle.
  // ext_req_sent_q: istek gönderildi, AXI işliyor
  logic ext_req_sent_q;

  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i)
      ext_req_sent_q <= 1'b0;
    else if (!ext_stall_w)
      ext_req_sent_q <= 1'b0;   // Stall kalktı → temizle
    else if (is_ext_access && !ext_req_sent_q)
      ext_req_sent_q <= 1'b1;   // İstek gönderildi → işaretle
  end

  // Harici port sinyalleri — yalnızca ilk cycle'da aktif (pulse)
  assign ext_mem_read_o     = mem_readM  && !is_int_dmem && !ext_req_sent_q;
  assign ext_mem_write_o    = mem_writeM && !is_int_dmem && !ext_req_sent_q;
  assign ext_mem_size_o     = mem_sizeM;
  assign ext_mem_unsigned_o = mem_unsignedM;
  assign ext_mem_addr_o     = aluY_M;
  assign ext_mem_wdata_o    = storeDataM;

  // Stall: AXI erişimi devam ediyor ve yanıt henüz gelmedi
  assign ext_stall_w = is_ext_access && !ext_mem_ready_i;

  // ═══ DMEM — yalnızca dahili adres aralığı ═══════
  logic [XLEN-1:0] int_readDataM;
  dmem #(.DMemInitFile(DMemInitFile), .BASE(IMEM_BASE)) u_dmem (
    .clk_i         (clk_i),
    .rstn_i        (rstn_i),
    .mem_read_i    (mem_readM  && is_int_dmem),
    .mem_write_i   (mem_writeM && is_int_dmem),
    .mem_size_i    (mem_sizeM),
    .mem_unsigned_i(mem_unsignedM),
    .addr_i        (aluY_M),
    .wdata_i       (storeDataM),
    .dbg_addr_i    (addr_i),
    .rdata_o       (int_readDataM),
    .dbg_data_o    (data_o)
  );

  // ReadData MUX: dahili DMEM veya harici AXI
  wire [XLEN-1:0] readDataM = is_int_dmem ? int_readDataM : ext_mem_rdata_i;

  // store log verisini mem_size'e g�re k�rp
  logic [XLEN-1:0] storeLogM;
  always_comb begin
    unique case (mem_sizeM)
      2'b00:  storeLogM = {24'h0, storeDataM[7:0]};
      2'b01:  storeLogM = {16'h0, storeDataM[15:0]};
      default:storeLogM = storeDataM;
    endcase
  end

  // ????????????????????????????????????????????????? MEM/WB ????????????????????????????????????????????
  logic [XLEN-1:0] aluY_W, readDataW, pcW, instrW;
  logic [1:0]      result_srcW;
  logic            reg_writeW_r, validW;
  logic [XLEN-1:0] mem_addrW, mem_dataW;
  logic            mem_wrtW, mem_readW;

  always_ff @(posedge clk_i) begin
    if (!rstn_i) begin
      aluY_W       <= '0;
      readDataW    <= '0;
      rdW          <= '0;
      result_srcW  <= 2'b00;
      reg_writeW_r <= 1'b0;
      pcW          <= '0;
      instrW       <= 32'h0000_0013;
      validW       <= 1'b0;
      mem_addrW    <= '0;
      mem_dataW    <= '0;
      mem_wrtW     <= 1'b0;
      mem_readW    <= 1'b0;
    end
    else if (!ext_stall_w) begin
      aluY_W       <= aluY_M;
      readDataW    <= readDataM;
      rdW          <= rdM;
      result_srcW  <= result_srcM;
      reg_writeW_r <= reg_writeM_r;
      pcW          <= pcM;
      instrW       <= instrM;
      validW       <= validM;

      mem_addrW    <= (mem_readM || mem_writeM) ? aluY_M : '0;
      mem_dataW    <= mem_writeM ? storeLogM
                      : (mem_readM ? readDataM : '0);
      mem_wrtW     <= mem_writeM;
      mem_readW    <= mem_readM;
    end
  end
  assign reg_writeW = reg_writeW_r;

  // ????????????????????????????????????????????????? WB ????????????????????????????????????????????????
  always_comb begin
    unique case (result_srcW)
      2'b00: result_W = aluY_W;
      2'b01: result_W = readDataW;
      2'b10: result_W = pcW + 32'd4; // JAL/JALR link
      default: result_W = aluY_W;
    endcase
  end

  // retire/scoreboard ba�lant�lar�
  assign reg_addr_o = reg_writeW ? rdW      : 5'd0;
  assign reg_data_o = reg_writeW ? result_W : '0;

  assign mem_addr_o = mem_addrW;
  assign mem_data_o = mem_dataW;
  assign mem_wrt_o  = mem_wrtW;
  assign mem_read_o = mem_readW;

  assign pc_o       = pcW;
  assign instr_o    = instrW;
  assign update_o   = validW;

endmodule
