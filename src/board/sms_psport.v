// sms_psport.v
// one PSRAM die: a change of t starts an access (clk side registers, stable)
module sms_psport(
  input         memclk, memclk_p, resetn, t, we,
  input  [21:0] addr,
  input  [7:0]  din,
  output [15:0] dout,
  output        ck, cs_n,
  inout         rwds,
  inout  [7:0]  dq
);
  reg ts, td, rd, wr;
  initial begin ts = 0; td = 0; rd = 0; wr = 0; end
  always @(posedge memclk) begin
    ts <= t;
    td <= ts;
    rd <= (ts != td) && !we;
    wr <= (ts != td) && we;
  end
  wire busy;
  psram_chan u_ch(.clk(memclk), .clk_p(memclk_p), .resetn(resetn), .read(rd), .write(wr),
    .addr(addr), .din({din, din}), .byte_write(1'b1), .dout(dout), .busy(busy),
    .psram_ck(ck), .psram_cs_n(cs_n), .psram_rwds(rwds), .psram_dq(dq));
endmodule

