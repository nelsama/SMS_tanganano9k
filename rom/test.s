; test.s : Master System hardware test (phase 1). 8 KB, no mapper.
; Self tests, then a demo: line interrupt split scroll, priority, sprites.
; Pad moves the ball; button 1 = tone, button 2 = noise; Pause = border colour.
VD = $BE
VC = $BF
PSG = $7F
frames = $C000          ; frame interrupts
lines  = $C001          ; line interrupts of this frame
lastl  = $C002          ; line interrupts of the last frame
demo   = $C003
scroll = $C004
border = $C005
bx     = $C006
by     = $C007

.org 0
  di
  im 1
  ld sp,$DFF0
  jp start
.org $38
  push af
  in a,(VC)
  add a,a               ; bit 7: frame
  jr c,irqf
  ld a,(lines)
  inc a
  ld (lines),a
  ld a,(demo)
  or a
  jr z,irqx
  ld a,(scroll)         ; below the split
  out (VC),a
  ld a,$88
  out (VC),a
irqx:
  pop af
  ei
  reti
.org $66
  push af
  ld a,(border)
  inc a
  and 15
  ld (border),a
  pop af
  retn
irqf:
  ld a,(frames)
  inc a
  ld (frames),a
  ld a,(lines)
  ld (lastl),a
  xor a
  ld (lines),a
  out (VC),a            ; top: no scroll
  ld a,$88
  out (VC),a
  jr irqx

start:
  ; silence
  ld hl,silence
  ld bc,$0400 | PSG
  otir
  ; VDP registers
  ld hl,regs
  ld bc,$1600 | VC
  otir
  ; clear VRAM
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
  ; palette
  ld hl,$C000
  call setad
  ld hl,pal
  ld bc,$2000 | VD
  otir
  ; font -> tiles 32.. (plane 0)
  ld hl,$4400
  call setad
  ld hl,font
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
  ; graphics -> tiles 128.. (4 planes)
  ld hl,$5000
  call setad
  ld hl,gfx
  ld b,0
  ld c,VD
gl:
  outi
  jr nz,gl
  ; no sprites
  ld hl,$7F00
  call setad
  ld a,$D0
  out (VD),a
  ; RAM
  xor a
  ld (demo),a
  ld (frames),a
  ld (lines),a
  ld (border),a
  ld a,120
  ld (bx),a
  ld a,100
  ld (by),a

  ld hl,$3800 + 2*(32*0+5)
  ld de,ttitle
  call print
  ; display on (tests need the sprites), interrupts off
  ld a,$C0
  ld b,$81
  call reg

; 1 RAM
  ld hl,$C100
  ld bc,$1E00
t1a:
  ld a,l
  xor h
  ld (hl),a
  inc hl
  dec bc
  ld a,b
  or c
  jr nz,t1a
  ld hl,$E100           ; through the mirror
  ld bc,$1E00
t1b:
  ld a,l
  xor h
  xor $20
  cp (hl)
  jr nz,t1f
  inc hl
  dec bc
  ld a,b
  or c
  jr nz,t1b
t1f:
  ld de,tn1
  ld c,0
  call result

; 2 VRAM: write 2 KB at $1800, read back
  ld hl,$5800
  call setad
  ld hl,0
t2a:
  ld a,l
  add a,h
  out (VD),a
  inc hl
  ld a,h
  cp 8
  jr nz,t2a
  ld hl,$1800
  call setad
  ld hl,0
t2b:
  in a,(VD)
  sub l
  sub h
  jr nz,t2f
  inc hl
  ld a,h
  cp 8
  jr nz,t2b
  xor a
t2f:
  ld de,tn2
  ld c,1
  call result

; 3 V counter: DA is followed by D5
t3a:
  in a,($7E)
  cp $DA
  jr nz,t3a
t3b:
  in a,($7E)
  cp $DA
  jr z,t3b
  cp $D5
  ld de,tn3
  ld c,2
  call result

; 4 CPU clocks per frame: 59736 = (27 * 2212) + ...
  call waitvb
  ld hl,0
t4a:
  inc hl                ; 6
  in a,(VC)             ; 11
  add a,a               ; 4
  jr nc,t4a             ; 12 = 33
  ; 59736 / 33 = 1810
  ld ($C010),hl
  ld de,1808
  or a
  sbc hl,de
  ld a,h
  or a
  jr nz,t4f
  ld a,l
  cp 4                  ; 1808..1811
  jr nc,t4f
  xor a
