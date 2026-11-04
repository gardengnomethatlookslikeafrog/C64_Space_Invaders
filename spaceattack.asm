; ============================================================
;  SPACE ATTACK  -  Commodore 64, 6502 assembly (ACME syntax)
;
;  Controls : A / Z / ,  = left      D / X / .  = right
;             SPACE or RETURN = fire
;             (joystick in port 2 also works)
;
;  Build    : acme -f cbm -o spaceattack.prg spaceattack.asm
;  Run      : LOAD "SPACEATTACK",8,1   then   RUN
;             (or drag the .prg onto an online C64 emulator)
; ============================================================

!cpu 6502
!to "spaceattack.prg", cbm

; ---------- constants -------------------------------------
SCREEN    = $0400
COLRAM    = $d800
CHARRAM   = $3000            ; our RAM copy of the character set
ptr       = $fb              ; zero page pointers
ptr2      = $fd
ptr3      = $f7
NB        = 3                ; max simultaneous alien bombs

CH_A1A    = $40              ; custom characters (screen codes)
CH_A2A    = $42
CH_A3A    = $44
CH_PLAYER = $46
CH_BULLET = $47
CH_BOMB   = $48
CH_EXPL   = $49
CH_GROUND = $4a

; ---------- BASIC stub:  10 SYS 2061 ----------------------
* = $0801
!byte $0b,$08,$0a,$00,$9e
!text "2061"
!byte $00,$00,$00

; ---------- macros ----------------------------------------
!macro print .t, .x, .y, .c {
    lda #<.t
    sta ptr2
    lda #>.t
    sta ptr2+1
    lda #.c
    sta pcol
    ldx #.x
    ldy #.y
    jsr printstr
}

!macro key .cm, .rm, .var {
    lda #.cm
    sta $dc00
    nop
    lda $dc01
    and #.rm
    bne .no
    lda #1
    sta .var
.no
}

; ============================================================
start:
    sei
    cld
    lda #0
    sta $d020
    sta $d021
    sta hi
    sta hi+1
    jsr initchars
    lda #$1c                 ; screen $0400, charset $3000
    sta $d018
    jsr initsid

menu:
    jsr titlescreen
    jsr newgame

; ---------------- main game loop --------------------------
game:
    jsr waitframe
    jsr readinput
    jsr doplayer
    jsr dobullet
    jsr doexplosion
    lda nalive
    bne g_alive
    jmp wave_clear
g_alive:
    lda entering             ; wave entrance: aliens fly in first
    beq g_norm
    jsr doentry
    jmp g_chk
g_norm:
    jsr dobombs
    jsr doplayfly
    inc mtimer
    lda mtimer
    cmp mdelay
    bcc g_chk
    lda #0
    sta mtimer
    jsr movestep
g_chk:
    lda status
    bne g_ev
    jmp game
g_ev:
    cmp #2
    bne g_ph
    jmp gameover             ; aliens have landed
g_ph:
    jmp playerhit

; ---------------- events ----------------------------------
wave_clear:
    ldx #50
    jsr delay
    inc level
    jsr newwave
    jmp game

playerhit:
    lda #$02
    sta pcol
    lda #CH_EXPL
    ldx px
    ldy #23
    jsr plot
    jsr sfx_boom
    ldx #60
    jsr delay
    dec lives
    jsr drawlives
    lda lives
    bne ph_go
    jmp gameover
ph_go:
    jsr clearshots
    lda #0
    sta status
    jmp game

gameover:
    lda score+1              ; new high score?
    cmp hi+1
    bcc go_nohi
    bne go_newhi
    lda score
    cmp hi
    bcc go_nohi
go_newhi:
    lda score
    sta hi
    lda score+1
    sta hi+1
go_nohi:
    jsr drawhud
    +print txt_gameover,15,12,$02
    ldx #120
    jsr delay
    jmp menu

; ============================================================
;  title screen
; ============================================================
titlescreen:
    jsr cls
    jsr drawhud
    +print txt_t1,8,3,$07
    +print txt_t2,8,5,$0f
    +print txt_p3,12,8,$0a
    +print txt_p2,12,10,$03
    +print txt_p1,12,12,$0d
    +print txt_k1,10,15,$0e
    +print txt_k2,10,16,$0e
    +print txt_k3,10,17,$0e
    +print txt_k4,10,18,$0e
    +print txt_start,6,21,$07
    jsr waitrelease
    jsr waitfire
    rts

