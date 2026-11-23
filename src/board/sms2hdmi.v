// sms2hdmi.v : SMS pixels -> 720x480p raster (855 x 524 at 27 MHz, 60.27 Hz).
// One SMS line (1368 clk at 21.6 MHz) = 2 HDMI lines; the picture is
// 256 x 2.5 = 640 pixels wide (centre pixel of every pair blended), 240 x 2
// lines high. Two-line buffer; the raster is locked to the SMS frame.
module sms2hdmi(
  input             clk,        // SMS side
  input             we,
  input      [8:0]  waddr,
  input      [5:0]  wdata,
  input             frame_t,
  input             clk_pix,
  output reg [7:0]  r, g, b,
  output reg        hs, vs, de,
  output reg        locked
);
  localparam H_TOT = 855, V_TOT = 524, X0 = 40, VLOCK = V_TOT - 2, HLOCK = 4;

  reg [5:0] lb[0:511];
  always @(posedge clk) if (we) lb[waddr] <= wdata;

  reg [9:0] h, v;
  reg [2:0] ph;       // phase of the 2.5x scaler, 0..4
  reg [7:0] px;
  reg [2:0] ft;
  initial begin h = 0; v = 0; ph = 0; px = 0; ft = 0; locked = 0; end

  always @(posedge clk_pix) begin
    ft <= {ft[1:0], frame_t};
    if (h == H_TOT - 1) begin
      h <= 0;
      v <= (v == V_TOT - 1) ? 10'd0 : v + 1'b1;
    end else h <= h + 1'b1;

    if (h < X0) begin ph <= 0; px <= 0; end
    else begin                              // pixel sequence a a b b b
      ph <= (ph == 4) ? 3'd0 : ph + 1'b1;
      if (ph == 1 || ph == 4) px <= px + 1'b1;
    end

    if (ft[2] != ft[1]) begin
      if (v == VLOCK && h >= HLOCK - 3 && h <= HLOCK + 3) locked <= 1;
      else begin v <= VLOCK; h <= HLOCK; locked <= 0; end
    end
  end

  // stage 1: address (px valid for pixel h-1)   stage 2: colour number
  // stage 3: rgb   stage 4: output
  reg [5:0]  c2;
  reg        vis1, vis2, vis3, bl1, bl2, bl3, de1, de2, de3, hs1, hs2, hs3, vs1, vs2, vs3;
  reg [8:0]  ra;
  wire [14:0] pal = {c2[1:0], c2[1:0], c2[1], c2[3:2], c2[3:2], c2[3], c2[5:4], c2[5:4], c2[5]};
  reg [14:0] rgb3, prev;
  wire [5:0] ar = rgb3[14:10] + prev[14:10];
  wire [5:0] ag = rgb3[9:5]   + prev[9:5];
  wire [5:0] ab = rgb3[4:0]   + prev[4:0];
  wire [5:0] sr = bl3 ? ar : {rgb3[14:10], rgb3[14]};
  wire [5:0] sg = bl3 ? ag : {rgb3[9:5],   rgb3[9]};
  wire [5:0] sb = bl3 ? ab : {rgb3[4:0],   rgb3[4]};

  always @(posedge clk_pix) begin
    ra   <= {v[1], px};
    vis1 <= h >= X0 && h < X0 + 640 && v < 480;
    bl1  <= ph == 2;
    de1  <= h < 720 && v < 480;
    hs1  <= !(h >= 736 && h < 798);
    vs1  <= !(v >= 489 && v < 495);
    c2   <= lb[ra];
    {vis2, bl2, de2, hs2, vs2} <= {vis1, bl1, de1, hs1, vs1};
    rgb3 <= pal;  prev <= rgb3;
    {vis3, bl3, de3, hs3, vs3} <= {vis2, bl2, de2, hs2, vs2};
    {de, hs, vs} <= {de3, hs3, vs3};
    r <= vis3 ? {sr, sr[5:4]} : 8'd0;
    g <= vis3 ? {sg, sg[5:4]} : 8'd0;
    b <= vis3 ? {sb, sb[5:4]} : 8'd0;
  end
endmodule
