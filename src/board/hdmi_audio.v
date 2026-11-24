// hdmi_audio.v : NES sample (unsigned, clk) -> 48 kHz signed sample for hdmi_tx.
// Low pass ~13 kHz (like the console's 14 kHz filter, also limits aliasing),
// DC removal (~1 Hz) and saturation. The result only changes on audio_req.
module hdmi_audio(
  input             clk,        // 21.6 MHz
  input      [15:0] sample,
  input             audio_req,  // toggles every 1/48000 s (pixel clock domain)
  output reg [15:0] audio
);
  reg [15:0] x;
  reg [23:0] lp;                // x << 8, one-pole, k = 2^-8 per clk
  reg [28:0] dc;                // x << 13, k = 2^-13 per sample
  reg [2:0]  rq;
  initial begin x = 0; lp = 0; dc = 0; rq = 0; audio = 0; end
  wire signed [16:0] d = {1'b0, lp[23:8]} - {1'b0, dc[28:13]};
  always @(posedge clk) begin
    x  <= sample;
    lp <= lp + x - lp[23:8];
    rq <= {rq[1:0], audio_req};
    if (rq[2] != rq[1]) begin
      dc <= dc + lp[23:8] - dc[28:13];
      audio <= (d > 17'sd32767)  ? 16'h7FFF :
               (d < -17'sd32768) ? 16'h8000 : d[15:0];
    end
  end
endmodule
