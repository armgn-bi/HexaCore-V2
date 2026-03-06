// filepath: tb/gen_golden.sv
// Golden log üreteci — Belirli bir test programını çalıştırır,
// WB aşamasından çıkan verileri golden log formatında dosyaya yazar.
//
// Kullanım:
//   xvlog --sv -f filelist_core.f tb/gen_golden.sv
//   xelab gen_golden -s gen_golden_snap
//   xsim gen_golden_snap --runall
//
// Parametreler xelab -generic_top ile geçilebilir, ya da kaynak kod
// düzenlenerek değiştirilebilir.
`timescale 1ns / 1ps

module gen_golden;
  import riscv_pkg::*;

  // ── Yapılandırma ──
  localparam string IMEM_FILE   = "imem_lsu.mem";
  localparam string DMEM_FILE   = "dmem.mem";
  localparam string OUTPUT_FILE = "lsu.golden_clean.log.txt";
  localparam int    MAX_CYCLES  = 1_000_000;

  // ── Clock & Reset ──
  logic clk;
  initial begin clk = 0; forever #1 clk = ~clk; end

  logic rstn;
  logic [31:0] addr = 32'h8000_0000;
  logic [31:0] data;

  // WB izleme sinyalleri
  logic        update;
  logic [31:0] pc, instr;
  logic [4:0]  reg_addr;
  logic [31:0] reg_data;
  logic [31:0] mem_addr, mem_data;
  logic        mem_wrt, mem_read;

  // DUT
  riscv_pipeline #(
    .IMemInitFile (IMEM_FILE),
    .DMemInitFile (DMEM_FILE)
  ) u_dut (
    .clk_i      (clk),
    .rstn_i     (rstn),
    .addr_i     (addr),
    .data_o     (data),
    .update_o   (update),
    .pc_o       (pc),
    .instr_o    (instr),
    .reg_addr_o (reg_addr),
    .reg_data_o (reg_data),
    .mem_addr_o (mem_addr),
    .mem_data_o (mem_data),
    .mem_wrt_o  (mem_wrt),
    .mem_read_o (mem_read)
  );

  // ── Golden log üretimi ──
  int fd;
  int line_cnt;
  int unsigned cycles;

  function automatic string make_log_line();
    string s;
    s = $sformatf("0x%08h (0x%08h)", pc, instr);

    if (reg_addr != 5'd0) begin
      if (reg_addr > 9)
        s = {s, $sformatf(" x%0d 0x%08h", reg_addr, reg_data)};
      else
        s = {s, $sformatf(" x%0d  0x%08h", reg_addr, reg_data)};
    end

    if (mem_wrt)
      s = {s, $sformatf(" mem 0x%08h 0x%08h", mem_addr, mem_data)};
    else if (mem_read)
      s = {s, $sformatf(" mem 0x%08h", mem_addr)};

    return s;
  endfunction

  initial begin
    rstn = 1'b0;
    repeat (2) @(posedge clk);
    rstn = 1'b1;

    fd = $fopen(OUTPUT_FILE, "w");
    if (fd == 0) $fatal(1, "Dosya acilamadi: %s", OUTPUT_FILE);

    line_cnt = 0;
    cycles   = 0;

    forever begin
      @(posedge clk); #0;
      cycles++;

      if (cycles > MAX_CYCLES) begin
        $display("[gen_golden] Watchdog: %0d cycle asild", MAX_CYCLES);
        break;
      end

      if (update) begin
        automatic string line = make_log_line();
        $fdisplay(fd, "%s", line);
        $display("[%0d] %s", line_cnt, line);
        line_cnt++;

        // NOP (0x00000000) = program sonu (convention)
        if (instr == 32'h0000_0000) begin
          $display("[gen_golden] NOP goruldu, program sonu.");
          break;
        end
      end
    end

    $fclose(fd);
    $display("[gen_golden] %s yazildi — %0d satir", OUTPUT_FILE, line_cnt);
    $finish;
  end

endmodule
