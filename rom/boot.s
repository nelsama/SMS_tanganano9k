; boot.s : phase 2 test, runs in menu mode. Tests the PSRAM and the mapper, then
; copies test.sms to the PSRAM and launches it (button 1, or by itself after 4 s).
VD = $BE
VC = $BF
font_off = $67C       ; font inside test.sms
.org 0
  di
  im 1
  ld sp,$DFF0
  jp start
.org $66
  retn
start:
  ld hl,silence
  ld bc,$0400 | $7F
  otir
  ld hl,regs
  ld bc,$1600 | VC
  otir
  ld hl,$4000
  call setad
  ld bc,$4000
clr:
  xor a
  out (VD),a
  dec bc
  ld a,b
  or c
  jr nz,clr
  ld hl,$C000
  call setad
  ld a,$10
  out (VD),a
  ld a,$3F
  out (VD),a
  ld hl,$4400
  call setad
  ld hl,test + font_off
  ld de,512
fl:
  ld a,(hl)
  out (VD),a
  xor a
  out (VD),a
  nop
  out (VD),a
  nop
  out (VD),a
  inc hl
  dec de
  ld a,d
  or e
  jr nz,fl
  ld hl,$7F00
  call setad
  ld a,$D0
  out (VD),a
  ld a,$C0
  out (VC),a
  ld a,$81
  out (VC),a
  ld hl,$3800 + 2*(64/2*1+5)
  ld de,ttitle
  call print

; 1 bytes, odd and even, in bank 1 ($4000): walking pattern, 16 KB
  ld hl,$4000
p1a:
  ld a,l
  xor h
  ld (hl),a
  inc hl
  bit 7,h
  jr z,p1a
  ld hl,$4000
p1b:
  ld a,l
  xor h
  cp (hl)
  jr nz,p1f
  inc hl
  bit 7,h
  jr z,p1b
  xor a
p1f:
  ld de,tn1
  ld c,0
  call result

; 2 all 256 banks (4 MB): one signature per bank, in slot 2
  ld b,0
p2a:
  ld a,b
  ld ($FFFF),a
  ld ($9234),a
  cpl
  ld ($9235),a
  inc b
  jr nz,p2a
p2b:
  ld a,b
  ld ($FFFF),a
  ld a,($9234)
  cp b
  jr nz,p2f
  cpl
  ld hl,$9235
  cp (hl)
  jr nz,p2f
  inc b
  jr nz,p2b
p2f:
  ld de,tn2
  ld c,1
  call result

; 3 the three slots see the same bank
  ld a,7
  ld ($FFFE),a
  ld ($FFFF),a
  ld a,$5A
  ld ($9001),a
  ld a,($5001)
  cp $5A
  jr nz,p3f
  ld a,8
  ld ($FFFE),a
  ld a,$A5
  ld ($5001),a
  ld a,($9001)
  cp $5A
p3f:
  ld de,tn3
  ld c,2
  call result

; 4 cart RAM: two pages, apart from the ROM
  ld a,9
  ld ($FFFF),a
  ld a,$11
  ld ($8000),a
  ld a,$08
  ld ($FFFC),a
  ld a,$22
  ld ($8000),a
  ld a,$0C
  ld ($FFFC),a
  ld a,$33
  ld ($8000),a
  ld a,$08
  ld ($FFFC),a
  ld a,($8000)
  cp $22
  jr nz,p4f
  ld a,$0C
  ld ($FFFC),a
  ld a,($8000)
  cp $33
  jr nz,p4f
  xor a
  ld ($FFFC),a
  ld a,($8000)
  cp $11
p4f:
  ld de,tn4
  ld c,3
  call result

; 5 back-to-back 16 bit accesses and stack in cart RAM
  ld a,$08
  ld ($FFFC),a
  ld sp,$BFF0
  ld hl,$1234
  push hl
  ld hl,$5678
  push hl
  call p5s
  pop hl
  pop de
  ld sp,$DFF0
  ld a,h
  cp $56
  jr nz,p5f
  ld a,l
  cp $78
  jr nz,p5f
  ld a,d
  cp $12
  jr nz,p5f
  ld a,e
  cp $34
p5f:
  ld de,tn5
  ld c,4
  call result
  xor a
  ld ($FFFC),a

; 6 LDIR through the PSRAM, and code in it
  ld a,3
  ld ($FFFE),a
  ld hl,code
  ld de,$4100
  ld bc,codee - code
  ldir
  ld hl,$4100
  ld de,$4900
  ld bc,codee - code
  ldir
  ld hl,0
  call $4900
  ld a,h
  cp $2B
  jr nz,p6f
  ld a,l
  cp $18                ; 11032 = $2B18
p6f:
  ld de,tn6
  ld c,5
  call result

; copy test.sms to bank 0, through slot 2
  xor a
  ld ($FFFF),a
  ld hl,test
  ld de,$8000
  ld bc,8192
  ldir
  ld hl,test
  ld de,$8000
  ld bc,8192
cmp:
  ld a,(de)
  cp (hl)
  jr nz,cpf
  inc hl
  inc de
  dec bc
  ld a,b
  or c
  jr nz,cmp
cpf:
  ld de,tn7
  ld c,6
  call result
  ld hl,$3800 + 64*14 + 10
  ld de,tgo
  call print
  ld b,240
w1:
  in a,($DC)
  bit 4,a
  jr z,go
  in a,(VC)
  add a,a
  jr nc,w1
  djnz w1
go:
  ld a,0
  out ($16),a           ; Sega mapper
  out ($17),a           ; 16 KB
  out ($18),a
  jr $

p5s:
  push af
  pop af
  ret
code:                   ; hl += sum of 1..n, checks branches and (hl) timing
  ld b,0
c1:
  ld de,43
  add hl,de
  djnz c1
  ld de,24
  add hl,de             ; 256 * 43 + 24 = 11032
  ret
codee:

setad:
  ld a,l
  out (VC),a
  ld a,h
  out (VC),a
  ret
print:
  set 6,h
  call setad
pr1:
  ld a,(de)
  or a
  ret z
  out (VD),a
  inc de
  xor a
  out (VD),a
  jr pr1
result:                 ; Z = passed; name de, row 4 + c
  push af
  ld a,c
  add a,4
  ld l,a
  ld h,0
  ld b,6
rs1:
  add hl,hl
  djnz rs1
  ld bc,$3800 + 8
  add hl,bc
  call print
  ld de,tok
  pop af
  jr z,pr1
  ld de,tbad
  jr pr1
silence: .db $9F,$BF,$DF,$FF
regs: .db $06,$80,$80,$81,$FF,$82,$FF,$83,$FF,$84,$FF,$85,$FB,$86,$00,$87,$00,$88,$00,$89,$FF,$8A
ttitle: .db "PSRAM AND MAPPER TEST",0
tn1: .db "PSRAM BYTES    ",0
tn2: .db "256 BANKS      ",0
tn3: .db "SLOTS          ",0
tn4: .db "CART RAM       ",0
tn5: .db "STACK IN RAM   ",0
tn6: .db "CODE IN PSRAM  ",0
tn7: .db "GAME COPY      ",0
tok:  .db "OK",0
tbad: .db "FAIL",0
tgo:  .db "BUTTON 1: RUN FROM PSRAM",0
.org $2000
test:
  .incbin "test.sms"