; ============================================================
;  new game / new wave
; ============================================================
newgame:
    lda #0
    sta score
    sta score+1
    lda #3
    sta lives
    lda #1
    sta level
    ; fall through

newwave:
    jsr cls
    jsr drawhud
    jsr drawground
    ldx #39
    lda #0
nw1:
    sta alive,x
    dex
    bpl nw1
    lda #40
    sta nalive
    lda #8
    sta fx
    lda level                ; start row = 2 + min(level-1,4)
    sec
    sbc #1
    cmp #5
    bcc nw2
    lda #4
nw2:
    clc
    adc #2
    sta fy
    lda level                ; bomb frequency by level
    sec
    sbc #1
    cmp #3
    bcc nw3
    lda #3
nw3:
    tax
    lda bmtab,x
    sta bmask
    lda #1
    sta dir
    lda #0
    sta frame
    sta status
    sta bact
    sta ex_t
    sta mtimer
    sta btimer
    ldx #NB-1
nw4:
    sta bmy,x
    dex
    bpl nw4
    lda #20
    sta px
    sta mdelay
    lda #1
    sta entering
    lda #0
    sta lcount
    sta ltimer
    sta ftimer
    sta ftick
    sta nfly
    sta pend
    sta evc
    lda $d41b                ; 3..5 fly-ins per wave
    and #3
    clc
    adc #3
    cmp #6
    bcc nw5
    lda #5
nw5:
    sta evleft
    lda $d41b                ; first one after 1..2 x 256 frames
    and #1
    clc
    adc #1
    sta evwait
    rts

; ============================================================
;  alien formation
; ============================================================
; A = 0 : erase formation, A = 1 : draw formation
drawform:
    sta dmode
    lda #0
    sta dr
df_row:
    lda dr
    asl
    clc
    adc fy
    sta dy
    lda dr
    asl
    asl
    asl
    sta dbase
    ldx dr
    lda rowchar,x
    clc
    adc frame
    sta dchar
    lda rowcol,x
    sta pcol
    lda #0
    sta dc
df_col:
    lda dbase
    clc
    adc dc
    tax
    lda alive,x
    cmp #1
    bne df_skip
    ldx dc
    lda mul3,x
    clc
    adc fx
    tax
    ldy dy
    lda dmode
    beq df_er
    lda dchar
    jmp df_pl
df_er:
    lda #$20
df_pl:
    jsr plot
df_skip:
    inc dc
    lda dc
    cmp #8
    bne df_col
    inc dr
    lda dr
    cmp #5
    bne df_row
    rts

; work out leftmost/rightmost column, lowest row, alive count
calcext:
    lda #7
    sta minc
    lda #0
    sta maxc
    sta maxr
    sta cnt
    ldx #39
ce_l:
    lda alive,x
    beq ce_next
    inc cnt
    txa
    and #7
    cmp minc
    bcs ce_1
    sta minc
ce_1:
    cmp maxc
    bcc ce_2
    sta maxc
ce_2:
    txa
    lsr
    lsr
    lsr
    cmp maxr
    bcc ce_next
    sta maxr
ce_next:
    dex
    bpl ce_l
    ldx minc
    lda mul3,x
    sta minc3
    ldx maxc
    lda mul3,x
    sta maxc3
    lda cnt
    sta nalive
    rts

; one step of the alien formation
movestep:
    jsr calcext
    lda nalive               ; speed: fewer aliens = faster
    lsr
    clc
    adc #3
    sta mdelay
    lda level
    sec
    sbc #1
    cmp #3
    bcc ms_b
    lda #2
ms_b:
    sta tmp
    lda mdelay
    sec
    sbc tmp
    sta mdelay
    lda #0
    jsr drawform             ; erase
    lda dir
    bmi ms_left
    lda maxc3
    clc
    adc fx
    cmp #39
    bcs ms_down
    inc fx
    jmp ms_moved
ms_left:
    lda minc3
    clc
    adc fx
    beq ms_down
    dec fx
    jmp ms_moved
ms_down:
    lda dir
    eor #$fe
    sta dir
    inc fy
ms_moved:
    lda maxr                 ; reached the bottom?
    asl
    clc
    adc fy
    cmp #22
    bcc ms_ok
    lda #2
    sta status
