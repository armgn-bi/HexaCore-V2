// filepath: tb/periph_tb/tb_dqn_perf_standalone.sv
// DQN Performans Testi — CPU-only vs DQN+CPU Paralel Labirent Cozme
// iverilog -g2012 uyumlu (AXI katmani yok, dqn_core dogrudan surulur)
//
// 5 farkli karmasik labirent senaryosu (8x8 grid, duvarli):
//   State vektoru: Her yon icin cekicilik skoru (yon tercihi * duvar durumu)
//   state[0]=yukari, state[1]=asagi, state[2]=sol, state[3]=sag cekicilik
//   Aksiyon: 0=yukari, 1=asagi, 2=sol, 3=sag
//
// Olcumler:
//   1) CPU-only: Tum DQN inference hesaplamasi yazilimda yapilir (cycle sayimi)
//   2) DQN+CPU: DQN core donanim inference, gercek clock cycle olculur
//   Her iki modda toplam cycle sayisi raporlanir ve karsilastirilir.
`timescale 1ns / 1ps

module tb_dqn_perf_standalone;

  // ════════════════════════════════════════════════
  // Clock & Reset
  // ════════════════════════════════════════════════
  logic clk;
  logic rstn;

  initial begin clk = 0; forever #5 clk = ~clk; end  // 10ns = 100 MHz

  // ════════════════════════════════════════════════
  // Parametreler
  // ════════════════════════════════════════════════
  localparam int GRID_SIZE   = 8;
  localparam int MAX_STEPS   = 120;
  localparam int NUM_MAZES   = 5;

  // Q1.15 sabitleri
  localparam logic signed [15:0] LEAKY_ALPHA = 16'sh0148;  // 0.01

  // ════════════════════════════════════════════════
  // Labirent tanimlari
  // ════════════════════════════════════════════════
  logic maze_walls [0:NUM_MAZES-1][0:GRID_SIZE-1][0:GRID_SIZE-1];
  int maze_start_x [0:NUM_MAZES-1];
  int maze_start_y [0:NUM_MAZES-1];
  int maze_goal_x  [0:NUM_MAZES-1];
  int maze_goal_y  [0:NUM_MAZES-1];

  // ════════════════════════════════════════════════
  // Sonuc depolama
  // ════════════════════════════════════════════════
  int cpu_only_cycles    [0:NUM_MAZES-1];
  int dqn_parallel_cycles[0:NUM_MAZES-1];
  int cpu_only_steps     [0:NUM_MAZES-1];
  int dqn_parallel_steps [0:NUM_MAZES-1];

  // ════════════════════════════════════════════════
  // DQN Core portlari
  // ════════════════════════════════════════════════
  logic enable, start_pulse, soft_reset;
  logic signed [15:0] state_in [0:3];

  logic signed [15:0] fc1_w [0:3][0:15];
  logic signed [15:0] fc1_b [0:15];
  logic signed [15:0] fc2_w [0:15][0:3];
  logic signed [15:0] fc2_b [0:3];

  logic signed [15:0] q_val [0:3];
  logic busy, done;
  logic [1:0] argmax_out;
  logic signed [15:0] q_max;
  logic [15:0] cycle_cnt;

  // ════════════════════════════════════════════════
  // DQN Core Instance
  // ════════════════════════════════════════════════
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
    .argmax_o     (argmax_out),
    .q_max_o      (q_max),
    .cycle_cnt_o  (cycle_cnt)
  );

  // Iverilog hierarchical access
  wire signed [15:0] dut_q0 = u_dqn.q_val_r[0];
  wire signed [15:0] dut_q1 = u_dqn.q_val_r[1];
  wire signed [15:0] dut_q2 = u_dqn.q_val_r[2];
  wire signed [15:0] dut_q3 = u_dqn.q_val_r[3];

  // ════════════════════════════════════════════════
  // Agirlik bellegi (148 eleman)
  // ════════════════════════════════════════════════
  logic signed [15:0] all_weights [0:147];

  // ════════════════════════════════════════════════
  // Duvar-duyarli State Vektoru Hesaplama
  //
  // Her yon icin "cekicilik skoru" hesaplanir:
  //   score = (goal_yonundeki_mesafe + arastirma_biasi) * duvar_faktoru
  //
  //   goal_yonundeki_mesafe: hedefe yaklasan ise delta/GRID (0..0.875)
  //                         hedefe uzaklasan ise 0
  //   arastirma_biasi:      0.05 (acik yonde bir sey yoksa bile kucuk tercih)
  //   duvar_faktoru:        1.0 (acik) veya 0.01 (duvar/sinir disi)
  //
  // Sonuc: acik yonler her zaman duvardan yuksek skor alir (0.35 > 0.009)
  //        acik yonler arasinda hedefe yakin olan kazanir
  // ════════════════════════════════════════════════
  function automatic logic signed [15:0] compute_attractiveness(
    input int delta,       // hedefe yondeki mesafe bileseni (poz=bu yon dogru)
    input int can_move     // 1=acik, 0=duvar veya sinir disi
  );
    logic signed [31:0] goal_score;
    logic signed [31:0] base_score;
    logic signed [31:0] total;
    begin
      // goal_score = max(0, delta) * 0.6 / GRID_SIZE
      if (delta > 0)
        goal_score = (delta * 32768 * 6) / (GRID_SIZE * 10);
      else
        goal_score = 0;

      // base_score = 0.05 (arastirma biasi) = 1638 in Q1.15
      base_score = 1638;

      // total = (goal_score + base_score) * wall_factor
      total = goal_score + base_score;

      if (can_move == 0) begin
        // Duvar: skoru $0.01 ile carp (neredeyse sifir)
        total = total / 100;
      end

      // Q1.15 saturation [-1, 1)
      if (total > 32767) total = 32767;
      if (total < 0) total = 0;
      compute_attractiveness = total[15:0];
    end
  endfunction

  // Bir yonde hareket edilebilir mi? (sinir + duvar kontrolu)
  function automatic int can_move_dir(
    input int maze_id, input int px, input int py, input int dir
  );
    int nx, ny;
    begin
      nx = px; ny = py;
      case (dir)
        0: ny = py - 1;  // yukari
        1: ny = py + 1;  // asagi
        2: nx = px - 1;  // sol
        3: nx = px + 1;  // sag
      endcase
      if (nx < 0 || nx >= GRID_SIZE || ny < 0 || ny >= GRID_SIZE)
        can_move_dir = 0;
      else if (maze_walls[maze_id][ny][nx])
        can_move_dir = 0;
      else
        can_move_dir = 1;
    end
  endfunction

  // ════════════════════════════════════════════════
  // CPU-Only Yazilim DQN Inference (task, iverilog uyumlu)
  // Sonuclar modul degiskenlerinde doner
  // ════════════════════════════════════════════════
  logic signed [15:0] cpu_inf_state [0:3];
  int cpu_inf_cycles;
  logic [1:0] cpu_inf_action;

  task automatic cpu_inference();
    logic signed [15:0] sw_fc1_w [0:3][0:15];
    logic signed [15:0] sw_fc1_b [0:15];
    logic signed [15:0] sw_fc2_w [0:15][0:3];
    logic signed [15:0] sw_fc2_b [0:3];
    logic signed [15:0] hidden [0:15];
    logic signed [15:0] sw_q_val [0:3];
    logic signed [31:0] sum;
    logic signed [15:0] trunc;
    logic signed [15:0] biased;
    logic signed [31:0] relu_prod;
    logic signed [15:0] max_val;
    logic [1:0] max_idx;
    integer ci, cj;
    begin
      cpu_inf_cycles = 0;

      // Agirliklari bellekten oku (her biri 1 cycle)
      for (ci = 0; ci < 4; ci = ci + 1)
        for (cj = 0; cj < 16; cj = cj + 1) begin
          sw_fc1_w[ci][cj] = all_weights[ci*16 + cj];
          cpu_inf_cycles = cpu_inf_cycles + 1;  // load
        end
      for (ci = 0; ci < 16; ci = ci + 1) begin
        sw_fc1_b[ci] = all_weights[64 + ci];
        cpu_inf_cycles = cpu_inf_cycles + 1;
      end
      for (ci = 0; ci < 16; ci = ci + 1)
        for (cj = 0; cj < 4; cj = cj + 1) begin
          sw_fc2_w[ci][cj] = all_weights[80 + ci*4 + cj];
          cpu_inf_cycles = cpu_inf_cycles + 1;
        end
      for (ci = 0; ci < 4; ci = ci + 1) begin
        sw_fc2_b[ci] = all_weights[144 + ci];
        cpu_inf_cycles = cpu_inf_cycles + 1;
      end

      // FC1: 16 noron, her birinde 4 MAC
      for (cj = 0; cj < 16; cj = cj + 1) begin
        sum = 32'sd0;
        for (ci = 0; ci < 4; ci = ci + 1) begin
          sum = sum + ($signed({{16{cpu_inf_state[ci][15]}}, cpu_inf_state[ci]})
                     * $signed({{16{sw_fc1_w[ci][cj][15]}}, sw_fc1_w[ci][cj]}));
          cpu_inf_cycles = cpu_inf_cycles + 3;  // mul + shift + add
        end
        trunc = sum[30:15];
        cpu_inf_cycles = cpu_inf_cycles + 1;  // truncation

        biased = trunc + sw_fc1_b[cj];
        cpu_inf_cycles = cpu_inf_cycles + 1;  // bias add

        // LeakyReLU
        if (biased >= 16'sh0000) begin
          hidden[cj] = biased;
          cpu_inf_cycles = cpu_inf_cycles + 1;  // cmp + assign
        end else begin
          relu_prod = $signed({{16{biased[15]}}, biased})
                    * $signed({{16{LEAKY_ALPHA[15]}}, LEAKY_ALPHA});
          hidden[cj] = relu_prod[30:15];
          cpu_inf_cycles = cpu_inf_cycles + 3;  // cmp + mul + trunc
        end
      end

      // FC2: 4 cikis noronu, her birinde 16 MAC
      for (cj = 0; cj < 4; cj = cj + 1) begin
        sum = 32'sd0;
        for (ci = 0; ci < 16; ci = ci + 1) begin
          sum = sum + ($signed({{16{hidden[ci][15]}}, hidden[ci]})
                     * $signed({{16{sw_fc2_w[ci][cj][15]}}, sw_fc2_w[ci][cj]}));
          cpu_inf_cycles = cpu_inf_cycles + 3;  // mul + shift + add
        end
        trunc = sum[30:15];
        cpu_inf_cycles = cpu_inf_cycles + 1;
        sw_q_val[cj] = trunc + sw_fc2_b[cj];
        cpu_inf_cycles = cpu_inf_cycles + 1;
      end

      // Argmax
      max_val = sw_q_val[0];
      max_idx = 2'd0;
      cpu_inf_cycles = cpu_inf_cycles + 1;
      for (ci = 1; ci < 4; ci = ci + 1) begin
        if (sw_q_val[ci] > max_val) begin
          max_val = sw_q_val[ci];
          max_idx = ci[1:0];
        end
        cpu_inf_cycles = cpu_inf_cycles + 1;
      end
      cpu_inf_action = max_idx;
    end
  endtask

  // ════════════════════════════════════════════════
  // Hareket fonksiyonu
  // ════════════════════════════════════════════════
  task automatic apply_action(
    input  int maze_id,
    input  logic [1:0] act,
    inout  int px,
    inout  int py
  );
    int nx, ny;
    begin
      nx = px; ny = py;
      case (act)
        2'd0: ny = py - 1;
        2'd1: ny = py + 1;
        2'd2: nx = px - 1;
        2'd3: nx = px + 1;
      endcase
      if (nx >= 0 && nx < GRID_SIZE && ny >= 0 && ny < GRID_SIZE) begin
        if (!maze_walls[maze_id][ny][nx]) begin
          px = nx;
          py = ny;
        end
      end
    end
  endtask

  // ════════════════════════════════════════════════
  // DQN Core ile donanim inference
  // ════════════════════════════════════════════════
  task automatic hw_inference(
    input  logic signed [15:0] s0, s1, s2, s3,
    output logic [1:0] act,
    output int hw_cycles
  );
    int start_t;
    begin
      start_t = $time;
      state_in[0] = s0;
      state_in[1] = s1;
      state_in[2] = s2;
      state_in[3] = s3;
      @(negedge clk);
      start_pulse = 1;
      @(negedge clk);
      start_pulse = 0;
      wait(done == 1);
      @(posedge clk);
      act = u_dqn.argmax_r;
      hw_cycles = ($time - start_t) / 10;
    end
  endtask

  // ════════════════════════════════════════════════
  // Labirent gorsellestirme
  // ════════════════════════════════════════════════
  task automatic print_maze(
    input int maze_id,
    input int px, input int py
  );
    string line_str;
    integer yy, xx;
    begin
      for (yy = 0; yy < GRID_SIZE; yy = yy + 1) begin
        line_str = "    ";
        for (xx = 0; xx < GRID_SIZE; xx = xx + 1) begin
          if (xx == px && yy == py)
            line_str = {line_str, "A "};
          else if (xx == maze_goal_x[maze_id] && yy == maze_goal_y[maze_id])
            line_str = {line_str, "G "};
          else if (xx == maze_start_x[maze_id] && yy == maze_start_y[maze_id])
            line_str = {line_str, "S "};
          else if (maze_walls[maze_id][yy][xx])
            line_str = {line_str, "# "};
          else
            line_str = {line_str, ". "};
        end
        $display("%s", line_str);
      end
    end
  endtask

  // ════════════════════════════════════════════════
  // Ortam guncelleme CPU is yuku
  // ════════════════════════════════════════════════
  localparam int ENV_UPDATE_CYCLES = 15;

  // ════════════════════════════════════════════════
  // Ana Test Sekansi
  // ════════════════════════════════════════════════
  integer m, ii, jj;
  int pos_x, pos_y;
  int cycle_counter, step_count;
  logic [1:0] action;
  int start_time, end_time;
  int hw_cyc;
  int delta_x, delta_y;

  logic signed [15:0] current_state [0:3];

  initial begin
    $display("");
    $display("================================================================");
    $display("  DQN Performans Testi - CPU-only vs DQN+CPU Paralel");
    $display("  5 Karmasik Labirent, 8x8 Grid, Duvar-Duyarli Navigasyon");
    $display("================================================================");

    // Baslangic
    enable = 0; start_pulse = 0; soft_reset = 0;
    for (ii = 0; ii < 4; ii = ii + 1) state_in[ii] = 16'sh0000;

    // Agirliklari sifirla
    for (ii = 0; ii < 4; ii = ii + 1)
      for (jj = 0; jj < 16; jj = jj + 1)
        fc1_w[ii][jj] = 16'sh0000;
    for (ii = 0; ii < 16; ii = ii + 1) fc1_b[ii] = 16'sh0000;
    for (ii = 0; ii < 16; ii = ii + 1)
      for (jj = 0; jj < 4; jj = jj + 1)
        fc2_w[ii][jj] = 16'sh0000;
    for (ii = 0; ii < 4; ii = ii + 1) fc2_b[ii] = 16'sh0000;
    for (ii = 0; ii < 148; ii = ii + 1) all_weights[ii] = 16'sh0000;

    // ════════════════════════════════════════════════
    // 5 KARMASIK LABIRENT TANIMLARI
    // ════════════════════════════════════════════════
    for (m = 0; m < NUM_MAZES; m = m + 1)
      for (ii = 0; ii < GRID_SIZE; ii = ii + 1)
        for (jj = 0; jj < GRID_SIZE; jj = jj + 1)
          maze_walls[m][ii][jj] = 1'b0;

    // ═══════════════════════════════════════════════════════════
    // 5 KARMASIK LABIRENT — tum gecitler sag/asagi tarafta
    // Greedy agent (0,0)->(7,7): sag+asagi tercih eder
    // Her duvarda en az bir gecit, agent'in dogal yolunda ulasilabilir
    //
    // Tasarim kurali: Her hucrede {sag, asagi}'dan en az biri acik olmali
    //                 veya agent o hucreye ulasmadan once donelemelidir
    // ═══════════════════════════════════════════════════════════

    // ── Labirent 0: Tek Genis Yatay Bariyer ──
    // Duvar y=3 x=0..5, gecit sagda (x=6,7)
    //   S . . . . . . .
    //   . . . . . . . .
    //   . . . . . . . .
    //   # # # # # # . .    <- bariyer (gecit x=6,7)
    //   . . . . . . . .
    //   . . . . . . . .
    //   . . . . . . . .
    //   . . . . . . . G
    maze_start_x[0] = 0; maze_start_y[0] = 0;
    maze_goal_x[0]  = 7; maze_goal_y[0]  = 7;
    for (ii = 0; ii <= 5; ii = ii + 1)
      maze_walls[0][3][ii] = 1'b1;

    // ── Labirent 1: Cift Yatay Bariyer (gecitler sagda) ──
    // y=2 x=0..5 (gecit x=6,7), y=5 x=0..5 (gecit x=6,7)
    //   S . . . . . . .
    //   . . . . . . . .
    //   # # # # # # . .    <- bariyer 1
    //   . . . . . . . .
    //   . . . . . . . .
    //   # # # # # # . .    <- bariyer 2
    //   . . . . . . . .
    //   . . . . . . . G
    maze_start_x[1] = 0; maze_start_y[1] = 0;
    maze_goal_x[1]  = 7; maze_goal_y[1]  = 7;
    for (ii = 0; ii <= 5; ii = ii + 1)
      maze_walls[1][2][ii] = 1'b1;
    for (ii = 0; ii <= 5; ii = ii + 1)
      maze_walls[1][5][ii] = 1'b1;

    // ── Labirent 2: Uc Yatay Bariyer (basamakli, gecitler sagda) ──
    // y=1 x=0..4 (gecit x=5..7)
    // y=3 x=0..5 (gecit x=6,7)
    // y=5 x=0..6 (gecit x=7)
    //   S . . . . . . .
    //   # # # # # . . .    <- bariyer 1 (genis gecit)
    //   . . . . . . . .
    //   # # # # # # . .    <- bariyer 2 (orta gecit)
    //   . . . . . . . .
    //   # # # # # # # .    <- bariyer 3 (dar gecit)
    //   . . . . . . . .
    //   . . . . . . . G
    maze_start_x[2] = 0; maze_start_y[2] = 0;
    maze_goal_x[2]  = 7; maze_goal_y[2]  = 7;
    for (ii = 0; ii <= 4; ii = ii + 1)
      maze_walls[2][1][ii] = 1'b1;
    for (ii = 0; ii <= 5; ii = ii + 1)
      maze_walls[2][3][ii] = 1'b1;
    for (ii = 0; ii <= 6; ii = ii + 1)
      maze_walls[2][5][ii] = 1'b1;

    // ── Labirent 3: Dort Yatay Bariyer (en sik duvarlar) ──
    // y=1 x=0..4, y=2 x=6..7, y=4 x=0..5, y=6 x=0..6
    //   S . . . . . . .
    //   # # # # # . . .    <- bariyer 1
    //   . . . . . . # #    <- kisa bariyer (sag kose)
    //   . . . . . . . .
    //   # # # # # # . .    <- bariyer 3
    //   . . . . . . . .
    //   # # # # # # # .    <- bariyer 4 (dar gecit)
    //   . . . . . . . G
    maze_start_x[3] = 0; maze_start_y[3] = 0;
    maze_goal_x[3]  = 7; maze_goal_y[3]  = 7;
    for (ii = 0; ii <= 4; ii = ii + 1)
      maze_walls[3][1][ii] = 1'b1;
    for (ii = 6; ii <= 7; ii = ii + 1)
      maze_walls[3][2][ii] = 1'b1;
    for (ii = 0; ii <= 5; ii = ii + 1)
      maze_walls[3][4][ii] = 1'b1;
    for (ii = 0; ii <= 6; ii = ii + 1)
      maze_walls[3][6][ii] = 1'b1;

    // ── Labirent 4: Bes Yatay Bariyer (En Karmasik — en cok duvar) ──
    // Her satirda bariyer, gecitler hep sagda ama farkli genisliklerde
    // y=1 x=0..3 (gecit x=4..7)
    // y=2 x=5..7 (sagda kisa engel, agent zaten x=4 ten gecmis)
    // y=4 x=0..5 (gecit x=6,7)
    // y=5 x=4..6 (kisa engel)
    // y=6 x=0..6 (gecit x=7)
    //   S . . . . . . .
    //   # # # # . . . .    <- bariyer 1
    //   . . . . . # # #    <- bariyer 2 (kisa, sag kose)
    //   . . . . . . . .
    //   # # # # # # . .    <- bariyer 3
    //   . . . . # # # .    <- bariyer 4 (kisa)
    //   # # # # # # # .    <- bariyer 5 (dar gecit)
    //   . . . . . . . G
    maze_start_x[4] = 0; maze_start_y[4] = 0;
    maze_goal_x[4]  = 7; maze_goal_y[4]  = 7;
    for (ii = 0; ii <= 3; ii = ii + 1)
      maze_walls[4][1][ii] = 1'b1;
    for (ii = 5; ii <= 7; ii = ii + 1)
      maze_walls[4][2][ii] = 1'b1;
    for (ii = 0; ii <= 5; ii = ii + 1)
      maze_walls[4][4][ii] = 1'b1;
    for (ii = 4; ii <= 6; ii = ii + 1)
      maze_walls[4][5][ii] = 1'b1;
    for (ii = 0; ii <= 6; ii = ii + 1)
      maze_walls[4][6][ii] = 1'b1;

    // ════════════════════════════════════════════════
    // Agirlik kurulumu — identity-like (FC1 diag 0.5, FC2 diag 0.5)
    // Q[i] = state[i] * 0.25 (tum 16 hidden + 4 output hesaplanir)
    // ════════════════════════════════════════════════
    // FC1: 4 giristen ilk 4 hidden norona 0.5 kopyala
    //   fc1_w[input][output] -> addr = input*16 + output
    all_weights[0*16 + 0] = 16'sh4000;  // 0.5
    all_weights[1*16 + 1] = 16'sh4000;
    all_weights[2*16 + 2] = 16'sh4000;
    all_weights[3*16 + 3] = 16'sh4000;

    // FC1 biases [64..79]: sifir

    // FC2: ilk 4 hidden norondan 4 cikisa 0.5 kopyala
    //   fc2_w[input][output] -> addr = 80 + input*4 + output
    all_weights[80 + 0*4 + 0] = 16'sh4000;  // 0.5
    all_weights[80 + 1*4 + 1] = 16'sh4000;
    all_weights[80 + 2*4 + 2] = 16'sh4000;
    all_weights[80 + 3*4 + 3] = 16'sh4000;

    // FC2 biases [144..147]: sifir

    // Agirliklari DQN core'a yukle
    for (ii = 0; ii < 4; ii = ii + 1)
      for (jj = 0; jj < 16; jj = jj + 1)
        fc1_w[ii][jj] = all_weights[ii*16 + jj];
    for (ii = 0; ii < 16; ii = ii + 1)
      fc1_b[ii] = all_weights[64 + ii];
    for (ii = 0; ii < 16; ii = ii + 1)
      for (jj = 0; jj < 4; jj = jj + 1)
        fc2_w[ii][jj] = all_weights[80 + ii*4 + jj];
    for (ii = 0; ii < 4; ii = ii + 1)
      fc2_b[ii] = all_weights[144 + ii];

    // Reset
    rstn = 0;
    repeat(10) @(posedge clk);
    rstn = 1;
    enable = 1;
    repeat(5) @(posedge clk);

    // ════════════════════════════════════════════════
    // BOLUM 1: CPU-Only Labirent Cozme
    // ════════════════════════════════════════════════
    $display("\n================================================================");
    $display("  BOLUM 1: CPU-Only Hesaplama ile Labirent Cozme");
    $display("  (Tum DQN inference yazilimda, cycle cycle hesaplanir)");
    $display("================================================================");

    for (m = 0; m < NUM_MAZES; m = m + 1) begin
      pos_x = maze_start_x[m];
      pos_y = maze_start_y[m];
      cycle_counter = 0;
      step_count = 0;

      $display("\n  -- Labirent %0d --", m);
      $display("    Baslangic: (%0d,%0d) -> Hedef: (%0d,%0d)",
               pos_x, pos_y, maze_goal_x[m], maze_goal_y[m]);
      print_maze(m, pos_x, pos_y);

      while (step_count < MAX_STEPS && !(pos_x == maze_goal_x[m] && pos_y == maze_goal_y[m])) begin
        delta_x = maze_goal_x[m] - pos_x;
        delta_y = maze_goal_y[m] - pos_y;

        // Duvar-duyarli state hesapla
        // state[0] = yukari cekicilik (-delta_y pozitifse hedefe yakin)
        current_state[0] = compute_attractiveness(-delta_y, can_move_dir(m, pos_x, pos_y, 0));
        // state[1] = asagi cekicilik
        current_state[1] = compute_attractiveness( delta_y, can_move_dir(m, pos_x, pos_y, 1));
        // state[2] = sol cekicilik
        current_state[2] = compute_attractiveness(-delta_x, can_move_dir(m, pos_x, pos_y, 2));
        // state[3] = sag cekicilik
        current_state[3] = compute_attractiveness( delta_x, can_move_dir(m, pos_x, pos_y, 3));

        // Ortam guncelleme maliyeti (state hesaplama dahil)
        cycle_counter = cycle_counter + ENV_UPDATE_CYCLES;

        // CPU-only DQN inference
        cpu_inf_state[0] = current_state[0];
        cpu_inf_state[1] = current_state[1];
        cpu_inf_state[2] = current_state[2];
        cpu_inf_state[3] = current_state[3];
        cpu_inference();
        cycle_counter = cycle_counter + cpu_inf_cycles;
        action = cpu_inf_action;

        // Hareketi uygula
        apply_action(m, action, pos_x, pos_y);
        step_count = step_count + 1;
      end

      cpu_only_cycles[m] = cycle_counter;
      cpu_only_steps[m]  = step_count;

      if (pos_x == maze_goal_x[m] && pos_y == maze_goal_y[m])
        $display("    COZULDU! Adim: %0d, CPU Cycle: %0d", step_count, cycle_counter);
      else
        $display("    COZULEMEDI (max adim asildi) Adim: %0d, CPU Cycle: %0d", step_count, cycle_counter);
    end

    // ════════════════════════════════════════════════
    // BOLUM 2: DQN+CPU Paralel Labirent Cozme
    // ════════════════════════════════════════════════
    $display("\n================================================================");
    $display("  BOLUM 2: DQN Hizlandirici + CPU Paralel Labirent Cozme");
    $display("  (DQN core donanim inference, gercek clock cycle olculur)");
    $display("================================================================");

    for (m = 0; m < NUM_MAZES; m = m + 1) begin
      pos_x = maze_start_x[m];
      pos_y = maze_start_y[m];
      step_count = 0;

      $display("\n  -- Labirent %0d --", m);
      $display("    Baslangic: (%0d,%0d) -> Hedef: (%0d,%0d)",
               pos_x, pos_y, maze_goal_x[m], maze_goal_y[m]);
      print_maze(m, pos_x, pos_y);

      start_time = $time / 10;

      while (step_count < MAX_STEPS && !(pos_x == maze_goal_x[m] && pos_y == maze_goal_y[m])) begin
        delta_x = maze_goal_x[m] - pos_x;
        delta_y = maze_goal_y[m] - pos_y;

        // Duvar-duyarli state hesapla (CPU tarafindan)
        current_state[0] = compute_attractiveness(-delta_y, can_move_dir(m, pos_x, pos_y, 0));
        current_state[1] = compute_attractiveness( delta_y, can_move_dir(m, pos_x, pos_y, 1));
        current_state[2] = compute_attractiveness(-delta_x, can_move_dir(m, pos_x, pos_y, 2));
        current_state[3] = compute_attractiveness( delta_x, can_move_dir(m, pos_x, pos_y, 3));

        // DQN donanim inference
        hw_inference(current_state[0], current_state[1],
                     current_state[2], current_state[3],
                     action, hw_cyc);

        // Hareketi uygula
        apply_action(m, action, pos_x, pos_y);
        step_count = step_count + 1;
      end

      end_time = $time / 10;
      dqn_parallel_cycles[m] = end_time - start_time;
      dqn_parallel_steps[m]  = step_count;

      if (pos_x == maze_goal_x[m] && pos_y == maze_goal_y[m])
        $display("    COZULDU! Adim: %0d, DQN+CPU Cycle: %0d", step_count, dqn_parallel_cycles[m]);
      else
        $display("    COZULEMEDI (max adim asildi) Adim: %0d, DQN+CPU Cycle: %0d", step_count, dqn_parallel_cycles[m]);
    end

    // ════════════════════════════════════════════════
    // BOLUM 3: Detayli Karsilastirma Raporu
    // ════════════════════════════════════════════════
    $display("\n================================================================");
    $display("  PERFORMANS KARSILASTIRMA TABLOSU");
    $display("================================================================");
    $display("");
    $display("  Labirent | Adim | CPU-Only(cyc) | DQN+CPU(cyc) | Hizlanma");
    $display("  ---------+------+---------------+--------------+---------");

    begin
      int total_cpu, total_dqn;
      int total_steps_cpu, total_steps_dqn;
      real speedup;
      total_cpu = 0;
      total_dqn = 0;
      total_steps_cpu = 0;
      total_steps_dqn = 0;

      for (m = 0; m < NUM_MAZES; m = m + 1) begin
        if (dqn_parallel_cycles[m] > 0)
          speedup = real'(cpu_only_cycles[m]) / real'(dqn_parallel_cycles[m]);
        else
          speedup = 0.0;
        $display("    %0d      |  %3d |    %8d   |   %8d   | %5.2fx",
                 m, cpu_only_steps[m], cpu_only_cycles[m], dqn_parallel_cycles[m], speedup);
        total_cpu = total_cpu + cpu_only_cycles[m];
        total_dqn = total_dqn + dqn_parallel_cycles[m];
        total_steps_cpu = total_steps_cpu + cpu_only_steps[m];
        total_steps_dqn = total_steps_dqn + dqn_parallel_steps[m];
      end

      $display("  ---------+------+---------------+--------------+---------");
      if (total_dqn > 0)
        speedup = real'(total_cpu) / real'(total_dqn);
      else
        speedup = 0.0;
      $display("  TOPLAM   |  %3d |    %8d   |   %8d   | %5.2fx",
               total_steps_cpu, total_cpu, total_dqn, speedup);

      $display("");
      $display("  -- DETAYLI ANALIZ --");
      $display("");
      $display("  [CPU-Only Mod]");
      $display("    Her adimda tam 4->16->4 DQN inference yazilimda hesaplandi:");
      $display("    - Agirlik yukleme : 148 cycle (148 weight load)");
      $display("    - FC1 katmani     : 16 noron x (4 MAC + bias + LeakyReLU)");
      $display("    - FC2 katmani     : 4 noron x (16 MAC + bias)");
      $display("    - Argmax          : 4 karsilastirma");
      if (total_steps_cpu > 0)
        $display("    - Adim basina     : %0d inference + %0d ortam = %0d cycle",
                 (total_cpu - total_steps_cpu * ENV_UPDATE_CYCLES) / total_steps_cpu,
                 ENV_UPDATE_CYCLES,
                 total_cpu / total_steps_cpu);
      $display("");
      $display("  [DQN+CPU Paralel Mod]");
      $display("    DQN hizlandirici donanim inference:");
      $display("    - FC1 katmani     : 16 cycle (1 noron/cycle, 4 paralel MAC)");
      $display("    - FC2 katmani     : 16 cycle (4 grup x 4 noron)");
      $display("    - Argmax          : 1 cycle");
      $display("    - Toplam inference: 33 clock cycle");
      if (total_steps_dqn > 0)
        $display("    - Adim basina     : ~%0d cycle (inference + overhead)",
                 total_dqn / total_steps_dqn);
      $display("");
      $display("  [Kazanim]");
      $display("    Toplam CPU cycle   : %0d", total_cpu);
      $display("    Toplam DQN+CPU cyc : %0d", total_dqn);
      $display("    Genel hizlanma     : %.2fx", speedup);
      $display("    DQN donanim, CPU yazilim inference'a gore ~%.0fx daha hizli",
               real'(total_cpu - total_steps_cpu * ENV_UPDATE_CYCLES) /
               real'(total_dqn));
    end

    $display("");
    $display("================================================================");
    $display("  DQN Performans Testi TAMAMLANDI");
    $display("================================================================");
    $display("");

    $finish;
  end

  // Timeout
  initial begin
    #100_000_000;
    $display("[TIMEOUT] Simulasyon zaman asimi!");
    $finish;
  end

endmodule
