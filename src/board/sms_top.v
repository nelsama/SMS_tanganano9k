// sms_top.v : Master System on the Sipeed Tang Nano 9K (GW1NR-LV9QN88PC6/I5).
//   PLL sys : 27 / 5 x 16 = 86.4 MHz, + 90 degrees (PSRAM), CLKOUTD /4 = 21.6 MHz
//   PLL hdmi: 27 x 5 = 135 MHz, CLKDIV /5 = 27 MHz pixel clock
// Pad: joy_* pins, fire = button 1, btn2 = button 2; pin 85 = Pause.
// S1 = reset, S2 = menu.
// LEDs: 0 HDMI locked, 1 heartbeat, 2 any pad button, 3 menu, 4 loading.
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
  wire clk, memclk, memclk_p, clk135, clk_pix, lock_s, lock_h;

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

  rPLL u_pll_hdmi(.CLKIN(clk27), .CLKOUT(clk135), .CLKOUTD(), .LOCK(lock_h),
    .CLKOUTP(), .CLKOUTD3(), .RESET(1'b0), .RESET_P(1'b0), .CLKFB(1'b0),
    .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b1111));
  defparam u_pll_hdmi.FCLKIN = "27";
  defparam u_pll_hdmi.DEVICE = "GW1NR-9C";
  defparam u_pll_hdmi.IDIV_SEL = 0;
  defparam u_pll_hdmi.FBDIV_SEL = 4;
  defparam u_pll_hdmi.ODIV_SEL = 4;

  CLKDIV u_div_pix(.CLKOUT(clk_pix), .HCLKIN(clk135), .RESETN(lock_h), .CALIB(1'b0));
  defparam u_div_pix.DIV_MODE = "5";
  defparam u_div_pix.GSREN = "false";

  // reset: power-on, S1, ~12 ms
  reg [1:0]  rs = 0;
  reg [18:0] por = 0;
  wire reset = !por[18];
  always @(posedge clk) begin
    rs <= {rs[0], btn_s1_n};
    if (!lock_s || !rs[1]) por <= 0;
    else if (reset) por <= por + 1'b1;
  end
  reg [3:0] prst = 4'hF;
  always @(posedge clk_pix or negedge lock_h)
    if (!lock_h) prst <= 4'hF; else prst <= {prst[2:0], 1'b0};

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
  wire        pix_we, frame_t, locked;
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
    .pix_we(pix_we), .pix_addr(pix_addr), .pix_color(pix_color), .frame_t(frame_t));

  wire [7:0] r, g, b;
  wire hs, vs, de;
  sms2hdmi u_v2h(.clk(clk), .we(pix_we), .waddr(pix_addr), .wdata(pix_color), .frame_t(frame_t),
    .clk_pix(clk_pix), .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de), .locked(locked));

  hdmi_module u_hdmi(.vga_clk_x5(clk135), .vga_clk(clk_pix), .rst(prst[3]),
    .vga_red_in(r), .vga_green_in(g), .vga_blue_in(b),
    .vga_hsync_in(hs), .vga_vsync_in(vs), .vga_disp_ena_in(de),
    .tmds_c0_p_out(tmds_d_p[0]), .tmds_c0_n_out(tmds_d_n[0]),
    .tmds_c1_p_out(tmds_d_p[1]), .tmds_c1_n_out(tmds_d_n[1]),
    .tmds_c2_p_out(tmds_d_p[2]), .tmds_c2_n_out(tmds_d_n[2]),
    .tmds_ck_p_out(tmds_ck_p), .tmds_ck_n_out(tmds_ck_n));

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
  reg [1:0] lk = 0;
  always @(posedge clk) lk <= {lk[0], locked};
  assign led_n = ~{1'b0, sd_active, menu, |pad, beat[23], lk[1]};
endmodule
