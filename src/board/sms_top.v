// sms_top.v : Master System on the Sipeed Tang Nano 9K (GW1NR-LV9QN88PC6/I5).
//   PLL sys : 27 / 5 x 16 = 86.4 MHz, + 90 degrees (PSRAM), CLKOUTD /4 = 21.6 MHz
//   hdmi_phy: 27 x 5 = 135 MHz, CLKDIV /5 = 27 MHz pixel clock
// Pad: joy_* pins, fire = button 1, btn2 = button 2; pin 85 = Pause.
// S1 = reset, S2 = menu.
// LEDs: 0 SMS locked to the HDMI raster, 1 heartbeat, 2 any pad button, 3 menu, 4 loading.
module sms_top(
  input        clk27,
  input        btn_s1_n, btn_s2_n, btn_start1, btn_credit,
  output [5:0] led_n,
  output       tmds_ck_p, tmds_ck_n,
  output [2:0] tmds_d_p, tmds_d_n,
  input        joy_up, joy_down, joy_left, joy_right, joy_fire, joy_btn2,
  output       audio_l, audio_r,
  output       sd_sck, sd_cmd, sd_cs,
  input        sd_dat0,
  output [1:0]  O_psram_ck,
  output [1:0]  O_psram_ck_n,
  inout  [1:0]  IO_psram_rwds,
  inout  [15:0] IO_psram_dq,
  output [1:0]  O_psram_reset_n,
  output [1:0]  O_psram_cs_n
);
  wire clk, memclk, memclk_p, clk_pix, lock_s;

  rPLL u_pll_sys(.CLKIN(clk27), .CLKOUT(memclk), .CLKOUTD(clk), .LOCK(lock_s),
    .CLKOUTP(memclk_p), .CLKOUTD3(), .RESET(1'b0), .RESET_P(1'b0), .CLKFB(1'b0),
    .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b1111));
  defparam u_pll_sys.FCLKIN = "27";
  defparam u_pll_sys.DEVICE = "GW1NR-9C";
  defparam u_pll_sys.IDIV_SEL = 4;
  defparam u_pll_sys.FBDIV_SEL = 15;
  defparam u_pll_sys.ODIV_SEL = 8;
  defparam u_pll_sys.DYN_SDIV_SEL = 4;
  defparam u_pll_sys.PSDA_SEL = "0100";

  // reset: power-on, S1, ~12 ms
  reg [1:0]  rs = 0;
  reg [18:0] por = 0;
  wire reset = !por[18];
  always @(posedge clk) begin
    rs <= {rs[0], btn_s1_n};
    if (!lock_s || !rs[1]) por <= 0;
    else if (reset) por <= por + 1'b1;
  end

  // pad, active low pins; opposite directions together are ignored
  reg [5:0] p0 = 0, p1 = 0;
  always @(posedge clk) begin
    p0 <= ~{joy_btn2, joy_fire, joy_right, joy_left, joy_down, joy_up};
    p1 <= p0;
  end
  wire [5:0] pad = {p1[5:4], p1[3] & ~p1[2], p1[2] & ~p1[3], p1[1] & ~p1[0], p1[0] & ~p1[1]};
  // Pause, debounced (~3 ms both ways)
  reg [1:0]  m2 = 2'b11;
  reg [15:0] md = 0;
  reg        pause = 0;
  always @(posedge clk) begin
    m2 <= {m2[0], btn_start1};
    if (!m2[1] == pause) md <= 0;
    else begin md <= md + 1'b1; if (&md) pause <= !pause; end
  end

  wire [15:0] sample;
  wire        pix_we, line_t, line_f, locked;
  wire [8:0]  pix_addr;
  wire [5:0]  pix_color;
  // S2, debounced (~3 ms)
  reg [1:0]  s2 = 2'b11;
  reg [15:0] sd = 0;
  reg        to_menu = 0;
  always @(posedge clk) begin
    s2 <= {s2[0], btn_s2_n};
    if (s2[1]) sd <= 0; else if (!(&sd)) sd <= sd + 1'b1;
    to_menu <= &sd;
  end
  wire        menu, sd_active, t0, t1, we0, we1;
  wire [21:0] a0, a1;
  wire [7:0]  d0, d1;
  wire [15:0] w0, w1;
  sms_psport u_p0(.memclk(memclk), .memclk_p(memclk_p), .resetn(lock_s), .t(t0), .we(we0),
    .addr(a0), .din(d0), .dout(w0), .ck(O_psram_ck[0]), .cs_n(O_psram_cs_n[0]),
    .rwds(IO_psram_rwds[0]), .dq(IO_psram_dq[7:0]));
  sms_psport u_p1(.memclk(memclk), .memclk_p(memclk_p), .resetn(lock_s), .t(t1), .we(we1),
    .addr(a1), .din(d1), .dout(w1), .ck(O_psram_ck[1]), .cs_n(O_psram_cs_n[1]),
    .rwds(IO_psram_rwds[1]), .dq(IO_psram_dq[15:8]));
  assign O_psram_ck_n = 2'b00;
  assign O_psram_reset_n = {2{lock_s}};
  sms_sys u_sys(.to_menu(to_menu), .menu(menu), .sd_active(sd_active),
    .sd_sck(sd_sck), .sd_cmd(sd_cmd), .sd_cs(sd_cs), .sd_dat0(sd_dat0),
    .t0(t0), .t1(t1), .we0(we0), .we1(we1), .a0(a0), .a1(a1), .d0(d0), .d1(d1), .w0(w0), .w1(w1),
    .clk(clk), .reset_in(reset), .pad1(pad), .pad2(6'd0), .pause(pause), .sample(sample),
    .pix_we(pix_we), .pix_addr(pix_addr), .pix_color(pix_color), .frame_t(),
    .line_t(line_t), .line_f(line_f), .locked(locked));

  wire [7:0] r, g, b;
  wire hs, vs, de;
  wire [9:0] h_tx, v_tx;
  sms2hdmi u_v2h(.clk(clk), .we(pix_we), .waddr(pix_addr), .wdata(pix_color),
    .clk_pix(clk_pix), .line_t(line_t), .line_f(line_f), .h_tx(h_tx), .v_tx(v_tx), .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de));

  // HDMI with 48 kHz audio (DVI only: FULL => false in hdmi_tx.vhd)
  wire        audio_req;
  wire [15:0] haudio;
  wire [9:0]  q0, q1, q2;
  hdmi_audio u_haud(.clk(clk), .sample(sample), .audio_req(audio_req), .audio(haudio));
  hdmi_tx u_tx(.clk(clk_pix), .h_cnt(h_tx), .v_cnt(v_tx), .hs(hs), .vs(vs), .de(de),
    .rgb({r, g, b}), .audio_req(audio_req), .audio(haudio), .q0(q0), .q1(q1), .q2(q2));
  hdmi_phy u_phy(.clk_27(clk27), .clk_pixel(clk_pix), .q0(q0), .q1(q1), .q2(q2),
    .tmds_c0_p(tmds_d_p[0]), .tmds_c0_n(tmds_d_n[0]),
    .tmds_c1_p(tmds_d_p[1]), .tmds_c1_n(tmds_d_n[1]),
    .tmds_c2_p(tmds_d_p[2]), .tmds_c2_n(tmds_d_n[2]),
    .tmds_ck_p(tmds_ck_p), .tmds_ck_n(tmds_ck_n));

  // first-order sigma-delta DAC
  reg [15:0] smp = 0;
  reg [16:0] acc = 0;
  always @(posedge clk) begin
    smp <= sample;
    acc <= {1'b0, acc[15:0]} + {1'b0, smp};
  end
  assign audio_l = acc[16];
  assign audio_r = acc[16];

  reg [23:0] beat = 0;
  always @(posedge clk) beat <= beat + 1'b1;
  assign led_n = ~{1'b0, sd_active, menu, |pad, beat[23], locked};
endmodule