t4f:
  ld de,tn4
  ld c,3
  call result

  ; the count, in hex
  ld hl,$7800 + 64*5 + 48
  call setad
  ld a,($C011)
  call hex
  ld a,($C010)
  call hex

; 5 frame interrupt
  ld a,$E0
  ld b,$81
  call reg
  ei
  ld a,(frames)
  add a,3
  ld b,a
t5a:
  ld a,(frames)
  cp b
  jr nz,t5a
  ld de,tn5
  ld c,4
  call result

; 6 line interrupt every 16 lines: 12 per frame
  ld a,15
  ld b,$8A
  call reg
  ld a,$16
  ld b,$80
  call reg
  ld b,3
  call waitf
  ld a,(lastl)
  cp 12
  ld de,tn6
  ld c,5
  call result
  di
  ld a,$06
  ld b,$80
  call reg
  ld a,$C0
  ld b,$81
  call reg

; 7 no overflow with 8 sprites, no collision
  ld hl,spr8
  call sprites
  and $60
  ld de,tn7
  ld c,6
  call result
; 8 overflow with 9
  ld hl,spr9
  call sprites
  and $60
  cp $40
  ld de,tn8
  ld c,7
  call result
; 9 collision
  ld hl,sprc
  call sprites
  and $60
  cp $20
  ld de,tn9
  ld c,8
  call result

; 10 CPU
  ld hl,$1234
  exx
  ld hl,$5678
  exx
  ld ix,$C200
  ld (ix+5),$99
  ld a,(ix+5)
  add a,1
  daa                   ; 00, carry
  jr nc,t10f
  ld bc,$0034
  adc hl,bc             ; 1234 + 34 + 1 = 1269
  ld a,l
  cp $69
  jr nz,t10f
  exx
  ld a,h
  exx
  cp $56
  jr nz,t10f
  ld hl,tn1
  ld de,$C300
  ld bc,16
  ldir
  ld a,($C30F)
  ld hl,tn1+15
  cp (hl)
  jr nz,t10f
  ld a,e
  cp $10
t10f:
  ld de,tn10
  ld c,9
  call result

; --- demo -------------------------------------------------------------------
  ld hl,$3800 + 2*(32*22+2)
  ld de,tkeys
  call print
  ; colour band, rows 13..20: tile 129 with the column in the palette bit,
  ; every 4th column with priority
  ld hl,$7800 + 64*13
  call setad
  ld hl,0
bl:
  ld a,l
  and 3
  ld a,129
  jr nz,bl1
  ld a,130
bl1:
  out (VD),a
  ld a,l
  and 12
  ld a,0
  jr nz,bl2
  ld a,$10              ; priority
bl2:
  out (VD),a
  inc hl
  ld a,h
  or a
  jr z,bl
  ld a,1
  ld (demo),a
  ld a,95
  ld b,$8A
  call reg
  ld a,$36              ; line int, mode 4, left column blank
  ld b,$80
  call reg
  ld a,$E2              ; 8 x 16 sprites
  ld b,$81
  call reg
  ei
loop:
  ld b,1
  call waitf
  ; scroll
  ld hl,scroll
  inc (hl)
  ; border
  ld a,(border)
  ld b,$87
  call reg
  ; pad
  in a,($DC)
  ld c,a
  ld hl,by
  bit 0,c
  jr nz,k1
  dec (hl)
k1:
  bit 1,c
  jr nz,k2
  inc (hl)
k2:
  ld hl,bx
  bit 2,c
  jr nz,k3
  dec (hl)
k3:
  bit 3,c
  jr nz,k4
  inc (hl)
k4:
  ; sound: tone 0 and noise
  ld a,$8E
  out (PSG),a
  ld a,$0F              ; period $0FE = 440 Hz
  out (PSG),a
  ld a,$9F
  bit 4,c
  jr nz,k5
  ld a,$92
k5:
  out (PSG),a
  ld a,$E5
  out (PSG),a
  ld a,$FF
  bit 5,c
  jr nz,k6
  ld a,$F4
k6:
  out (PSG),a
  ; sprite table: ball (2 sprites) + a row of 6
  ld hl,$7F00
  call setad
  ld a,(by)
  out (VD),a
  nop
  out (VD),a
  ld b,6
  ld a,150
s1:
  out (VD),a
  nop
  djnz s1
  ld a,$D0
  out (VD),a
  ld hl,$7F80
  call setad
  ld a,(bx)
  out (VD),a
  ld a,132
  out (VD),a
  ld a,(bx)
  add a,8
  out (VD),a
  ld a,134
  out (VD),a
  ld a,(scroll)
  neg
  ld b,6
