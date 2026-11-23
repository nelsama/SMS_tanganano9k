// fat.c : read-only FAT32 + .sms loader of the menu. Also built with gcc for
// the host test (HOST).
#include "fat.h"

#ifdef HOST
u8 buf[512];
entry_t list[LIST_N];
#endif
u8 fat_err;
static u32 buf_lba;
// where each page of the current directory starts
typedef struct { u32 cl; u8 sec, off; } page_t;
#define PAGES 600
#ifdef HOST
static page_t pages[PAGES];
#else
#define pages ((page_t *)0xC200)
#endif
static u32 pg_dir;
static u16 pg_known;
u16 list_page;
static u32 fat_lba, data_lba, root_cl, part_lba;
static u8 spc;

#ifdef HOST
static u16 rd16(u16 o) { return buf[o] | (buf[o + 1] << 8); }
static u32 rd32(u16 o) { return rd16(o) | ((u32)rd16(o + 2) << 16); }
#else
#define rd16(o) (*(u16 *)(buf + (o)))
#define rd32(o) (*(u32 *)(buf + (o)))
#endif

static u8 sector(u32 lba) {
  if (buf_lba == lba) return 1;
  buf_lba = 0xFFFFFFFFUL;
  if (!sd_read(lba)) { fat_err = E_READ; return 0; }
  buf_lba = lba;
  return 1;
}

static u8 is_fat32(void) {
  return buf[510] == 0x55 && buf[511] == 0xAA && rd16(11) == 512 &&
         rd16(17) == 0 && rd16(22) == 0 && rd32(36) != 0 && buf[13] != 0;
}

u8 fat_mount(void) {
  buf_lba = 0xFFFFFFFFUL;
  pg_known = 0;
  fat_err = E_FAT;
  part_lba = 0;
  if (!sector(0)) return 0;
  if (!is_fat32()) {
    part_lba = rd32(454);            // first MBR partition
    if (part_lba == 0 || !sector(part_lba)) return 0;
    if (!is_fat32()) return 0;
  }
  spc = buf[13];
  fat_lba = part_lba + rd16(14);
  data_lba = fat_lba + rd32(36) * buf[16];
  root_cl = rd32(44);
  fat_err = 0;
  return 1;
}

static u32 next_cluster(u32 cl) {
  if (!sector(fat_lba + (cl >> 7))) return 0;
  cl = rd32(((u16)cl & 127) << 2) & 0x0FFFFFFFUL;
  if (cl < 2 || cl >= 0x0FFFFFF7UL) return 0;
  return cl;
}

// --- sequential reader ------------------------------------------------------
static u32 cur_cl, cur_lba;
static u8 cur_sec;
static void seek0(u32 cl) {
  cur_cl = cl ? cl : root_cl;
  cur_sec = 0;
  cur_lba = data_lba + (cur_cl - 2) * spc;
}
static u8 advance(void) {
  if (++cur_sec == spc) {
    cur_cl = next_cluster(cur_cl);
    if (!cur_cl) return 0;
    seek0(cur_cl);
  } else ++cur_lba;
  return 1;
}

// --- directory ----------------------------------------------------------------
u8 list_len, list_more;
static char lfn[NAME_N];
static u8 lfn_ok;
static const u8 lfn_pos[13] = {1, 3, 5, 7, 9, 14, 16, 18, 20, 22, 24, 28, 30};


