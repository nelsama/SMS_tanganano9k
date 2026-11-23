;; startup of the menu (16 KB at $0000, no interrupts)
  .module crt0
  .globl _main
  .area _HEADER (ABS)
  .org 0
  di
  im 1
  ld sp,#0xDFF0
  jp init
  .org 0x66
  retn
  .area _CODE
init:
  ld hl,#0xC000          ; clear the variables
  ld de,#0xC001
  ld bc,#0x1FEF
  ld (hl),#0
  ldir
  call _main
hang:
  jr hang
;; void read512(u8 *p) (hl): port $17 reads a byte and sends the next FF
_read512::
  in a,(0x17)
  ld bc,#0x0017
  ex (sp),hl             ; the first byte takes 2 us
  ex (sp),hl
  inir
  inir
  ret
;; void launch(void): clear VRAM, CRAM and RAM and start the game
_launch::
  ld a,#0x80
  out (0xBF),a
  ld a,#0x81
  out (0xBF),a
  xor a
  out (0xBF),a
  ld a,#0x40
  out (0xBF),a
  ld hl,#0x4000
1$:
  xor a
  out (0xBE),a
  dec hl
  ld a,h
  or l
  jr nz,1$
  out (0xBF),a
  ld a,#0xC0
  out (0xBF),a
  ld b,#32
2$:
  xor a
  out (0xBE),a
  djnz 2$
  ld hl,#0xC000
  ld de,#0xC001
  ld bc,#0x1FFB
  ld (hl),#0
  ldir
  out (0x18),a
  jr hang
  .area _HOME
  .area _INITIALIZER
  .area _DATA
  .area _BSS
