// menu.c : file browser of the flash cart (runs on the SMS Z80, SDCC)
#include "fat.h"
__sfr __at 0xBE VD;
__sfr __at 0xBF VC;
__sfr __at 0xDC PAD;
__sfr __at 0x7F PSG;
__sfr __at 0x10 SPI;
__sfr __at 0x11 SPI_ST;
__sfr __at 0x12 ADR0;
__sfr __at 0x13 ADR1;
__sfr __at 0x14 ADR2;
__sfr __at 0x15 DMA;
__sfr __at 0x16 MAPPER;
__sfr __at 0x17 MASK;
__sfr __at 0x19 CLEAN;

extern const u8 font[];
void launch(void);              // crt0.s
void write512(u8 *p);
void ram_clear(void);
u16 ram_sum(u16 s);
void read512(u8 *p);            // crt0.s: 512 bytes from the SD card
static u8 sdhc;

// --- SD card ------------------------------------------------------------------
static u8 xfer(u8 b) {
  SPI = b;
  while (SPI_ST & 0x80) ;
  return SPI;
}
static u8 speed;          // 0 slow, 2 fast
static void deselect(void) { SPI_ST = speed | 1; xfer(0xFF); }
static u8 command(u8 c, u32 arg, u8 crc) {
  u8 i, r;
  deselect();
  SPI_ST = speed;
  xfer(0xFF);
  xfer(c | 0x40);
  xfer((u8)(arg >> 24)); xfer((u8)(arg >> 16)); xfer((u8)(arg >> 8)); xfer((u8)arg);
  xfer(crc);
  for (i = 0; i < 10; ++i) {
    r = xfer(0xFF);
    if (!(r & 0x80)) break;
  }
  return r;
}
static u8 sd_init(void) {
  u8 i, r, v2;
  u16 n;
  speed = 0;
  SPI_ST = 1;
  for (i = 0; i < 12; ++i) xfer(0xFF);
  for (n = 0; n < 50; ++n) if (command(0, 0, 0x95) == 1) break;
  if (n == 50) return 0;
  v2 = 0;
  if (command(8, 0x1AA, 0x87) == 1) {
    xfer(0xFF); xfer(0xFF); xfer(0xFF);
    if (xfer(0xFF) != 0xAA) return 0;
    v2 = 1;
  }
  r = 1;
  for (n = 0; n < 2000; ++n) {
    command(55, 0, 0xFF);
    r = command(41, v2 ? 0x40000000UL : 0, 0xFF);
    if (r == 0) break;
  }
  if (r) return 0;
  sdhc = 0;
  if (v2) {
    if (command(58, 0, 0xFF)) return 0;
    if (xfer(0xFF) & 0x40) sdhc = 1;
    xfer(0xFF); xfer(0xFF); xfer(0xFF);
  }
  if (!sdhc && command(16, 512, 0xFF)) return 0;
  speed = 2;
  deselect();
  return 1;
}
static u8 start_read(u32 lba) {
  u16 n;
  u8 r;
  if (!sdhc) lba <<= 9;
  if (command(17, lba, 0xFF)) return 0;
  for (n = 0; n < 20000; ++n) {
    r = xfer(0xFF);
    if (r == 0xFE) return 1;
    if (r != 0xFF) return 0;
  }
  return 0;
}
u8 sd_dma(u32 lba, u8 die, u32 addr) {
  if (!start_read(lba)) { deselect(); return 0; }
  ADR0 = (u8)addr;
  ADR1 = (u8)(addr >> 8);
  ADR2 = (u8)(addr >> 16);
  DMA = die;
  while (SPI_ST & 0x80) ;
  xfer(0xFF); xfer(0xFF);
  deselect();
  return 1;
}
u8 sd_read(u32 lba) {
  if (!start_read(lba)) { deselect(); return 0; }
  read512(buf);                 // leaves the first CRC byte on its way
  while (SPI_ST & 0x80) ;
  xfer(0xFF);
  deselect();
  return 1;
}

u8 sd_write(u32 lba) {
  u16 n;
  u8 r;
  if (!sdhc) lba <<= 9;
  if (command(24, lba, 0xFF)) { deselect(); return 0; }
  xfer(0xFF);
  xfer(0xFE);
  write512(buf);
  while (SPI_ST & 0x80) ;
  xfer(0xFF); xfer(0xFF);
  r = xfer(0xFF) & 0x1F;
  for (n = 60000; n; --n) if (xfer(0xFF) == 0xFF) break;   // busy
  deselect();
  return n && r == 5;
}