ms_ok:
    lda frame
    eor #1
    sta frame
    lda #1
    jmp drawform             ; draw (tail call)

; ============================================================
;  wave entrance: aliens fly in from both sides, loop the
;  loop, then home in on their place in the formation
;  alive[] : 0 = dead, 1 = in formation, 2 = flying
; ============================================================
PL        = 47                    ; number of points in the flight path

doentry:
    inc ftimer
    lda ftimer
    cmp #2                   ; flyers move every 2nd frame
    bcs en_go
    rts
en_go:
    lda #0
    sta ftimer
    inc ltimer
    lda ltimer
    cmp #3                   ; launch a pair every 3rd step
    bcc en_nl
    lda #0
    sta ltimer
    lda lcount
    cmp #20
    bcs en_nl
    jsr launch
en_nl:
    jsr flytick
    lda lcount               ; everyone launched and landed?
    cmp #20
    bcc en_ret
    lda nfly
    bne en_ret
    lda #0
    sta entering
    sta mtimer
en_ret:
    rts

; move every flying alien one step
flytick:
    lda ftick                ; wing flap toggle
    eor #1
    sta ftick
    ldx #39
ft_l:
    stx fi
    lda alive,x
    cmp #2
    bne ft_n
    jsr flyone
ft_n:
    ldx fi
    dex
    bpl ft_l
    rts

; ============================================================
;  fly-ins during play: now and then one or two extra aliens
;  fly in, loop, and settle into a gap in the formation
; ============================================================
doplayfly:
    inc evc
    bne pf_noev
    lda evwait               ; every 256 frames
    beq pf_try
    dec evwait
    jmp pf_noev
pf_try:
    lda evleft
    beq pf_noev
    lda pend
    bne pf_noev
    jsr pickvac              ; is there a gap to fill?
    bcc pf_retry
    dec evleft
    lda $d41b
    and #1
    clc
    adc #1
    sta pend                 ; 1 or 2 flies
    jsr newevwait
    jmp pf_noev
pf_retry:
    lda #1
    sta evwait
pf_noev:
    lda nfly
    ora pend
    beq pf_ret
    inc ftimer
    lda ftimer
    cmp #2
    bcc pf_ret
    lda #0
    sta ftimer
    lda pend
    beq pf_nl
    inc ltimer
    lda ltimer
    cmp #3
    bcc pf_nl
    lda #0
    sta ltimer
    jsr pickvac
    bcc pf_cancel
    jsr startfly
    inc nalive               ; one more alien in play
    dec pend
    jmp pf_nl
pf_cancel:
    lda #0
    sta pend
pf_nl:
    jsr flytick
pf_ret:
    rts

; pick a random empty formation slot.  carry set = found, X = index
pickvac:
    lda $d41b
    and #$3f
    cmp #40
    bcc pk_1
    sbc #40
pk_1:
    tax
    ldy #40
pk_l:
    lda alive,x
    beq pk_ok
    inx
    cpx #40
    bcc pk_2
    ldx #0
pk_2:
    dey
    bne pk_l
    clc
    rts
pk_ok:
    sec
    rts

newevwait:                   ; next fly-in in 1..3 x 256 frames
    lda $d41b
    and #3
    cmp #3
    bcc ne_1
    lda #0
ne_1:
    clc
    adc #1
    sta evwait
    rts

; did the bullet touch a flying alien?  carry set = yes
hitfly:
    ldx #39
hf_l:
    lda alive,x
    cmp #2
    bne hf_n
    lda fcx,x
    cmp #$ff
    beq hf_n
    sec
    sbc bx
    bcs hf_1
    eor #$ff
    adc #1
hf_1:
    cmp #2
    bcs hf_n
    lda fcy,x
    sec
    sbc by
    bcs hf_2
    eor #$ff
    adc #1
hf_2:
    cmp #2
    bcs hf_n
    lda #0                   ; shot down!
    sta alive,x
    dec nfly
    lda fcx,x
    sta bx
    lda fcy,x
    sta by
    lda #5                   ; score row 5 = flying alien (50 points)
    sta hr
    sec
    rts
hf_n:
    dex
    bpl hf_l
    clc
    rts

