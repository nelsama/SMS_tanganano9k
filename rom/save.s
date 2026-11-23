; save.s : cart RAM test. Byte $8000 counts the starts (shown as the border
; colour); $8001.. and page 2 hold a pattern.
.org 0
  di
  im 1
  jp start
.org $66
  retn
start:
  ld a,$08
  ld ($FFFC),a
  ld hl,$8000
  inc (hl)
  ld a,(hl)
  ld ($C000),a
  ld a,$5A
  ld ($9FFF),a
  ld a,$0C
  ld ($FFFC),a
  ld a,$A5
  ld ($BFFF),a
  ld a,16               ; CRAM 16..: colour = count
  out ($BF),a
  ld a,$C0
  out ($BF),a
  ld a,($C000)
  ld b,16
p:
  out ($BE),a
  djnz p
s:
  jr s
.org $1FF0
  .db "TMR SEGA"