// --- screen -------------------------------------------------------------------
static void vblank(void) { while (!(VC & 0x80)) ; }
static void reg(u8 n, u8 v) { VC = v; VC = n | 0x80; }
static void vaddr(u16 a) { VC = (u8)a; VC = (u8)(a >> 8) | 0x40; }
static void cell(u8 x, u8 y) { vaddr(0x3800 + ((u16)y << 6) + (u16)(x << 1)); }
static void put(u8 c, u8 at) { VD = c; VD = at; }
static void at(u8 x, u8 y, const char *s) {
  cell(x, y);
  while (*s) put(*s++, 0);
}
static void cls(void) {
  u16 i;
  vaddr(0x3800);
  for (i = 0; i < 896; ++i) put(' ', 0);
}
static void mark(u8 row, u8 pal) {          // highlight a line of the list
  u8 i;
  const char *s = list[row].name;
  cell(1, row + 4);
  put(list[row].isdir ? '/' : ' ', pal);
  for (i = 0; i < 29; ++i) {
    put(*s ? *s : ' ', pal);
    if (*s) ++s;
  }
}
void progress(u16 k, u16 total) {
  static u8 done;
  u8 n = (u8)(((u32)k * 24) / total);
  if (k == 0) done = 0;
  while (done < n) { cell(4 + done, 14); put(' ', 8); ++done; }
}
static const char *const msgs[] = {"", "NO SD CARD", "SD READ ERROR", "NOT FAT32", "BAD SIZE", "SD FULL", "FOLDER FULL"};

static u8 pad_now, pad_new;
static void readpad(void) {                 // U D L R 1 2
  u8 old = pad_now;
  pad_now = ~PAD & 0x3F;
  pad_new = pad_now & ~old;
}
static u32 dir_stack[6];
static u16 page_stack[6];
static u8 depth, sel;
static u32 dir;
static u16 page;

static void title(void) { at(4, 1, "TANG NANO 9K  SMS CART"); }

static void fail(void) {
  cls();
  title();
  at(4, 10, msgs[fat_err]);
  at(4, 13, "PRESS 1");
  do { vblank(); readpad(); } while (!(pad_new & 0x10));
}

static void draw(void) {
  u8 i;
  vblank();
  reg(1, 0x80);
  cls();
  title();
  if (!list_len) at(4, 10, "NO SMS FILES HERE");
  for (i = 0; i < list_len; ++i) mark(i, i == sel ? 8 : 0);
  if (page) at(2, 21, "< LEFT");
  if (list_more) at(23, 21, "RIGHT >");
  at(2, 22, "1 OPEN   2 BACK");
  reg(1, 0xC0);
}
static void move(u8 n) {
  mark(sel, 0);
  sel = n;
  mark(sel, 8);
}

// --- start of a game ------------------------------------------------------------
#define CART(a) (*(volatile u8 *)(a))
#define CART16(a) (*(volatile u16 *)(a))
static u8 header(u16 a) {
  static const char h[] = "TMR SEGA";
  u8 i;
  for (i = 0; i < 8; ++i) if (CART(a + i) != h[i]) return 0;
  return 1;
}
// what the cart RAM belongs to: kept in the last PSRAM bank (slot 2)
typedef struct { u16 magic; u32 serial, dir; char sn[8]; u16 sum; } info_t;
#define INFO ((volatile info_t *)0x8000)
#define MAGIC 0x5A53
static void info_on(void) { CART(0xFFFC) = 0; CART(0xFFFF) = 255; }
static u16 sum32(void) {
  u16 s;
  CART(0xFFFC) = 0x08;
  s = ram_sum(0);
  CART(0xFFFC) = 0x0C;
  s = ram_sum(s);
  CART(0xFFFC) = 0;
  return s;
}
void cram_read(u8 k) {
  u16 i;
  volatile u8 *p = (volatile u8 *)(0x8000 + ((u16)(k & 31) << 9));
  CART(0xFFFC) = (k & 32) ? 0x0C : 0x08;
  for (i = 0; i < 512; ++i) buf[i] = p[i];
  CART(0xFFFC) = 0;
}
// back from a game: write its cart RAM if it changed. 1 = done
static u8 save_back(void) {
  u8 i;
  char sn[8];
  u32 d, ser;
  u16 sum;
  if (!(SPI_ST & 1)) return 1;
  info_on();
  if (INFO->magic != MAGIC) { CLEAN = 0; return 1; }
  ser = INFO->serial; d = INFO->dir; sum = INFO->sum;
  for (i = 0; i < 8; ++i) sn[i] = INFO->sn[i];
  if (sum32() == sum) { CLEAN = 0; return 1; }
  at(4, 10, "SAVING...");
  if (ser != fat_serial) { fat_err = E_SD; return 0; }
  if (!fat_save(d, sn)) return 0;
  sum = sum32();
  info_on();
  INFO->sum = sum;
  CLEAN = 0;
  return 1;
}
static void load_sav(const entry_t *e) {    // cart RAM = its file, or zeros
  u8 i;
  u16 s;
  CART(0xFFFC) = 0x08; ram_clear();
  CART(0xFFFC) = 0x0C; ram_clear();
  CART(0xFFFC) = 0;
  CLEAN = 0;
  info_on();
  INFO->magic = 0;
  // without a readable file or room for the note, never write it back
  if (!fat_load_sav(dir, e->sn) || rom_size > 0x3FC000UL) return;
  s = sum32();
  info_on();
  INFO->serial = fat_serial;
  INFO->dir = dir;
  for (i = 0; i < 8; ++i) INFO->sn[i] = e->sn[i];
  INFO->sum = s;
  INFO->magic = MAGIC;
}
static void start(u32 size) {
  u16 banks = (u16)((size + 16383) >> 14), m = 1;
  u8 mode;
  while (m < banks) m <<= 1;
  // the cart is at $4000 (bank 1) and $8000 (bank 2, set to 0 here)
  CART(0xFFFF) = 0;
  if (banks >= 4 && CART16(0x7FE6) && (u16)(CART16(0x7FE6) + CART16(0x7FE8)) == 0) mode = 1;
  else if ((banks >= 2 && header(0x7FF0)) || header(0xBFF0) || header(0x9FF0)) mode = 0;
  else mode = banks <= 3 ? 3 : 2;
  MAPPER = mode;
  MASK = (u8)(m - 1);
  launch();
}