; launch one alien from the left and one from the right
launch:
    lda lcount
    lsr
    lsr
    asl
    asl
    asl
    sta tmp                  ; row * 8
    lda lcount
    and #3
    sta tmp2                 ; 0..3
    lda tmp
    clc
    adc tmp2
    tax                      ; left alien
    jsr startfly
    lda tmp
    clc
    adc #7
    sec
    sbc tmp2
    tax                      ; right alien (mirror)
    jsr startfly
    inc lcount
    rts

startfly:
    lda #2
    sta alive,x
    lda #0
    sta fstep,x
    lda #$ff
    sta fcx,x                ; $ff = nothing drawn yet
    inc nfly
    rts

; move flying alien number 'fi' one step
flyone:
    ldx fi
    lda fcx,x
    cmp #$ff
    beq fo_move
    sta sx                   ; erase old image
    sta tx
    lda fcy,x
    sta sy
    sta ty
    lda #$20
    ldx tx
    ldy ty
    jsr plot
    jsr findslot             ; ...but redraw a landed alien that was here
    bcc fo_move
    lda alive,x
    cmp #1
    bne fo_move
    ldy hr
    lda rowcol,y
    sta pcol
    lda rowchar,y
    clc
    adc frame
    ldx tx
    ldy ty
    jsr plot
fo_move:
    ldx fi
    lda fstep,x
    cmp #PL
    bcs fo_home
    tay                      ; --- still on the looping flight path
    lda pathx,y
    sta tx
    lda pathy,y
    sta ty
    txa
    and #7
    cmp #4                   ; right half of the formation: mirror the path
    bcc fo_nm
    lda #39
    sec
    sbc tx
    sta tx
fo_nm:
    inc fstep,x
    jmp fo_draw
fo_home:                     ; --- fly straight to the slot
    txa
    and #7
    tay
    lda mul3,y
    clc
    adc fx
    sta gx
    txa
    lsr
    lsr
    lsr
    asl
    clc
    adc fy
    sta gy
    lda fcx,x
    sta tx
    lda fcy,x
    sta ty
    lda tx
    cmp gx
    beq fo_y
    bcc fo_xi
    dec tx
    jmp fo_y
fo_xi:
    inc tx
fo_y:
    lda ty
    cmp gy
    beq fo_chk
    bcc fo_yi
    dec ty
    jmp fo_chk
fo_yi:
    inc ty
fo_chk:
    lda tx
    cmp gx
    bne fo_draw
    lda ty
    cmp gy
    bne fo_draw
    ldx fi                   ; arrived: join the formation
    lda #1
    sta alive,x
    dec nfly
    txa
    lsr
    lsr
    lsr
    tay
    lda rowcol,y
    sta pcol
    lda rowchar,y
    clc
    adc frame
    ldx tx
    ldy ty
    jmp plot
fo_draw:
    ldx fi
    lda tx
    sta fcx,x
    lda ty
    sta fcy,x
    txa
    lsr
    lsr
    lsr
    tay
    lda rowcol,y
    sta pcol
    lda rowchar,y
    clc
    adc ftick                ; flapping wings
    ldx tx
    ldy ty
    jmp plot

; ============================================================
;  player
; ============================================================
doplayer:
    inc pmt
    lda pmt
    and #1
    bne dp_draw
    lda inl
    beq dp_1
    lda px
    beq dp_1
    jsr erasep
    dec px
dp_1:
    lda inr
    beq dp_draw
    lda px
    cmp #39
    bcs dp_draw
    jsr erasep
    inc px
dp_draw:
    lda #1
    sta pcol
    lda #CH_PLAYER
    ldx px
    ldy #23
    jmp plot

erasep:
    lda #$20
    ldx px
    ldy #23
    jmp plot

; ============================================================
;  player bullet
; ============================================================
dobullet:
    lda bact
    bne db_active
    lda inf
    beq db_ret
    lda #1
    sta bact
    lda px
    sta bx
    lda #22
    sta by
    jsr sfx_shoot
    jmp db_draw
db_active:
    jsr hittest              ; (alien may have moved into the bullet)
    bcs db_hit
    ldx bx
    ldy by
    jsr peek
    cmp #CH_BULLET
    bne db_mv
    lda #$20
    ldx bx
    ldy by
    jsr plot
db_mv:
    dec by
    lda by
    beq db_off
    jsr hittest
    bcs db_hit
    lda entering
    bne db_draw
    lda nfly
    beq db_draw
    jsr hitfly
    bcc db_draw
    jmp killalien
