// sim_sys frames outdir [pad@from-to ...] : runs the sms_sys netlist
// (netlist.h), writes every frame as PPM (last 3 only) and checks the raster.
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>
#include "netlist.h"
// PSRAM: the access starts when t changes; the word shows up 5 clk later
static uint8_t ps[2][1 << 22];
struct Die { unsigned t = 0; int wait = 0; unsigned a = 0, q = 0xDEAD; long lost = 0; } die[2];
static void psram(int k, unsigned t, unsigned we, unsigned a, unsigned d) {
  Die &x = die[k];
  if (x.wait && !--x.wait) x.q = ps[k][a & ~1u] | ps[k][a | 1] << 8;
  if (t != x.t) {
    if (x.wait) x.lost++;
    x.t = t;
    if (we) ps[k][a] = d; else { x.q = 0xDEAD; x.wait = 5; }
  }
}
// SD card (SPI mode 0, SDHC) on the image file $SDIMG
struct Sd {
  FILE *f = nullptr; unsigned sck = 0, in = 0, out = 0xFF; int n = 0;
  std::vector<uint8_t> cmd, q; size_t qi = 0; bool idle = true, app = false; long reads = 0;
  int wst = 0; unsigned wa = 0, wn = 0; uint8_t wb[514]; long writes = 0;
  void byte(unsigned b) {
    if (wst == 1) { if (b == 0xFE) { wst = 2; wn = 0; } return; }
    if (wst == 2) {
      wb[wn++] = b;
      if (wn == 514) {
        fseek(f, (long)wa * 512, SEEK_SET); fwrite(wb, 1, 512, f); fflush(f); writes++; wst = 0;
        q.clear(); qi = 0; for (int x : {0xE5, 0, 0, 0, 0xFF}) q.push_back(x);
      }
      return;
    }
    if (cmd.empty() && (b & 0xC0) != 0x40) return;
    cmd.push_back(b);
    if (cmd.size() < 6) return;
    unsigned c = cmd[0] & 63, a = cmd[1] << 24 | cmd[2] << 16 | cmd[3] << 8 | cmd[4];
    cmd.clear(); q.clear(); qi = 0; q.push_back(0xFF);
    bool ap = app; app = false;
    if (c == 0) { idle = true; q.push_back(1); }
    else if (c == 8) { for (int x : {1, 0, 0, 1, 0xAA}) q.push_back(x); }
    else if (c == 55) { app = true; q.push_back(idle); }
    else if (c == 41 && ap) { idle = false; q.push_back(0); }
    else if (c == 58) { for (int x : {0, 0xC0, 0xFF, 0x80, 0}) q.push_back(x); }
    else if (c == 17) {
      uint8_t t[512] = {0}; fseek(f, (long)a * 512, SEEK_SET); (void)!fread(t, 1, 512, f); reads++;
      for (int x : {0, 0xFF, 0xFF, 0xFE}) q.push_back(x);
      q.insert(q.end(), t, t + 512); q.push_back(0x12); q.push_back(0x34);
    } else if (c == 24) { q.push_back(0); wst = 1; wa = a; }
    else q.push_back(4);
  }
  unsigned step(unsigned cs, unsigned ck, unsigned mosi) {
    if (cs || !f) { n = 0; out = 0xFF; cmd.clear(); q.clear(); qi = 0; wst = 0; sck = ck; return 1; }
    if (ck && !sck) { in = in << 1 | mosi; n++; }
    if (!ck && sck) {
      if (n == 8) { n = 0; byte(in & 255); out = qi < q.size() ? q[qi++] : 0xFF; }
      else out = out << 1 | 1;
    }
    sck = ck;
    return out >> 7 & 1;
  }
} sd;
int main(int argc, char **argv) {
  int frames = atoi(argv[1]);
  std::string out = argv[2];
  struct P { unsigned pad; int a, b; };
  std::vector<P> ev;
  for (int i = 3; i < argc; i++) { P p; if (sscanf(argv[i], "%x@%d-%d", &p.pad, &p.a, &p.b) == 3) ev.push_back(p); }
  if (getenv("SDIMG")) sd.f = fopen(getenv("SDIMG"), "rb+");
  sim_init();
  static uint8_t img[240][256];
  set_reset_in(1); set_pause(0); set_to_menu(0); set_sd_dat0(1); set_pad1(0); set_pad2(0);
  long t = 0, last = -1, px = 0, badlen = 0;
  for (int i = 0; i < 64; i++) { eval(); tick(); t++; }
  set_reset_in(0);
  unsigned ft = get_frame_t(); int f = 0, line = -1; unsigned prevx = 999;
  setvbuf(stdout, nullptr, _IONBF, 0);
  unsigned smin = 65535, smax = 0;
  while (f < frames) {
    unsigned pad = 0;
    for (auto &e : ev) if (f >= e.a && f <= e.b) pad |= e.pad;
    set_pad1(pad & 63); set_pause(pad >> 8 & 1); set_to_menu((pad >> 9 & 1) && t - last < 1000);
    eval();
    psram(0, get_t0(), get_we0(), get_a0(), get_d0()); psram(1, get_t1(), get_we1(), get_a1(), get_d1());
    set_w0(die[0].q); set_w1(die[1].q); set_sd_dat0(sd.step(get_sd_cs(), get_sd_sck(), get_sd_cmd())); eval();
    unsigned s = get_sample(); if (s < smin) smin = s; if (s > smax) smax = s;
    if (get_frame_t() != ft) {
      ft = !ft;
      if (f > 0) {
        if (t - last != 1368L * 262) { badlen++; printf("frame %d: %ld clk\n", f, t - last); }
        if (px != 61440) printf("frame %d: %ld pixels\n", f, px);
      }
      if (f >= frames - 3) printf("frame %d sample %u..%u\n", f, smin, smax);
      if (f >= frames - 3) {
        char n[300]; snprintf(n, 300, "%s/f%03d.ppm", out.c_str(), f);
        FILE *o = fopen(n, "wb"); fprintf(o, "P6 256 240 255\n");
        for (auto &r : img) for (uint8_t c : r) { uint8_t b[3] = {(uint8_t)((c & 3) * 85), (uint8_t)((c >> 2 & 3) * 85), (uint8_t)((c >> 4) * 85)}; fwrite(b, 1, 3, o); }
        fclose(o);
      }
      if (f % 20 == 0) printf("frame %d, SD %ld r %ld w\n", f, sd.reads, sd.writes);
      f++; last = t; px = 0; line = -1; prevx = 999; smin = 65535; smax = 0;
    }
    if (get_pix_we()) {
      unsigned a = get_pix_addr(), x = a & 255;
      if (x == 0) line++;
      if (line >= 0 && line < 240) img[line][x] = get_pix_color();
      px++; prevx = x;
    }
    tick(); t++;
  }
  printf("PSRAM overlaps: %ld %ld\n", die[0].lost, die[1].lost);
  printf("SD sectors: %ld read, %ld written\n", sd.reads, sd.writes);
  printf("bad frame lengths: %ld\n", badlen);
}
