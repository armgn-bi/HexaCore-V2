// filepath: tb/periph_tb/tb_dqn_core_standalone.sv
// DQN Core dogrudan testbench — AXI katmani olmadan
// iverilog -g2012 ile derlenebilir
`timescale 1ns / 1ps

module tb_dqn_core_standalone;

  logic clk, rstn;
  initial begin clk = 0; forever #5 clk = ~clk; end

  // DQN Core portlari
  logic enable, start_pulse, soft_reset;
  logic signed [15:0] state_in [0:3];

  logic signed [15:0] fc1_w [0:3][0:15];
  logic signed [15:0] fc1_b [0:15];
  logic signed [15:0] fc2_w [0:15][0:3];
  logic signed [15:0] fc2_b [0:3];

  // Cikislar — iverilog unpacked array port uyumu icin
  // dogrudan DUT ici sinyallere erisecegiz
  logic signed [15:0] q_val [0:3];
  logic busy, done;
  logic [1:0] argmax;
  logic signed [15:0] q_max;
  logic [15:0] cycle_cnt;

  int pass_cnt = 0;
  int fail_cnt = 0;
  int test_num = 0;

  // DUT
  dqn_core u_dqn (
    .clk_i        (clk),
    .rstn_i       (rstn),
    .enable_i     (enable),
    .start_i      (start_pulse),
    .soft_reset_i (soft_reset),
    .state_in_i   (state_in),
    .fc1_w_i      (fc1_w),
    .fc1_b_i      (fc1_b),
    .fc2_w_i      (fc2_w),
    .fc2_b_i      (fc2_b),
    .q_val_o      (q_val),
    .busy_o       (busy),
    .done_o       (done),
    .argmax_o     (argmax),
    .q_max_o      (q_max),
    .cycle_cnt_o  (cycle_cnt)
  );

  // Iverilog hierarchical access ile DUT ici q_val_r'den oku
  // Bu, unpacked array port sorununu bypass eder
  wire signed [15:0] dut_q0 = u_dqn.q_val_r[0];
  wire signed [15:0] dut_q1 = u_dqn.q_val_r[1];
  wire signed [15:0] dut_q2 = u_dqn.q_val_r[2];
  wire signed [15:0] dut_q3 = u_dqn.q_val_r[3];

  task automatic check16(
    input string test_name,
    input logic signed [15:0] got,
    input logic signed [15:0] expected
  );
    test_num = test_num + 1;
    if (got === expected) begin
      pass_cnt = pass_cnt + 1;
      $display("[%0t] PASS #%0d %s — got=0x%04h", $time, test_num, test_name, got);
    end else begin
      fail_cnt = fail_cnt + 1;
      $display("[%0t] FAIL #%0d %s — got=0x%04h expected=0x%04h",
               $time, test_num, test_name, got, expected);
    end
  endtask

  task automatic check_val(
    input string test_name,
    input integer got,
    input integer expected
  );
    test_num = test_num + 1;
    if (got === expected) begin
      pass_cnt = pass_cnt + 1;
      $display("[%0t] PASS #%0d %s — got=%0d", $time, test_num, test_name, got);
    end else begin
      fail_cnt = fail_cnt + 1;
      $display("[%0t] FAIL #%0d %s — got=%0d expected=%0d",
               $time, test_num, test_name, got, expected);
    end
  endtask

  integer i, j;

  initial begin
    $display("════════════════════════════════════════════════");
    $display("  DQN Core Standalone Test");
    $display("════════════════════════════════════════════════");

    enable = 0; start_pulse = 0; soft_reset = 0;

    for (i = 0; i < 4; i = i + 1)
      for (j = 0; j < 16; j = j + 1)
        fc1_w[i][j] = 16'sh0000;
    for (i = 0; i < 16; i = i + 1) fc1_b[i] = 16'sh0000;
    for (i = 0; i < 16; i = i + 1)
      for (j = 0; j < 4; j = j + 1)
        fc2_w[i][j] = 16'sh0000;
    for (i = 0; i < 4; i = i + 1) fc2_b[i] = 16'sh0000;
    for (i = 0; i < 4; i = i + 1) state_in[i] = 16'sh0000;

    // Identity-like weights: FC1 diag 0.5, FC2 diag 0.5
    fc1_w[0][0] = 16'sh4000;
    fc1_w[1][1] = 16'sh4000;
    fc1_w[2][2] = 16'sh4000;
    fc1_w[3][3] = 16'sh4000;

    fc2_w[0][0] = 16'sh4000;
    fc2_w[1][1] = 16'sh4000;
    fc2_w[2][2] = 16'sh4000;
    fc2_w[3][3] = 16'sh4000;

    rstn = 0;
    repeat(10) @(posedge clk);
    rstn = 1;
    enable = 1;
    repeat(5) @(posedge clk);

    // ── TEST 1: Positif girisler ──
    $display("\n── TEST 1: Inference (Positif Girisler) ──");
    state_in[0] = 16'sh4000;  // 0.5
    state_in[1] = 16'sh2000;  // 0.25
    state_in[2] = 16'sh6000;  // 0.75
    state_in[3] = 16'sh1000;  // 0.125

    @(negedge clk);
    start_pulse = 1;
    @(negedge clk);
    start_pulse = 0;

    wait(done == 1);
    @(posedge clk);

    // Beklenen: q_val[i] = state[i] * 0.5 * 0.5 = state[i] * 0.25
    check16("q_val[0]=0.125",  dut_q0, 16'sh1000);
    check16("q_val[1]=0.0625", dut_q1, 16'sh0800);
    check16("q_val[2]=0.1875", dut_q2, 16'sh1800);
    check16("q_val[3]=0.03125",dut_q3, 16'sh0400);
    check_val("argmax=2",      argmax, 2);
    check16("q_max=0x1800",    q_max,  16'sh1800);
    check_val("cycle_cnt > 0", (cycle_cnt > 0) ? 1 : 0, 1);
    $display("  Inference cycles = %0d", cycle_cnt);

    // ── TEST 2: Negatif giris (LeakyReLU) ──
    $display("\n── TEST 2: LeakyReLU (Negatif Giris) ──");
    state_in[3] = 16'shC000;  // -0.5

    @(negedge clk);
    start_pulse = 1;
    @(negedge clk);
    start_pulse = 0;
    wait(done == 1);
    @(posedge clk);

    check_val("q_val[3] negatif", dut_q3[15], 1);
    check16("q_val[0] ayni", dut_q0, 16'sh1000);
    check16("q_val[2] ayni", dut_q2, 16'sh1800);
    check_val("argmax hala 2", argmax, 2);

    // ── TEST 3: Esit girisler ──
    $display("\n── TEST 3: Esit Girisler ──");
    state_in[0] = 16'sh4000;
    state_in[1] = 16'sh4000;
    state_in[2] = 16'sh4000;
    state_in[3] = 16'sh4000;

    @(negedge clk);
    start_pulse = 1;
    @(negedge clk);
    start_pulse = 0;
    wait(done == 1);
    @(posedge clk);

    check16("esit q_val[0]", dut_q0, 16'sh1000);
    check16("esit q_val[1]", dut_q1, 16'sh1000);
    check16("esit q_val[2]", dut_q2, 16'sh1000);
    check16("esit q_val[3]", dut_q3, 16'sh1000);

    // ── TEST 4: Soft Reset ──
    $display("\n── TEST 4: Soft Reset ──");
    state_in[0] = 16'sh2000;
    @(negedge clk);
    start_pulse = 1;
    @(negedge clk);
    start_pulse = 0;
    repeat(5) @(posedge clk);
    @(negedge clk);
    soft_reset = 1;
    @(negedge clk);
    soft_reset = 0;
    repeat(5) @(posedge clk);
    check_val("busy after reset", busy, 0);
    check_val("done after reset", done, 0);

    // ── TEST 5: Bias testi ──
    $display("\n── TEST 5: Bias Testi ──");
    fc2_b[0] = 16'sh1000;  // bias = 0.125

    state_in[0] = 16'sh4000;
    state_in[1] = 16'sh2000;
    state_in[2] = 16'sh6000;
    state_in[3] = 16'sh1000;

    @(negedge clk);
    start_pulse = 1;
    @(negedge clk);
    start_pulse = 0;
    wait(done == 1);
    @(posedge clk);

    // q_val[0] = 0.125 + bias(0.125) = 0.25 = 0x2000
    check16("q_val[0] biasli", dut_q0, 16'sh2000);
    check16("q_val[1] biassiz", dut_q1, 16'sh0800);
    check_val("argmax=0 (biasli)", argmax, 0);

    fc2_b[0] = 16'sh0000;

    // ── TEST 6: Sifir giris ──
    $display("\n── TEST 6: Sifir Giris ──");
    state_in[0] = 16'sh0000;
    state_in[1] = 16'sh0000;
    state_in[2] = 16'sh0000;
    state_in[3] = 16'sh0000;

    @(negedge clk);
    start_pulse = 1;
    @(negedge clk);
    start_pulse = 0;
    wait(done == 1);
    @(posedge clk);

    check16("sifir q_val[0]", dut_q0, 16'sh0000);
    check16("sifir q_val[1]", dut_q1, 16'sh0000);
    check16("sifir q_val[2]", dut_q2, 16'sh0000);
    check16("sifir q_val[3]", dut_q3, 16'sh0000);

    // ── SONUC ──
    $display("\n════════════════════════════════════════════════");
    $display("  DQN Core Test: %0d/%0d PASS", pass_cnt, test_num);
    if (fail_cnt > 0)
      $display("  UYARI: %0d test BASARISIZ!", fail_cnt);
    else
      $display("  Tum testler BASARILI");
    $display("════════════════════════════════════════════════");
    $finish;
  end

  initial begin
    #200_000;
    $display("[TIMEOUT] Simulasyon zaman asimi!");
    $finish;
  end

endmodule