db_draw:
    lda #1
    sta pcol
    lda #CH_BULLET
    ldx bx
    ldy by
    jsr plot
db_ret:
    rts
db_off:
    lda #0
    sta bact
    rts
db_hit:
    jmp killalien

; is cell (sx,sy) a formation slot?  carry set = yes, X = index, hr = row
findslot:
    lda sy
    sec
    sbc fy
    bcc fs_no
    lsr
    bcs fs_no                ; odd offset = gap between rows
    cmp #5
    bcs fs_no
    sta hr
    lda sx
    sec
    sbc fx
    bcc fs_no
    ldx #0
fs_d:
    cmp #3
    bcc fs_e
    sbc #3
    inx
    jmp fs_d
fs_e:
    cmp #0
    bne fs_no
    cpx #8
    bcs fs_no
    stx tmp
    lda hr
    asl
    asl
    asl
    clc
    adc tmp
    tax
    sec
    rts
fs_no:
    clc
    rts

; does the bullet cell (bx,by) contain a landed alien?  carry set = yes
hittest:
    lda bx
    sta sx
    lda by
    sta sy
    jsr findslot
    bcc ht_no
    lda alive,x
    cmp #1
    bne ht_no
    lda #0
    sta alive,x
    sec
    rts
ht_no:
    clc
    rts

killalien:
    lda #0
    sta bact
    dec nalive
    ldx hr
    lda pts,x
    jsr addscore
    jsr showscore
    lda ex_t                 ; remove an older explosion first
    beq ka_1
    ldx ex_x
    ldy ex_y
    jsr peek
    cmp #CH_EXPL
    bne ka_1
    lda #$20
    ldx ex_x
    ldy ex_y
    jsr plot
ka_1:
    lda bx
    sta ex_x
    lda by
    sta ex_y
    lda #8
    sta ex_t
    lda #$07
    sta pcol
    lda #CH_EXPL
    ldx bx
    ldy by
    jsr plot
    jmp sfx_boom

doexplosion:
    lda ex_t
    beq de_ret
    dec ex_t
    bne de_ret
    ldx ex_x
    ldy ex_y
    jsr peek
    cmp #CH_EXPL
    bne de_ret
    lda #$20
    ldx ex_x
    ldy ex_y
    jsr plot
de_ret:
    rts

; ============================================================
;  alien bombs
; ============================================================
dobombs:
    inc btimer
    lda btimer
    cmp #4
    bcs dbm_go
    rts
dbm_go:
    lda #0
    sta btimer
    ldx #NB-1
dbm_l:
    stx bi
    lda bmy,x
    bne dbm_act
    jsr tryspawn
    jmp dbm_next
dbm_act:
    sta ty
    lda bmx,x
    sta tx
    ldx tx                   ; erase old bomb image
    ldy ty
    jsr peek
    cmp #CH_BOMB
    bne dbm_mov
    lda #$20
    ldx tx
    ldy ty
    jsr plot
dbm_mov:
    inc ty
    ldx bi
    lda ty
    sta bmy,x
    cmp #23
    bcc dbm_draw
    lda tx                   ; bomb is at player height
    cmp px
    beq dbm_hit
    lda ty
    cmp #24
    bcs dbm_rem
dbm_draw:
    ldx tx
    ldy ty
    jsr peek
    cmp #$20
    bne dbm_next
    lda #$08
    sta pcol
    lda #CH_BOMB
    ldx tx
    ldy ty
    jsr plot
    jmp dbm_next
dbm_rem:
    ldx bi
    lda #0
    sta bmy,x
    jmp dbm_next
dbm_hit:
    ldx bi
    lda #0
    sta bmy,x
    lda #1
    sta status
dbm_next:
    ldx bi
    dex
    bmi dbm_exit
    jmp dbm_l
dbm_exit:
    rts

; maybe launch a new bomb in slot 'bi'
tryspawn:
    lda $d41b
    and bmask
    bne ts_ret
    lda $d41b
    and #7
    sta tc
    ldy #4
ts_l:
    tya
    asl
    asl
    asl
    clc
    adc tc
    tax
    lda alive,x
    cmp #1
    beq ts_found
    dey
    bpl ts_l
ts_ret:
    rts
