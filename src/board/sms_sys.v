// sms_sys.v : Master System + flash-cart ("EverDrive" style) logic.
// clk = 21.6 MHz: dot = clk/4, CPU = clk/6 = 3.6 MHz (real 3.58),
// 228 CPU clocks per line, 60.27 frames/s (real 59.92).
//
// Memory: work RAM 8 KB and menu ROM 16 KB in BSRAM; cart ROM in PSRAM die 0
// (up to 4 MB), cart RAM (2 x 16 KB) in PSRAM die 1.
// A PSRAM read starts in T1 (2 clk into it); the word is latched 6 clk later
// and the CPU samples at the end of T2, 4 clk after that: no wait states.
//
// Menu mode (power-on or S2): $0000-$3FFF is the menu ROM, $4000-$BFFF the
// cart through the mapper (always Sega), and cart ROM is writable. Ports:
//   $10 W send SPI byte            R last byte received
//   $11 W bit 0 CS (1 = high), bit 1 fast clock     R bit 7 SPI / DMA busy,
//                                    bit 0 the game wrote the cart RAM
//   $12/13/14 W PSRAM byte address, low / mid / high
//   $15 W 0/1: copy 512 SPI bytes to that PSRAM die; the address increments
//   $16 W mapper: 0 Sega, 1 Codemasters, 2 Sega + Korean ($A000), 3 none
//   $17 W bank mask (16 KB banks - 1)    R last byte, and sends FF (for INIR)
//   $18 W leave the menu: reset and run the game     $19 W clear that bit 0
module sms_sys(
  input             clk,
  input             reset_in,
  input      [5:0]  pad1,       // active high: 0 U, 1 D, 2 L, 3 R, 4 button 1, 5 button 2
  input      [5:0]  pad2,
  input             pause,      // active high, debounced
  input             to_menu,
  output reg        menu,
  output            sd_active,
  output            sd_sck, sd_cmd, sd_cs,
  input             sd_dat0,
  // PSRAM ports: a change of t starts an access; word ready 5 clk later
  output reg        t0, t1, we0, we1,
  output reg [21:0] a0, a1,
  output reg [7:0]  d0, d1,
  input      [15:0] w0, w1,
  output     [15:0] sample,
  output            pix_we,
  output     [8:0]  pix_addr,
  output     [5:0]  pix_color,
  output            frame_t
);
`include "rom_cfg.vh"
  reg [7:0] rcnt;
  reg  launch;
  wire reset = !rcnt[7];
  initial begin rcnt = 0; menu = 1; launch = 0; end
  always @(posedge clk) begin
    if (to_menu) menu <= 1; else if (launch) menu <= 0;
    if (reset_in || to_menu || launch) rcnt <= 0;
    else if (reset) rcnt <= rcnt + 1'b1;
  end

  reg [2:0] cdiv;
  initial cdiv = 0;
  wire ce = cdiv == 5;
  always @(posedge clk) cdiv <= ce ? 3'd0 : cdiv + 1'b1;

  // --- CPU --------------------------------------------------------------------
  wire        m1_n, mrd_t1, mreq_n, iorq_n, rd_n, wr_n, irq_n;
  wire [15:0] a;
  wire [7:0]  dout;
  wire [7:0]  din;
  T80sed u_cpu(.RESET_n(!reset), .CLK_n(clk), .CLKEN(ce), .WAIT_n(1'b1), .INT_n(irq_n),
    .NMI_n(!pause), .BUSRQ_n(1'b1), .M1_n(m1_n), .MRD_T1(mrd_t1), .MREQ_n(mreq_n), .IORQ_n(iorq_n),
    .RD_n(rd_n), .WR_n(wr_n), .RFSH_n(), .HALT_n(), .BUSAK_n(), .A(a), .DI(din), .DO(dout));

  // strobes last several clk: one pulse at the start of each
  reg  wr_d, rd_d;
  wire wr_p = !wr_n && wr_d, rd_p = !rd_n && rd_d;
  always @(posedge clk) begin wr_d <= wr_n; rd_d <= rd_n; end
  wire mem_w = wr_p && !mreq_n;
  wire io_w  = wr_p && !iorq_n, io_r = rd_p && !iorq_n;
  wire [1:0] ios = a[7:6];

  // --- mapper -----------------------------------------------------------------
  reg  [7:0] b0, b1, b2, mask;
  reg  [1:0] mode;
  reg        cram_en, cram_bk;
  initial begin mode = 0; mask = 8'hFF; end
  wire [1:0] md = menu ? 2'd0 : mode;
  always @(posedge clk) begin
    if (mem_w && (md == 0 || md == 2) && &a[15:2]) case (a[1:0])
      0: {cram_en, cram_bk} <= dout[3:2];
      1: b0 <= dout;
      2: b1 <= dout;
      3: b2 <= dout;
    endcase
    if (mem_w && md == 2 && a == 16'hA000 && !cram_en) b2 <= dout;
    if (mem_w && md == 1 && a[13:0] == 0) case (a[15:14])
      0: b0 <= dout;
      1: b1 <= dout;
      2: b2 <= dout;
      default: ;
    endcase
    if (reset) begin b0 <= 0; b1 <= 1; b2 <= 2; cram_en <= 0; cram_bk <= 0; end
  end
  wire [7:0] bank = a[15] ? b2 : a[14] ? b1 : (a[13:10] == 0 && md != 1) ? 8'd0 : b0;
  wire       ram_cs  = a[15:14] == 2'b11;
  wire       mrom_cs = menu && a[15:14] == 2'b00;
  wire       cram_cs = a[15:14] == 2'b10 && cram_en;
  wire       cart_cs = !ram_cs && !mrom_cs;
  wire [21:0] ca0 = {menu ? bank : bank & mask, a[13:0]};
  wire [21:0] ca1 = {7'd0, cram_bk, a[13:0]};

  // --- PSRAM requests ---------------------------------------------------------
  wire       rq   = mrd_t1 && cdiv == 1;               // T1 of a memory read
  reg  [5:0] pdly;
  reg        psel;
  reg  [7:0] q_ps;
  reg        dma_wr, dma_die;
  reg [21:0] dma_a;
  reg  [7:0] dma_d;
  initial begin t0 = 0; t1 = 0; we0 = 0; we1 = 0; pdly = 0; end
  always @(posedge clk) begin
    pdly <= {pdly[4:0], 1'b0};
    if (!reset && rq && cart_cs) begin
      psel <= cram_cs; pdly[0] <= 1;
      if (cram_cs) begin t1 <= !t1; we1 <= 0; a1 <= ca1; end
      else         begin t0 <= !t0; we0 <= 0; a0 <= ca0; end
    end
    if (!reset && mem_w && cart_cs) begin
      if (cram_cs)   begin t1 <= !t1; we1 <= 1; a1 <= ca1; d1 <= dout; end
      else if (menu) begin t0 <= !t0; we0 <= 1; a0 <= ca0; d0 <= dout; end
    end
    if (dma_wr) begin             // the CPU waits in the menu ROM
      if (dma_die) begin t1 <= !t1; we1 <= 1; a1 <= dma_a; d1 <= dma_d; end
      else         begin t0 <= !t0; we0 <= 1; a0 <= dma_a; d0 <= dma_d; end
    end
    if (pdly[5]) q_ps <= psel ? (a1[0] ? w1[15:8] : w1[7:0]) : (a0[0] ? w0[15:8] : w0[7:0]);
  end

  // --- BSRAM ------------------------------------------------------------------
  reg [7:0] rom[0:16383], ram[0:8191];
  reg [7:0] q_rom, q_ram;
  initial $readmemh(`ROM_HEX, rom);
  always @(posedge clk) q_rom <= rom[a[13:0]];
  always @(posedge clk)
    if (mem_w && ram_cs) ram[a[12:0]] <= dout;
    else q_ram <= ram[a[12:0]];

  // --- cart registers ---------------------------------------------------------
  wire       creg = menu && a[7:4] == 4'h1;
  reg        cs, fast, spi_go, dma, dirty;
  reg  [7:0] spi_tx;
  reg  [9:0] dcnt;
  wire       spi_busy, spi_done;
  wire [7:0] spi_rx;
  assign sd_cs = cs;
  assign sd_active = dma;
  initial begin dirty = 0; cs = 1; fast = 0; spi_go = 0; dma = 0; dma_wr = 0; end
  always @(posedge clk) begin
    spi_go <= 0; launch <= 0; dma_wr <= 0;
    if (dma_wr) dma_a <= dma_a + 1'b1;
    if (mem_w && cram_cs && !menu) dirty <= 1;
    if (io_w && creg && a[3:0] == 9) dirty <= 0;
    if (reset) begin
      cs <= 1; fast <= 0; dma <= 0;
    end else begin
      if (io_w && creg) case (a[3:0])
        4'h0: begin spi_tx <= dout; spi_go <= 1; end
        4'h1: {fast, cs} <= dout[1:0];
        4'h2: dma_a[7:0] <= dout;
        4'h3: dma_a[15:8] <= dout;
        4'h4: dma_a[21:16] <= dout[5:0];
        4'h5: begin dma_die <= dout[0]; dma <= 1; dcnt <= 0; spi_tx <= 8'hFF; spi_go <= 1; end
        4'h6: mode <= dout[1:0];
        4'h7: mask <= dout;
        4'h8: launch <= 1;
        default: ;
      endcase
      if (io_r && creg && a[3:0] == 7) begin spi_tx <= 8'hFF; spi_go <= 1; end
      if (dma && spi_done) begin
        dma_wr <= 1; dma_d <= spi_rx;
        dcnt <= dcnt + 1'b1;
        if (dcnt == 511) dma <= 0;
        else spi_go <= 1;
      end
    end
  end
  sms_spi u_spi(.clk(clk), .go(spi_go), .fast(fast), .tx(spi_tx), .rx(spi_rx),
    .busy(spi_busy), .done(spi_done), .sck(sd_sck), .mosi(sd_cmd), .miso(sd_dat0));

  // --- I/O --------------------------------------------------------------------
  wire [7:0] vdp_q, vcount, hcount;
  reg  [7:0] hlatch, ioctl;
  initial ioctl = 8'hFF;
  // TH pins: input (pulled up) or the programmed level
  wire tha = ioctl[1] | ioctl[5], thb = ioctl[3] | ioctl[7];
  wire tra = ioctl[0] ? !pad1[5] : ioctl[4];
  wire trb = ioctl[2] ? !pad2[5] : ioctl[6];
  reg  tha_d, thb_d;
  always @(posedge clk) begin
    tha_d <= tha; thb_d <= thb;
    if (tha && !tha_d || thb && !thb_d) hlatch <= hcount;
    if (reset) ioctl <= 8'hFF;
    else if (io_w && ios == 0 && a[0] && !creg) ioctl <= dout;
  end
  sms_vdp u_vdp(.clk(clk), .reset(reset), .wr(io_w && ios == 2), .rd(io_r && ios == 2), .a0(a[0]),
    .din(dout), .dout(vdp_q), .vcount(vcount), .hcount(hcount), .irq_n(irq_n),
    .pix_we(pix_we), .pix_addr(pix_addr), .pix_color(pix_color), .frame_t(frame_t));
  sn76489 u_psg(.clk(clk), .reset(reset), .ce(ce), .wr(io_w && ios == 1), .din(dout), .sample(sample));

  reg [7:0] q_io;
  always @(posedge clk) if (io_r && creg)
    q_io <= a[3:0] == 1 ? {spi_busy | spi_go | dma, 6'd0, dirty} : spi_rx;
  else if (io_r) case ({ios, a[0]})
    3'b010:  q_io <= vcount;
    3'b011:  q_io <= hlatch;
    3'b110:  q_io <= {!pad2[1], !pad2[0], tra, !pad1[4], !pad1[3], !pad1[2], !pad1[1], !pad1[0]};
    3'b111:  q_io <= {thb, tha, 2'b11, trb, !pad2[4], !pad2[3], !pad2[2]};
    default: q_io <= 8'hFF;
  endcase
  // interrupt acknowledge (M1 + IORQ) reads FF
  assign din = !iorq_n ? (!m1_n ? 8'hFF : ios == 2 ? vdp_q : q_io)
             : ram_cs ? q_ram : mrom_cs ? q_rom : q_ps;
endmodule

// SPI mode 0 byte: slow = clk/64 (337 kHz), fast = clk/4 (5.4 MHz)
module sms_spi(
  input            clk, go, fast,
  input      [7:0] tx,
  output     [7:0] rx,
  output reg       busy, done, sck,
  output           mosi,
  input            miso
);
  reg [7:0] sr;
  reg [5:0] div;
  reg [2:0] n;
  initial begin busy = 0; done = 0; sck = 0; sr = 8'hFF; end
  assign mosi = busy ? sr[7] : 1'b1;
  assign rx = sr;
  reg bitin;
  wire tick = fast ? div[0] : (div[4:0] == 31);
  always @(posedge clk) begin
    done <= 0;
    if (!busy) begin
      sck <= 0; div <= 0; n <= 0;
      if (go) begin busy <= 1; sr <= tx; end
    end else begin
      div <= tick ? 6'd0 : div + 1'b1;
      if (tick) begin
        sck <= !sck;
        if (!sck) bitin <= miso;             // rising edge
        else begin                           // falling edge
          sr <= {sr[6:0], bitin};
          n <= n + 1'b1;
          if (n == 7) begin busy <= 0; done <= 1; end
        end
      end
    end
  end
endmodule
