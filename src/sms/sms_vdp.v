// sms_vdp.v : Sega Master System VDP (315-5246 style), mode 4, 192 lines, NTSC.
//
// clk = 4 clk per dot; 342 dots x 262 lines. hc = 0 is the dot where the V
// counter changes; the picture is hc 24..279.
// One 16 KB single-port VRAM, shared by the phase of the dot:
//   ph 0 CPU   ph 1 background   ph 2 sprites   ph 3 unused
// Sprites: Y scan while the previous line is shown, pattern fetch and drawing
// into a 256 x 4 line buffer in the horizontal blanking.
// Not implemented: TMS9918 modes, 224 / 240 line modes, SMS1 zoom bug.
module sms_vdp(
  input             clk, reset,
  // CPU side: one-clk pulses; a0 = 1 control / status, 0 data
  input             wr, rd, a0,
  input      [7:0]  din,
  output reg [7:0]  dout,       // valid the clk after rd, then held
  output     [7:0]  vcount,
  output     [7:0]  hcount,
  output            irq_n,
  // video
  output            pix_we,
  output     [8:0]  pix_addr,   // {line[0], x}
  output reg [5:0]  pix_color,  // BBGGRR
  output reg        frame_t     // toggles at the first of the 240 output lines
);
  // --- counters -------------------------------------------------------------
  reg [1:0] ph;
  reg [8:0] hc, line;
  initial begin ph = 0; hc = 0; line = 0; frame_t = 0; end
  wire eol = ph == 3 && hc == 341;
  always @(posedge clk) begin
    if (reset) begin ph <= 0; hc <= 0; line <= 0; end
    else begin
      ph <= ph + 1'b1;
      if (ph == 3) hc <= hc == 341 ? 9'd0 : hc + 1'b1;
      if (eol) line <= line == 261 ? 9'd0 : line + 1'b1;
    end
    if (!reset && ph == 1 && hc == 0 && line == 238) frame_t <= !frame_t;
  end
  wire       line0 = ph == 0 && hc == 0;          // start of a line
  wire [8:0] x     = hc - 9'd24;
  wire       act_h = hc >= 24 && hc < 280;
  wire       act_v = line < 192;
  assign vcount = line <= 218 ? line[7:0] : line[7:0] - 8'd6;
  wire [8:0] xh = hc >= 24 ? hc - 9'd24 : hc + 9'd318;
  assign hcount = xh[8:1] <= 8'h93 ? xh[8:1] : xh[8:1] + 8'h55;

  // --- registers and CPU port -------------------------------------------------
  reg [7:0]  r0, r1, r7, r8, r9, r10;
  reg [2:0]  r2;                // r2[3:1]
  reg [5:0]  r5;                // r5[6:1]
  reg        r6;                // r6[2]
  reg [13:0] addr;
  reg [1:0]  code;
  reg        second;
  reg [7:0]  rbuf, wbuf;
  reg        rd_pend, wr_pend;
  reg [13:0] ca;                // address of the pending CPU access
  reg        f_vb, f_ovr, f_col, f_line;
  reg        cpu_rd_d;          // VRAM data for the CPU arrives this clk
  reg [7:0]  lcnt;
  reg        set_ovr, set_col;
  reg [7:0]  vq;                // VRAM output

  reg [5:0]  cram[0:31];
  wire       cram_we = wr && !a0 && code == 2'd3;
  always @(posedge clk) if (cram_we) cram[addr[4:0]] <= din[5:0];

  assign irq_n = !(f_vb && r1[5] || f_line && r0[4]);
  wire st_rd = rd && a0;
  initial begin
    r0 = 0; r1 = 0; r2 = 7; r5 = 6'h3F; r6 = 1; r7 = 0; r8 = 0; r9 = 0; r10 = 8'hFF;
    second = 0; code = 0; addr = 0; rd_pend = 0; wr_pend = 0;
    f_vb = 0; f_ovr = 0; f_col = 0; f_line = 0; lcnt = 8'hFF;
  end
  always @(posedge clk) begin
    cpu_rd_d <= ph == 0 && rd_pend;
    if (cpu_rd_d) rbuf <= vq;
    if (ph == 0) begin rd_pend <= 0; wr_pend <= 0; end

    // status flags: a set wins over the clear
    if (st_rd) begin f_vb <= 0; f_ovr <= 0; f_col <= 0; f_line <= 0; end
    if (line0 && line == 193) f_vb <= 1;
    if (set_ovr) f_ovr <= 1;
    if (set_col) f_col <= 1;
    // end of line L seen at the start of line L + 1; counts lines 0..192
    if (line0) begin
      if (line >= 1 && line <= 193) begin
        if (lcnt == 0) begin lcnt <= r10; f_line <= 1; end
        else lcnt <= lcnt - 1'b1;
      end else lcnt <= r10;
    end

    if (rd) begin
      second <= 0;
      if (a0) dout <= {f_vb, f_ovr, f_col, 5'h1F};
      else begin
        dout <= rbuf; rd_pend <= 1; ca <= addr; addr <= addr + 1'b1;
      end
    end
    if (wr && !a0) begin
      second <= 0; rbuf <= din;
      if (code != 2'd3) begin wr_pend <= 1; ca <= addr; wbuf <= din; end
      addr <= addr + 1'b1;
    end
    if (wr && a0) begin
      second <= !second;
      if (!second) addr[7:0] <= din;
      else begin
        code <= din[7:6];
        addr[13:8] <= din[5:0];
        if (din[7:6] == 0) begin
          rd_pend <= 1; ca <= {din[5:0], addr[7:0]};
          addr <= {din[5:0], addr[7:0]} + 1'b1;
        end
        if (din[7:6] == 2) case (din[3:0])
          4'd0:  r0 <= addr[7:0];
          4'd1:  r1 <= addr[7:0];
          4'd2:  r2 <= addr[3:1];
          4'd5:  r5 <= addr[6:1];
          4'd6:  r6 <= addr[2];
          4'd7:  r7 <= addr[7:0];
          4'd8:  r8 <= addr[7:0];
          4'd9:  r9 <= addr[7:0];
          4'd10: r10 <= addr[7:0];
          default: ;
        endcase
      end
    end
    if (reset) begin
      r0 <= 8'h36; r1 <= 8'h80; r2 <= 3'd7; r5 <= 6'h3F; r6 <= 0; r7 <= 0; r8 <= 0; r9 <= 0; r10 <= 8'hFF;
      second <= 0; code <= 0; addr <= 0; rd_pend <= 0; wr_pend <= 0;
      f_vb <= 0; f_ovr <= 0; f_col <= 0; f_line <= 0;
    end
  end

  // --- background ---------------------------------------------------------------
  reg [7:0] hs, vs;             // latched scrolls
  always @(posedge clk) begin
    if (ph == 3 && hc == 6) hs <= (r0[6] && line < 16) ? 8'd0 : r8;
    if (line0 && !act_v) vs <= r9;
  end
  wire [8:0] b   = x - {6'd0, hs[2:0]};
  wire [5:0] t   = b[8:3] + 1'b1;         // screen tile being fetched
  wire [4:0] col = t[4:0] - hs[7:3];
  wire       lock = r0[7] && !t[5] && t[4:3] == 2'd3;
  wire [8:0] ysum = {1'b0, line[7:0]} + {1'b0, vs};
  wire [8:0] ywrap = ysum >= 448 ? ysum - 9'd448 : ysum >= 224 ? ysum - 9'd224 : ysum;
  wire [7:0] ybg = lock ? line[7:0] : ywrap[7:0];
  reg  [8:0] nt;
  reg        nhf, nvf, npal, npri;
  reg  [7:0] p0, p1, p2, p3;
  wire [1:0] pln = b[1:0] - 2'd2;         // slots 2..5 = planes 0..3
  wire [13:0] bg_a = b[2:1] == 0 ? {r2, ybg[7:3], col, b[0]}
                                 : {nt, ybg[2:0] ^ {3{nvf}}, pln};
  function [7:0] flip(input [7:0] d, input f);
    flip = f ? {d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7]} : d;
  endfunction
  reg [7:0] s0, s1, s2, s3;
  reg       spal, spri;
  always @(posedge clk) begin
    if (ph == 2) case (b[2:0])
      0: nt[7:0] <= vq;
      1: {npri, npal, nvf, nhf, nt[8]} <= vq[4:0];
      2: p0 <= flip(vq, nhf);
      3: p1 <= flip(vq, nhf);
      4: p2 <= flip(vq, nhf);
      5: p3 <= flip(vq, nhf);
      default: ;
    endcase
    if (ph == 3) begin
      if (b[2:0] == 7) begin
        s0 <= p0; s1 <= p1; s2 <= p2; s3 <= p3; spal <= npal; spri <= npri;
      end else begin
        s0 <= s0 << 1; s1 <= s1 << 1; s2 <= s2 << 1; s3 <= s3 << 1;
      end
    end
  end

  // --- sprites --------------------------------------------------------------------
  reg        scan, fetch;
  reg  [5:0] si;
  reg  [3:0] sn, sk;            // found, being fetched
  reg  [2:0] step;
  reg  [9:0] hit[0:7];          // {row, index}
  wire [9:0] h     = hit[sk[2:0]];
  wire [7:0] sd    = vcount - vq;                  // row of line + 1 (Y = first line - 1)
  wire [4:0] sht   = {r1[1], !r1[1], 3'd0};       // 8 or 16
  wire [7:0] slim  = r1[0] ? {2'd0, sht, 1'b0} : {3'd0, sht};
  wire [3:0] srow  = r1[0] ? sd[4:1] : sd[3:0];
  reg  [7:0] fx, fn, f0, f1, f2;
  wire [1:0] spln  = step[1:0] - 2'd2;
  wire [13:0] sp_a =
      scan      ? {r5, 2'b00, si} :
      step < 2  ? {r5, 1'b1, h[5:0], step[0]} :
                  {r6, fn[7:1], r1[1] ? h[9] : fn[0], h[8:6], spln};
  // drawing
  reg        drw;
  reg  [3:0] dcnt;
  reg  [8:0] dx;
  reg  [7:0] d0, d1, d2, d3;
  reg        dv1;
  reg  [7:0] dx1;
  reg  [3:0] px1;
  initial begin scan = 0; fetch = 0; drw = 0; dv1 = 0; sn = 0; end

  reg  [3:0] sb[0:255];
  reg  [3:0] sbq;
  wire [7:0] sb_ra = act_h ? x[7:0] : dx[7:0];
  wire       sb_re = act_h ? ph == 0 : drw;
  wire       sb_cl = act_h && ph == 2;
  wire       sb_dw = dv1 && px1 != 0 && sbq == 0;
  always @(posedge clk) begin
    if (sb_re) sbq <= sb[sb_ra];
    if (sb_cl || sb_dw) sb[sb_cl ? x[7:0] : dx1] <= sb_cl ? 4'd0 : px1;
  end

  always @(posedge clk) begin
    set_ovr <= 0; set_col <= 0;
    // scan
    if (hc == 24 && ph == 0) begin
      scan <= r1[6] && (line == 261 || line < 191);
      si <= 0; sn <= 0;
    end else if (scan && ph == 3) begin
      si <= si + 1'b1;
      if (si == 63 || vq == 8'hD0) scan <= 0;
      if (vq != 8'hD0 && sd < slim) begin
        if (sn[3]) begin set_ovr <= 1; scan <= 0; end
        else begin
          hit[sn[2:0]] <= {srow, si};
          sn <= sn + 1'b1;
        end
      end
    end
    // pattern fetch
    if (hc == 280 && ph == 0) begin
      fetch <= sn != 0; sk <= 0; step <= 0;
    end else if (fetch && ph == 3) begin
      case (step)
        0: fx <= vq;
        1: fn <= vq;
        2: f0 <= vq;
        3: f1 <= vq;
        4: f2 <= vq;
        default: ;
      endcase
      step <= step + 1'b1;
      if (step == 5) begin
        step <= 0; sk <= sk + 1'b1;
        if (sk + 4'd1 == sn) fetch <= 0;
      end
    end
    // draw, 1 pixel / clk
    dv1 <= drw && !dx[8];
    dx1 <= dx[7:0];
    px1 <= {d3[7], d2[7], d1[7], d0[7]};
    if (dv1 && px1 != 0 && sbq != 0) set_col <= 1;
    if (fetch && ph == 3 && step == 5) begin
      drw <= 1; dcnt <= 0;
      dx <= {1'b0, fx} - {5'd0, r0[3], 3'd0};
      d0 <= f0; d1 <= f1; d2 <= f2; d3 <= vq;
    end else if (drw) begin
      dx <= dx + 1'b1; dcnt <= dcnt + 1'b1;
      if (!r1[0] || dcnt[0]) begin d0 <= d0 << 1; d1 <= d1 << 1; d2 <= d2 << 1; d3 <= d3 << 1; end
      if (dcnt == (r1[0] ? 4'd15 : 4'd7)) drw <= 0;
    end
    if (reset) begin scan <= 0; fetch <= 0; drw <= 0; sn <= 0; end
  end

  // --- VRAM ---------------------------------------------------------------------
  reg [7:0] vram[0:16383];
  wire [13:0] va = ph == 0 ? ca : ph == 1 ? bg_a : sp_a;
  always @(posedge clk) begin
    if (ph == 0 && wr_pend) vram[va] <= wbuf;
    else vq <= vram[va];
  end

  // --- pixel --------------------------------------------------------------------
  wire [3:0] bgp  = {s3[7], s2[7], s1[7], s0[7]};
  wire       spon = sbq != 0 && !(spri && bgp != 0);
  wire       bord = !act_v || !r1[6] || (r0[5] && x[7:3] == 0);
  wire [4:0] idx  = bord ? {1'b1, r7[3:0]} : spon ? {1'b1, sbq} : {spal, bgp};
  always @(posedge clk) if (ph == 1) pix_color <= cram[idx];
  assign pix_we   = ph == 3 && act_h && (line >= 238 || line < 216) && !reset;
  assign pix_addr = {line[0], x[7:0]};
endmodule