ts_found:
    ldx tc
    lda mul3,x
    clc
    adc fx
    sta tx
    tya
    asl
    clc
    adc fy
    clc
    adc #1
    sta ty
    ldx bi
    lda tx
    sta bmx,x
    lda ty
    sta bmy,x
    rts

; remove all bombs and the bullet from the screen
clearshots:
    ldx #NB-1
cs_1:
    stx bi
    lda bmy,x
    beq cs_2
    sta ty
    lda bmx,x
    sta tx
    ldx tx
    ldy ty
    jsr peek
    cmp #CH_BOMB
    bne cs_3
    lda #$20
    ldx tx
    ldy ty
    jsr plot
cs_3:
    ldx bi
    lda #0
    sta bmy,x
cs_2:
    ldx bi
    dex
    bpl cs_1
    lda bact
    beq cs_4
    ldx bx
    ldy by
    jsr peek
    cmp #CH_BULLET
    bne cs_5
    lda #$20
    ldx bx
    ldy by
    jsr plot
cs_5:
    lda #0
    sta bact
cs_4:
    rts

; ============================================================
;  input  (joystick port 2 + keyboard matrix scan)
; ============================================================
readinput:
    lda #0
    sta inl
    sta inr
    sta inf
    sta $dc02                ; port A -> inputs, read joystick 2
    lda $dc00
    ldx #$ff
    stx $dc02                ; port A -> outputs for key scan
    eor #$ff
    sta joy
    and #$04
    beq ri_1
    inc inl
ri_1:
    lda joy
    and #$08
    beq ri_2
    inc inr
ri_2:
    lda joy
    and #$10
    beq ri_3
    inc inf
ri_3:
    +key $fd,$04,inl         ; A
    +key $fd,$10,inl         ; Z
    +key $df,$80,inl         ; ,
    +key $fb,$04,inr         ; D
    +key $fb,$80,inr         ; X
    +key $df,$10,inr         ; .
    +key $7f,$10,inf         ; SPACE
    +key $fe,$02,inf         ; RETURN
    lda #$ff
    sta $dc00
    rts

waitrelease:
    jsr waitframe
    jsr readinput
    lda inf
    bne waitrelease
    rts

waitfire:
    jsr waitframe
    jsr readinput
    lda inf
    beq waitfire
    rts

; ============================================================
;  utility routines
; ============================================================
waitframe:
    lda $d012
    cmp #$f8
    bne waitframe
wf_2:
    lda $d012
    cmp #$f8
    beq wf_2
    rts

delay:                       ; X = number of frames
    stx dcount
dl_1:
    jsr waitframe
    dec dcount
    bne dl_1
    rts

; plot: A = char, X = column, Y = row, colour in pcol
plot:
    sta pchar
    lda rowlo,y
    sta ptr
    lda rowhi,y
    sta ptr+1
    txa
    tay
    lda pchar
    sta (ptr),y
    lda ptr+1
    clc
    adc #$d4
    sta ptr+1
    lda pcol
    sta (ptr),y
    rts

; peek: X = column, Y = row -> A = screen code
peek:
    lda rowlo,y
    sta ptr
    lda rowhi,y
    sta ptr+1
    txa
    tay
    lda (ptr),y
    rts

; print $ff-terminated string at ptr2, X = col, Y = row, colour = pcol
printstr:
    txa
    clc
    adc rowlo,y
    sta ptr
    lda rowhi,y
    adc #0
    sta ptr+1
    lda ptr
    sta ptr3
    lda ptr+1
    clc
    adc #$d4
    sta ptr3+1
    ldy #0
ps_1:
    lda (ptr2),y
    cmp #$ff
    beq ps_2
    sta (ptr),y
    lda pcol
    sta (ptr3),y
    iny
    bne ps_1
ps_2:
    rts

cls:
    ldx #0
cls_1:
    lda #$20
    sta $0400,x
    sta $0500,x
    sta $0600,x
    sta $0700,x
    lda #$01
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $db00,x
    inx
    bne cls_1
    rts

drawground:
    ldx #39
dg_1:
    lda #CH_GROUND
    sta $07c0,x
    lda #$05
    sta $dbc0,x
    dex
    bpl dg_1
    rts

; ---------- score (BCD, 2 bytes = 4 digits, + fixed "0") --
addscore:                    ; A = BCD amount (in tens)
    sed
    clc
    adc score
    sta score
    lda score+1
    adc #0
    sta score+1
    cld
    rts

