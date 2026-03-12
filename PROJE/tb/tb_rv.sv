// tb_rv_all.sv
// 4 testi tek ko�uda s�rayla �al��t�ran testbench.
// NOT: SystemVerilog ile derleyin (-sv / -sverilog)
`timescale 1ns / 1ps

module tb_rv_all;
  import riscv_pkg::*;

  // ?? Kullanaca��n�z dosya adlar� ????????????????????????????????????????????
  localparam string BASE_IMEM   = "imem_base.mem";
  localparam string BUBBLE_IMEM = "imem_bubble.mem";
  localparam string BOOK_IMEM   = "imem_book.mem";
  localparam string LSU_IMEM    = "imem_lsu.mem";

  localparam string DMEM_FILE   = "dmem.mem";

  // Golden log dosyalar� (clean)
  localparam string BASE_GOLDEN   = "base_test.golden_clean.log.txt";
  localparam string BUBBLE_GOLDEN = "bubble_sort.golden_clean.log.txt";
  localparam string BOOK_GOLDEN   = "book_test.golden_clean.log.txt";
  localparam string LSU_GOLDEN    = "lsu.golden_clean.log.txt";

  // ?? Ortak clock ????????????????????????????????????????????????????????????
  logic clk; initial begin clk = 0; forever #1 clk = ~clk; end

  // ?? Test 0: BASE ???????????????????????????????????????????????????????????
  logic        rstn0, start0, done0;
  logic [31:0] addr0 = 32'h8000_0000;
  logic [31:0] data0;
  logic        update0;  logic [31:0] pc0, instr0;
  logic [4:0]  rdaddr0;  logic [31:0] rddata0;
  logic [31:0] maddr0, mdata0; logic mwrt0, mrd0;

  riscv_pipeline #(.IMemInitFile(BASE_IMEM), .DMemInitFile(DMEM_FILE)) u0 (
    .clk_i(clk), .rstn_i(rstn0),
    .addr_i(addr0), .data_o(data0),
    .update_o(update0), .pc_o(pc0), .instr_o(instr0),
    .reg_addr_o(rdaddr0), .reg_data_o(rddata0),
    .mem_addr_o(maddr0), .mem_data_o(mdata0),
    .mem_wrt_o(mwrt0), .mem_read_o(mrd0)
  );

  rv_scoreboard #(.TEST_NAME("BASE"), .GOLDEN_FILE(BASE_GOLDEN)) sb0 (
    .clk(clk), .rstn(rstn0), .start_i(start0), .done_o(done0),
    .update(update0), .pc(pc0), .instr(instr0),
    .reg_addr(rdaddr0), .reg_data(rddata0),
    .mem_addr(maddr0), .mem_data(mdata0), .mem_wrt(mwrt0), .mem_read(mrd0)
  );

  // ?? Test 1: BUBBLE_SORT ???????????????????????????????????????????????????
  logic        rstn1, start1, done1;
  logic [31:0] addr1 = 32'h8000_0000;
  logic [31:0] data1;
  logic        update1;  logic [31:0] pc1, instr1;
  logic [4:0]  rdaddr1;  logic [31:0] rddata1;
  logic [31:0] maddr1, mdata1; logic mwrt1, mrd1;

  riscv_pipeline #(.IMemInitFile(BUBBLE_IMEM), .DMemInitFile(DMEM_FILE)) u1 (
    .clk_i(clk), .rstn_i(rstn1),
    .addr_i(addr1), .data_o(data1),
    .update_o(update1), .pc_o(pc1), .instr_o(instr1),
    .reg_addr_o(rdaddr1), .reg_data_o(rddata1),
    .mem_addr_o(maddr1), .mem_data_o(mdata1),
    .mem_wrt_o(mwrt1), .mem_read_o(mrd1)
  );

  rv_scoreboard #(.TEST_NAME("BUBBLE"), .GOLDEN_FILE(BUBBLE_GOLDEN)) sb1 (
    .clk(clk), .rstn(rstn1), .start_i(start1), .done_o(done1),
    .update(update1), .pc(pc1), .instr(instr1),
    .reg_addr(rdaddr1), .reg_data(rddata1),
    .mem_addr(maddr1), .mem_data(mdata1), .mem_wrt(mwrt1), .mem_read(mrd1)
  );

  // ?? Test 2: BOOK_TEST ?????????????????????????????????????????????????????
  logic        rstn2, start2, done2;
  logic [31:0] addr2 = 32'h8000_0000;
  logic [31:0] data2;
  logic        update2;  logic [31:0] pc2, instr2;
  logic [4:0]  rdaddr2;  logic [31:0] rddata2;
  logic [31:0] maddr2, mdata2; logic mwrt2, mrd2;

  riscv_pipeline #(.IMemInitFile(BOOK_IMEM), .DMemInitFile(DMEM_FILE)) u2 (
    .clk_i(clk), .rstn_i(rstn2),
    .addr_i(addr2), .data_o(data2),
    .update_o(update2), .pc_o(pc2), .instr_o(instr2),
    .reg_addr_o(rdaddr2), .reg_data_o(rddata2),
    .mem_addr_o(maddr2), .mem_data_o(mdata2),
    .mem_wrt_o(mwrt2), .mem_read_o(mrd2)
  );

  rv_scoreboard #(.TEST_NAME("BOOK"), .GOLDEN_FILE(BOOK_GOLDEN)) sb2 (
    .clk(clk), .rstn(rstn2), .start_i(start2), .done_o(done2),
    .update(update2), .pc(pc2), .instr(instr2),
    .reg_addr(rdaddr2), .reg_data(rddata2),
    .mem_addr(maddr2), .mem_data(mdata2), .mem_wrt(mwrt2), .mem_read(mrd2)
  );

  // ?? Test 3: LSU ???????????????????????????????????????????????????????????
  logic        rstn3, start3, done3;
  logic [31:0] addr3 = 32'h8000_0000;
  logic [31:0] data3;
  logic        update3;  logic [31:0] pc3, instr3;
  logic [4:0]  rdaddr3;  logic [31:0] rddata3;
  logic [31:0] maddr3, mdata3; logic mwrt3, mrd3;

  riscv_pipeline #(.IMemInitFile(LSU_IMEM), .DMemInitFile(DMEM_FILE)) u3 (
    .clk_i(clk), .rstn_i(rstn3),
    .addr_i(addr3), .data_o(data3),
    .update_o(update3), .pc_o(pc3), .instr_o(instr3),
    .reg_addr_o(rdaddr3), .reg_data_o(rddata3),
    .mem_addr_o(maddr3), .mem_data_o(mdata3),
    .mem_wrt_o(mwrt3), .mem_read_o(mrd3)
  );

  rv_scoreboard #(.TEST_NAME("LSU"), .GOLDEN_FILE(LSU_GOLDEN)) sb3 (
    .clk(clk), .rstn(rstn3), .start_i(start3), .done_o(done3),
    .update(update3), .pc(pc3), .instr(instr3),
    .reg_addr(rdaddr3), .reg_data(rddata3),
    .mem_addr(maddr3), .mem_data(mdata3), .mem_wrt(mwrt3), .mem_read(mrd3)
  );

  // ?? S�ral� ko�u kontrol� ??????????????????????????????????????????????????
  initial begin
    rstn0=0; rstn1=0; rstn2=0; rstn3=0;
    start0=0; start1=0; start2=0; start3=0;

    // BASE
    repeat (2) @(posedge clk);
    rstn0=1; start0=1;
    wait (done0);
    rstn0=0; start0=0;

    // BUBBLE
    repeat (2) @(posedge clk);
    rstn1=1; start1=1;
    wait (done1);
    rstn1=0; start1=0;

    // BOOK
    repeat (2) @(posedge clk);
    rstn2=1; start2=1;
    wait (done2);
    rstn2=0; start2=0;

    // LSU
    repeat (2) @(posedge clk);
    rstn3=1; start3=1;
    wait (done3);
    rstn3=0; start3=0;

    $display("\n[TB] TUM TESTLER TAMAMLANDI.\n");
    $finish;
  end

  // opsiyonel VCD
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_rv_all);
  end
endmodule


// ?????????????????????????????????????????????????????????????????????????????
// Genel ama�l� scoreboard (EXP vs GOT + PASS/FAIL)
// ?????????????????????????????????????????????????????????????????????????????
module rv_scoreboard #(
  parameter string TEST_NAME   = "TEST",
  parameter string GOLDEN_FILE = "golden.log",
  parameter int    MAX_PRINT   = 2000,
  parameter int unsigned MAX_CYCLES = 5_000_000
)(
  input  logic clk,
  input  logic rstn,
  input  logic start_i,
  output logic done_o,

  // retire port (WB'den)
  input  logic        update,
  input  logic [31:0] pc,
  input  logic [31:0] instr,
  input  logic [4:0]  reg_addr,
  input  logic [31:0] reg_data,
  input  logic [31:0] mem_addr,
  input  logic [31:0] mem_data,
  input  logic        mem_wrt,
  input  logic        mem_read
);
  // golden sat�rlar�n� y�kle
  string golden[$];

  function automatic string rstrip(input string s);
    while (s.len() && ((s[s.len()-1] == "\n") || (s[s.len()-1] == "\r")))
      s = s.substr(0, s.len()-2);
    return s;
  endfunction

  task automatic load_golden_from_file(input string fname);
    int fd; string line;
    fd = $fopen(fname, "r");
    if (fd == 0) $fatal(1, "[%s] Golden a�ilamadi: %s", TEST_NAME, fname);
    while ($fgets(line, fd)) golden.push_back(rstrip(line));
    $fclose(fd);
    $display("[%s] Golden okundu: %0d satir", TEST_NAME, golden.size());
  endtask

  // >>> Burada d�zeltme var: load sat�rlar�nda veri yok, sadece adres yaz�l�yor.
  function automatic string make_log_line();
    string s;
    s = $sformatf("0x%08h (0x%08h)", pc, instr);

    if (reg_addr != 5'd0) begin
      if (reg_addr > 9)
        s = {s, $sformatf(" x%0d 0x%08h", reg_addr, reg_data)};
      else
        s = {s, $sformatf(" x%0d  0x%08h", reg_addr, reg_data)};
    end

    // store -> addr + data, load -> sadece addr
    if (mem_wrt)
      s = {s, $sformatf(" mem 0x%08h 0x%08h", mem_addr, mem_data)};
    else if (mem_read)
      s = {s, $sformatf(" mem 0x%08h", mem_addr)};

    return s;
  endfunction

  int idx, pass_cnt, fail_cnt;
  int unsigned cycles;

  initial begin
    done_o = 1'b0;
    idx = 0; pass_cnt = 0; fail_cnt = 0; cycles = 0;
    load_golden_from_file(GOLDEN_FILE);

    // start_i gelene kadar bekle
    @(posedge start_i);
    @(posedge clk); #0;

    forever begin
      @(posedge clk); #0;

      cycles++;
      if (cycles > MAX_CYCLES)
        $fatal(1, "[%s] Watchdog a�ildi (%0d)", TEST_NAME, MAX_CYCLES);

      if (update) begin
        automatic string got = make_log_line();
        automatic string exp = (idx < golden.size()) ? golden[idx] : "";

        if (got == exp) begin
          pass_cnt++;
          if (idx < MAX_PRINT) $display("%s PASS [%0d] %s", TEST_NAME, idx, got);
        end else begin
          fail_cnt++;
          if (fail_cnt <= MAX_PRINT)
            $display("%s FAIL [%0d]\n EXP: %s\n GOT: %s\n", TEST_NAME, idx, exp, got);
        end

        idx++;
        if (idx >= golden.size()) begin
          $display("\n[%s] BITTI: toplam=%0d PASS=%0d FAIL=%0d\n",
                   TEST_NAME, idx, pass_cnt, fail_cnt);
          if (fail_cnt != 0)
            $fatal(1, "[%s] Golden uyumsuzlu�u var. FAIL=%0d", TEST_NAME, fail_cnt);
          done_o = 1'b1;
          disable fork;
          break;
        end
      end
    end
  end
endmodule
