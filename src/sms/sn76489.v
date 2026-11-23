// sn76489.v : Sega PSG. ce = CPU clock enable (3.58 MHz); wr = one-clk pulse.
module sn76489(
  input             clk, reset, ce, wr,
  input      [7:0]  din,
  output reg [15:0] sample      // unsigned
);
  reg [9:0]  per0, per1, per2, cnt0, cnt1, cnt2;
  reg [3:0]  vol0, vol1, vol2, vol3;
  reg        t0, t1, t2;        // tone outputs
  reg [2:0]  nctl, lch;
  reg [6:0]  ncnt;
  reg        nclk, nclk_d;
  reg [15:0] lfsr;
  reg [3:0]  div;
  initial begin
    per0 = 0; per1 = 0; per2 = 0; cnt0 = 0; cnt1 = 0; cnt2 = 0;
    vol0 = 15; vol1 = 15; vol2 = 15; vol3 = 15; t0 = 0; t1 = 0; t2 = 0;
    nctl = 0; lch = 0; ncnt = 0; nclk = 0; nclk_d = 0; lfsr = 16'h8000; div = 0;
  end
  // 2 dB steps, full = 8191
  function [12:0] lev(input on, input [3:0] v);
    case (on ? v : 4'd15)
      0: lev = 8191;  1: lev = 6506;  2: lev = 5168;  3: lev = 4105;
      4: lev = 3261;  5: lev = 2590;  6: lev = 2057;  7: lev = 1634;
      8: lev = 1298;  9: lev = 1031; 10: lev = 819;  11: lev = 650;
      12: lev = 517; 13: lev = 410;  14: lev = 326; default: lev = 0;
    endcase
  endfunction
  wire [2:0] sel = din[7] ? din[6:4] : lch;
  wire tick = ce && div == 15;
  always @(posedge clk) begin
    if (ce) div <= div + 1'b1;
    if (tick) begin
      // period 0 / 1 = constant high (used to play samples)
      if (per0 <= 1) begin t0 <= 1; cnt0 <= 0; end
      else if (cnt0 <= 1) begin cnt0 <= per0; t0 <= !t0; end else cnt0 <= cnt0 - 1'b1;
      if (per1 <= 1) begin t1 <= 1; cnt1 <= 0; end
      else if (cnt1 <= 1) begin cnt1 <= per1; t1 <= !t1; end else cnt1 <= cnt1 - 1'b1;
      if (per2 <= 1) begin t2 <= 1; cnt2 <= 0; end
      else if (cnt2 <= 1) begin cnt2 <= per2; t2 <= !t2; end else cnt2 <= cnt2 - 1'b1;
      if (nctl[1:0] == 3) nclk <= t2;
      else if (ncnt == 0) begin
        ncnt <= nctl[1:0] == 0 ? 7'd15 : nctl[1:0] == 1 ? 7'd31 : 7'd63;
        nclk <= !nclk;
      end else ncnt <= ncnt - 1'b1;
      nclk_d <= nclk;
      if (nclk && !nclk_d) lfsr <= {nctl[2] ? lfsr[0] ^ lfsr[3] : lfsr[0], lfsr[15:1]};
    end
    if (wr) begin
      if (din[7]) lch <= din[6:4];
      case (sel)
        0: if (din[7]) per0[3:0] <= din[3:0]; else per0[9:4] <= din[5:0];
        2: if (din[7]) per1[3:0] <= din[3:0]; else per1[9:4] <= din[5:0];
        4: if (din[7]) per2[3:0] <= din[3:0]; else per2[9:4] <= din[5:0];
        6: begin nctl <= din[2:0]; lfsr <= 16'h8000; end
        1: vol0 <= din[3:0];
        3: vol1 <= din[3:0];
        5: vol2 <= din[3:0];
        7: vol3 <= din[3:0];
      endcase
    end
    if (reset) begin
      vol0 <= 15; vol1 <= 15; vol2 <= 15; vol3 <= 15;
      per0 <= 0; per1 <= 0; per2 <= 0; nctl <= 0; lch <= 0;
    end
  end
  wire [14:0] sum = {2'b0, lev(t0, vol0)} + {2'b0, lev(t1, vol1)}
                  + {2'b0, lev(t2, vol2)} + {2'b0, lev(lfsr[0], vol3)};
  always @(posedge clk) sample <= {sum, 1'b0};
endmodule