drawhud:
    ldx #39
    lda #$01
dh_1:
    sta COLRAM,x
    dex
    bpl dh_1
    +print txt_score,0,0,$0e
    +print txt_hi,13,0,$0e
    +print txt_lives,24,0,$0e
    +print txt_lv,33,0,$0e
    jsr showscore
    jsr showhi
    jsr drawlives
    jmp drawlevel

showscore:
    lda score+1
    sta nhi
    lda score
    sta nlo
    lda #6
    sta numcol
    jmp shownum

showhi:
    lda hi+1
    sta nhi
    lda hi
    sta nlo
    lda #16
    sta numcol
    jmp shownum

shownum:
    ldy numcol
    lda nhi
    lsr
    lsr
    lsr
    lsr
    ora #$30
    sta SCREEN,y
    iny
    lda nhi
    and #$0f
    ora #$30
    sta SCREEN,y
    iny
    lda nlo
    lsr
    lsr
    lsr
    lsr
    ora #$30
    sta SCREEN,y
    iny
    lda nlo
    and #$0f
    ora #$30
    sta SCREEN,y
    iny
    lda #$30
    sta SCREEN,y
    rts

drawlives:
    lda lives
    ora #$30
    sta SCREEN+30
    rts

drawlevel:
    lda level
    cmp #10
    bcc dlv_1
    lda #9
dlv_1:
    ora #$30
    sta SCREEN+36
    rts

; ---------- sound -----------------------------------------
initsid:
    lda #$ff
    sta $d40e                ; voice 3 = noise, used as random generator
    sta $d40f
    lda #$80
    sta $d412
    lda #$0f
    sta $d418
    rts

sfx_shoot:
    lda #$00
    sta $d404
    sta $d400
    sta $d402
    sta $d406
    lda #$28
    sta $d401
    lda #$08
    sta $d403
    lda #$05
    sta $d405
    lda #$41
    sta $d404
    rts

sfx_boom:
    lda #$00
    sta $d40b
    sta $d407
    sta $d40d
    lda #$08
    sta $d408
    lda #$09
    sta $d40c
    lda #$81
    sta $d40b
    rts

; ---------- character set ---------------------------------
initchars:
    lda $01
    pha
    lda #$33                 ; character ROM visible at $d000
    sta $01
    lda #$00
    sta ptr
    sta ptr2
    lda #$d0
    sta ptr+1
    lda #>CHARRAM
    sta ptr2+1
    ldx #8
    ldy #0
ic_1:
    lda (ptr),y
    sta (ptr2),y
    iny
    bne ic_1
    inc ptr+1
    inc ptr2+1
    dex
    bne ic_1
    pla
    sta $01
    ldx #0
ic_2:
    lda gfx,x
    sta CHARRAM+$200,x       ; screen codes $40 and up
    inx
    cpx #11*8
    bne ic_2
    rts

; ============================================================
;  data
; ============================================================
gfx:
    ; $40 bottom alien, frame A
    !byte %00011000,%00111100,%01111110,%11011011
    !byte %11111111,%00100100,%01011010,%10100101
    ; $41 bottom alien, frame B
    !byte %00011000,%00111100,%01111110,%11011011
    !byte %11111111,%00100100,%01000010,%00100100
    ; $42 middle alien, frame A
    !byte %00100100,%10100101,%11111111,%11011011
    !byte %11111111,%01111110,%00100100,%01000010
    ; $43 middle alien, frame B
    !byte %00100100,%00100100,%01111110,%11011011
    !byte %11111111,%11111111,%10100101,%10100101
    ; $44 top alien, frame A
    !byte %00111100,%01111110,%11111111,%10011001
    !byte %11111111,%00100100,%01011010,%10000001
    ; $45 top alien, frame B
    !byte %00111100,%01111110,%11111111,%10011001
    !byte %11111111,%00100100,%01000010,%00100100
    ; $46 player cannon
    !byte %00011000,%00011000,%00111100,%00111100
    !byte %01111110,%11111111,%11111111,%11111111
    ; $47 bullet
    !byte %00011000,%00011000,%00011000,%00011000
    !byte %00011000,%00011000,%00011000,%00000000
    ; $48 bomb
    !byte %00010000,%00001000,%00010000,%00001000
    !byte %00010000,%00001000,%00010000,%00001000
    ; $49 explosion
    !byte %10010001,%01001010,%00100100,%11000011
    !byte %11000011,%00100100,%01001010,%10010001
    ; $4a ground
    !byte %11111111,%00000000,%00000000,%00000000
    !byte %00000000,%00000000,%00000000,%00000000

