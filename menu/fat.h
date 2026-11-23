#ifndef FAT_H
#define FAT_H
#ifdef HOST
#include <stdint.h>
typedef uint8_t u8; typedef uint16_t u16; typedef uint32_t u32;
#else
typedef unsigned char u8; typedef unsigned int u16; typedef unsigned long u32;
#endif
#define LIST_N 16
#define NAME_N 28
enum { E_OK, E_SD, E_READ, E_FAT, E_SIZE };
typedef struct { u32 cl, size; u8 isdir; char name[NAME_N]; } entry_t;
#ifdef HOST
extern u8 buf[512];
extern entry_t list[LIST_N];
#else               // work RAM: $C000 sector, $C200 pages, $D010 list; variables from $D280
#define buf ((u8 *)0xC000)
#define list ((entry_t *)0xD010)
#endif
extern u16 list_page;
extern u8 fat_err, list_len, list_more;
extern u32 rom_size;                  // without the 512 byte header
u8 fat_mount(void);
u8 fat_list(u32 dir, u16 page);       // dir 0 = root; list_page = page shown
u8 fat_load(u32 cl, u32 size);
// provided by the platform
u8 sd_read(u32 lba);                  // sector -> buf
u8 sd_dma(u32 lba, u8 die, u32 addr); // sector -> PSRAM
void progress(u16 k, u16 total);
#endif