s2:
  out (VD),a
  add a,24
  ld c,a
  ld a,132
  out (VD),a
  ld a,c
  djnz s2
  jp loop

; --- subroutines ------------------------------------------------------------
setad:                  ; VDP address / code = hl
  ld a,l
  out (VC),a
  ld a,h
  out (VC),a
  ret
reg:                    ; a -> register b (b = $80 + n); atomic
  push af
  ld a,i                ; P/V = IFF2
  di
  jp po,reg1
  pop af
  out (VC),a
  ld a,b
  out (VC),a
  ei
  ret
reg1:
  pop af
  out (VC),a
  ld a,b
  out (VC),a
  ret
hex:                    ; a in hex at the VRAM address
  push af
  rrca
  rrca
  rrca
  rrca
  call hex1
  pop af
hex1:
  and 15
  add a,$90
  daa
  adc a,$40
  daa
  out (VD),a
  ld a,0
  nop
  out (VD),a
  ret
waitvb:                 ; poll the frame flag (interrupts off)
  in a,(VC)
wv1:
  in a,(VC)
  add a,a
  jr nc,wv1
  ret
waitf:                  ; wait b frames (interrupts on)
  ld a,(frames)
  ld c,a
wf1:
  ld a,(frames)
  cp c
  jr z,wf1
  djnz waitf
  ret
print:                  ; zero-ended text de to VRAM hl
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
result:                 ; Z = passed; name de, row 2 + c
  push af
  ld l,c
  ld h,0
  inc l
  inc l
  ld b,6
rs1:
  add hl,hl
  djnz rs1
  ld bc,$3800 + 8
  add hl,bc
  call print
  ld de,tok
  pop af
  jr z,rs2
  ld de,tbad
rs2:
  jr pr1
sprites:                ; table at hl: n, then Ys, $D0, then x,tile; a = status of a frame
  push hl
  call waitvb
  ld hl,$7F00
  call setad
  pop hl
  ld b,(hl)
  ld d,b
  inc hl
  ld c,VD
sp1:
  outi
  jr nz,sp1
  ld a,$D0
  out (VD),a
  push hl
  ld hl,$7F80
  call setad
  pop hl
  sla d
  ld b,d
sp2:
  outi
  jr nz,sp2
  call waitvb
  call sp3
  push af
  ld hl,$7F00           ; off again
  call setad
  ld a,$D0
  out (VD),a
  pop af
  ret
sp3:                    ; line 190 of the next frame, then one status read
  in a,($7E)
  cp 190
  jr nz,sp3
  in a,(VC)
  ret

silence:
  .db $9F,$BF,$DF,$FF
regs:
  .db $06,$80,$80,$81,$FF,$82,$FF,$83,$FF,$84,$FF,$85,$FB,$86,$00,$87,$00,$88,$00,$89,$FF,$8A
pal:
  .db $10,$3F,$03,$0C,$30,$0F,$3C,$33,$15,$2A,$02,$08,$20,$0A,$28,$22
  .db $00,$3F,$03,$0C,$30,$0F,$3C,$33,$15,$2A,$02,$08,$20,$0A,$28,$22
ttitle: .db "MASTER SYSTEM TANG NANO 9K",0
tkeys:  .db "PAD MOVES  1 TONE  2 NOISE",0
tn1:  .db "RAM 8K         ",0
tn2:  .db "VRAM           ",0
tn3:  .db "V COUNTER      ",0
tn4:  .db "CLOCKS / FRAME ",0
tn5:  .db "FRAME INT      ",0
tn6:  .db "LINE INT       ",0
tn7:  .db "8 SPRITES      ",0
tn8:  .db "9 SPRITES      ",0
tn9:  .db "COLLISION      ",0
tn10: .db "CPU            ",0
tok:  .db "OK",0
tbad: .db "FAIL",0
spr8:
  .db 8
  .db 160,160,160,160,160,160,160,160
  .db 8,131,24,131,40,131,56,131,72,131,88,131,104,131,120,131
spr9:
  .db 9
  .db 160,160,160,160,160,160,160,160,160
  .db 8,131,24,131,40,131,56,131,72,131,88,131,104,131,120,131,136,131
sprc:
  .db 2
  .db 160,166
  .db 100,131,106,131
gfx:    ; 128 unused, 129 bars, 130 box, 131 solid, 132..135 ball
  .incbin "gfx.bin"
font:   ; ASCII 32..95
  .incbin "font.bin"