// shows page `page` (or the last one if there are fewer)
u8 fat_list(u32 dir, u16 page) {
  u16 o, pg;
  u8 i, j, n, c, attr, isdir, *p;
  entry_t *e;
  page_t *q;
  if (page >= PAGES - 1) page = PAGES - 2;
  if (!pg_known || pg_dir != dir) {
    seek0(dir);
    pg_dir = dir;
    pg_known = 1;
    pages[0].cl = cur_cl; pages[0].sec = 0; pages[0].off = 0;
  }
restart:
  list_len = 0;
  list_more = 0;
  lfn_ok = 0;
  pg = page < pg_known ? page : pg_known - 1;
  q = &pages[pg];
  seek0(q->cl);
  cur_sec = q->sec;
  cur_lba += cur_sec;
  o = (u16)q->off << 5;
  n = 0;                                     // entries found in page pg
  for (;;) {
    if (!sector(cur_lba)) return 0;
    for (; o < 512; o += 32) {
      p = buf + o;
      if (p[0] == 0) goto end;
      if (p[0] == 0xE5) { lfn_ok = 0; continue; }
      attr = p[11];
      if ((attr & 0x3F) == 0x0F) {
        if (pg != page) continue;            // only skipping
        if (p[0] & 0x40) {
          for (i = 0; i < NAME_N; ++i) lfn[i] = 0;
          lfn_ok = 1;
        }
        j = ((p[0] & 0x1F) - 1) * 13;
        for (i = 0; i < 13; ++i, ++j) {
          if (j >= NAME_N - 1) break;
          c = p[lfn_pos[i]];
          if (p[lfn_pos[i] + 1]) c = (c == 0xFF) ? 0 : '?';
          lfn[j] = (c < 128) ? c : '?';
        }
        continue;
      }
      isdir = (attr & 0x10) != 0;
      // hidden, system, volume label, "." (".." is kept)
      if ((attr & 0x0E) || (p[0] == '.' && p[1] != '.') ||
          (!isdir && (p[8] != 'S' || p[9] != 'M' || p[10] != 'S'))) { lfn_ok = 0; continue; }
      if (n == LIST_N) {                     // first entry of the next page
        if (pg == page) { list_more = 1; list_page = pg; return 1; }
        ++pg;
        n = 0;
        if (pg == page) goto restart;        // go back for its long name
      }
      ++n;
      if (n == LIST_N && pg + 1 == pg_known) {
        q = &pages[pg_known];
        ++pg_known;
        q->cl = cur_cl; q->sec = cur_sec; q->off = (u8)(o >> 5) + 1;
      }
      if (pg != page) continue;
      e = &list[list_len];
      ++list_len;
      e->isdir = isdir;
      e->cl = ((u32)rd16(o + 20) << 16) | rd16(o + 26);
      e->size = ((u32)rd16(o + 30) << 16) | rd16(o + 28);
      if (lfn_ok) {
        for (i = 0; i < NAME_N; ++i) e->name[i] = lfn[i];
      } else {
        j = 0;
        for (i = 0; i < 11; ++i) {
          c = p[i];
          if (i == 8 && c != ' ') e->name[j++] = '.';
          if (c != ' ') e->name[j++] = c < 128 ? c : '?';
        }
        while (j < NAME_N) e->name[j++] = 0;
      }
      lfn_ok = 0;
    }
    if (!advance()) { if (fat_err) return 0; break; }
    o = 0;
  }
end:
  if (pg != page || (n == 0 && pg)) {        // past the end: show the last page
    page = n ? pg : pg - 1;
    goto restart;
  }
  list_page = pg;
  return 1;
}

#ifdef HOST
void pg_test(void) { pg_known = 0; }         // forget the page table
#endif

// --- loader -----------------------------------------------------------------
u32 rom_size;

// loads the file to PSRAM die 0; returns 1 when the game can be started
u8 fat_load(u32 cl, u32 size) {
  u16 k, total;
  u32 addr = 0;
  u8 skip = ((u16)size & 0x3FF) == 512;        // copier header
  fat_err = E_SIZE;
  rom_size = skip ? size - 512 : size;
  if (!cl || rom_size < 1024 || rom_size > 0x400000UL) return 0;
  fat_err = 0;
  seek0(cl);
  total = (u16)((rom_size + 511) >> 9);
  if (skip && !advance()) goto eof;
  for (k = 0; ; ) {
    if (!sd_dma(cur_lba, 0, addr)) { fat_err = E_READ; return 0; }
    addr += 512;
    if (!(k & 15)) progress(k, total);
    if (++k == total) return 1;
    if (!advance()) goto eof;
  }
eof:
  if (!fat_err) fat_err = E_SIZE;
  return 0;
}