; flight path for aliens entering from the left (right side is mirrored)
pathx:
    !byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    !byte 16,17,18,18,19,19,19,19,19,18,18,17,16,15,14,13
    !byte 12,11,10,10,9,9,9,9,9,10,10,11,12,13,14
pathy:
    !byte 12,13,14,14,15,16,16,16,17,17,18,18,18,18,18,18
    !byte 18,17,17,16,15,14,13,12,11,10,9,9,8,8,8,8
    !byte 8,9,9,10,11,12,13,14,15,16,17,17,18,18,18

rowlo:
!for i, 0, 24 {
    !byte <(SCREEN + i*40)
}
rowhi:
!for i, 0, 24 {
    !byte >(SCREEN + i*40)
}

mul3:     !byte 0,3,6,9,12,15,18,21
rowchar:  !byte CH_A3A, CH_A2A, CH_A2A, CH_A1A, CH_A1A
rowcol:   !byte $0a,$03,$03,$0d,$0d
pts:      !byte $03,$02,$02,$01,$01,$05          ; BCD, in tens
bmtab:    !byte $1f,$0f,$07,$07

txt_score:    !scr "score",$ff
txt_hi:       !scr "hi",$ff
txt_lives:    !scr "lives",$ff
txt_lv:       !scr "lv",$ff
txt_gameover: !scr "game over",$ff
txt_t1:       !scr "s p a c e   a t t a c k",$ff
txt_t2:       !scr "written in 6502 assembly",$ff
txt_p3:       !byte CH_A3A,$20
              !scr "= 30 points",$ff
txt_p2:       !byte CH_A2A,$20
              !scr "= 20 points",$ff
txt_p1:       !byte CH_A1A,$20
              !scr "= 10 points",$ff
txt_k1:       !scr "a or z      move left",$ff
txt_k2:       !scr "d or x      move right",$ff
txt_k3:       !scr "space       fire",$ff
txt_k4:       !scr "or joystick in port 2",$ff
txt_start:    !scr "press space or fire to start",$ff

; ---------- variables -------------------------------------
inl:      !byte 0
inr:      !byte 0
inf:      !byte 0
joy:      !byte 0
fx:       !byte 0
fy:       !byte 0
dir:      !byte 0
frame:    !byte 0
mtimer:   !byte 0
mdelay:   !byte 0
nalive:   !byte 0
minc:     !byte 0
maxc:     !byte 0
maxr:     !byte 0
cnt:      !byte 0
minc3:    !byte 0
maxc3:    !byte 0
bx:       !byte 0
by:       !byte 0
bact:     !byte 0
px:       !byte 0
score:    !byte 0,0
hi:       !byte 0,0
lives:    !byte 0
level:    !byte 0
ex_x:     !byte 0
ex_y:     !byte 0
ex_t:     !byte 0
bmx:      !fill NB,0
bmy:      !fill NB,0
btimer:   !byte 0
bi:       !byte 0
bmask:    !byte 0
status:   !byte 0
tmp:      !byte 0
pchar:    !byte 0
pcol:     !byte 0
tx:       !byte 0
ty:       !byte 0
tc:       !byte 0
hr:       !byte 0
dmode:    !byte 0
dr:       !byte 0
dc:       !byte 0
dy:       !byte 0
dbase:    !byte 0
dchar:    !byte 0
numcol:   !byte 0
nhi:      !byte 0
nlo:      !byte 0
pmt:      !byte 0
dcount:   !byte 0
entering: !byte 0
lcount:   !byte 0
ltimer:   !byte 0
ftimer:   !byte 0
ftick:    !byte 0
nfly:     !byte 0
fi:       !byte 0
sx:       !byte 0
sy:       !byte 0
gx:       !byte 0
gy:       !byte 0
tmp2:     !byte 0
evc:      !byte 0
evwait:   !byte 0
evleft:   !byte 0
pend:     !byte 0
fstep:    !fill 40,0
fcx:      !fill 40,0
fcy:      !fill 40,0
alive:    !fill 40,0