static u8 rep;
static void browse(void) {
  u8 redraw;
  entry_t *e;
  depth = 0; dir = 0; page = 0; sel = 0;
  for (;;) {
    if (!fat_list(dir, page)) return;
    page = list_page;
    if (sel >= list_len) sel = list_len ? list_len - 1 : 0;
    draw();
    redraw = 0;
    while (!redraw) {
      vblank();
      readpad();
      if (pad_now & 0x0F) {                    // auto repeat
        if (++rep >= 14) { rep = 11; pad_new |= pad_now & 0x0F; }
      } else rep = 0;
      if ((pad_new & 0x02) && list_len) {
        if (sel + 1 < list_len) move(sel + 1);
        else if (list_more) { ++page; sel = 0; redraw = 1; }
        else if (page) { page = 0; sel = 0; redraw = 1; }
        else move(0);
      } else if ((pad_new & 0x01) && list_len) {
        if (sel) move(sel - 1);
        else if (page) { --page; sel = LIST_N - 1; redraw = 1; }
        else move(list_len - 1);
      } else if ((pad_new & 0x08) && list_more) { ++page; sel = 0; redraw = 1; }
      else if ((pad_new & 0x04) && page) { --page; sel = 0; redraw = 1; }
      else if ((pad_new & 0x20) && depth) {
        --depth; dir = dir_stack[depth]; page = page_stack[depth]; sel = 0; redraw = 1;
      } else if ((pad_new & 0x10) && list_len) {
        e = &list[sel];
        redraw = 1;
        if (e->isdir) {
          if (e->name[0] == '.' && e->name[1] == '.') {
            if (depth) { --depth; dir = dir_stack[depth]; page = page_stack[depth]; }
          } else if (depth < 6) {
            dir_stack[depth] = dir; page_stack[depth] = page; ++depth;
            dir = e->cl; page = 0;
          }
          sel = 0;
        } else {
          cls();
          title();
          at(4, 10, e->name);
          at(4, 12, "LOADING");
          if (fat_load(e->cl, e->size)) { load_sav(e); start(rom_size); }
          fail();
          fat_err = 0;
        }
      }
    }
  }
}

// 1 = try again, 0 = give up
static u8 save_fail(void) {
  cls();
  title();
  at(4, 8, "GAME NOT SAVED");
  at(4, 10, msgs[fat_err]);
  at(4, 13, "1 RETRY   2 DISCARD");
  for (;;) {
    vblank();
    readpad();
    if (pad_new & 0x10) { cls(); title(); return 1; }
    if (pad_new & 0x20) { CLEAN = 0; return 0; }
  }
}

void main(void) {
  static const u8 regs[11] = {0x06, 0x80, 0xFF, 0xFF, 0xFF, 0xFF, 0xFB, 0x02, 0, 0, 0xFF};
  static const u8 psg[4] = {0x9F, 0xBF, 0xDF, 0xFF};
  u16 i;
  u8 j;
  for (j = 0; j < 4; ++j) PSG = psg[j];
  for (j = 0; j < 11; ++j) reg(j, regs[j]);
  VC = 0; VC = 0xC0;                          // palette
  for (j = 0; j < 32; ++j) VD = 0;
  VC = 0; VC = 0xC0; VD = 0x10; VD = 0x3F;
  VC = 16; VC = 0xC0; VD = 0x38; VD = 0x3F; VD = 0x10;
  vaddr(32 * 32);                             // font: tiles 32..127, plane 0
  for (i = 0; i < 768; ++i) { VD = font[i]; VD = 0; VD = 0; VD = 0; }
  vaddr(0x3F00);
  VD = 0xD0;
  cls();
  title();
  reg(1, 0xC0);
  for (;;) {
    fat_err = E_SD;
    if (sd_init() && fat_mount()) {
      if (save_back()) browse();
      else if (save_fail()) continue;
      else { CLEAN = 0; browse(); }
    } else if ((SPI_ST & 1) && save_fail()) continue;
    fail();
  }
}
