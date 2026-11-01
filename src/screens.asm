;=======================================================================================
; screens.asm - the title menu, the reading table and the card detail view.
;
; Each screen is a loop: frame_input, logic, then either a full redraw (which ends in
; present, synced to the frame) or wait_frame. Nothing is drawn unless something changed
; (the pointer is a hardware sprite); animations set `dirty` every frame they run.
; Screens jump to each other and reset the stack on entry.
;=======================================================================================

RS_WAIT         = 0                     ; the deck waits to be shuffled
RS_SHUFFLE      = 1
RS_DEAL         = 2
RS_PLAY         = 3                     ; cards on the table, turning them over
CS_NONE         = 0                     ; a card: not dealt yet
CS_DOWN         = 1                     ;   face down
CS_FLIP         = 2                     ;   turning over (rd_anim)
CS_UP           = 3                     ;   face up
SHUF_N          = 96                    ; frames of shuffling (three riffles)
DEAL_N          = 12                    ; frames per card flying to its place
FLIP_N          = 12                    ; frames per card turning over

B_SPREAD0       = 0                     ; button ids: 0-3 the spreads
B_REVERSALS     = 4
B_BACK          = 10
B_REVEAL        = 11
B_NEW           = 12
B_PREV          = 13
B_NEXT          = 14

RESET_STACK .macro
        ldx #$ff
        txs
        .endmacro

dirty:          .byte 0
reversals:      .byte 1                 ; cards may come out upside down
spread:         .byte 0
toll_t:         .byte 0
toll_c:         .byte 0

;---------------------------------------------------------------------------------------
; the title
;---------------------------------------------------------------------------------------
title_screen:
        #RESET_STACK
        jsr fade_out
        lda #BG_TITLE
        sta cur_screen
        lda #$ff
        sta hover_btn
        jsr title_draw
        jsr fade_in
_loop:  jsr frame_input
        inc toll_t                      ; a bell tolls now and then
        bne +
        lda toll_c
        eor #1
        sta toll_c
        beq +
        lda #SFX_TOLL
        jsr sfx_play
+       lda #<title_buttons
        ldx #>title_buttons
        jsr buttons_find
        cmp hover_btn
        beq +
        sta hover_btn
        lda #1
        sta dirty
+       lda mouse_left_click
        beq _draw
        lda hover_btn
        cmp #B_REVERSALS
        bcc _spread
        bne _draw
        lda reversals
        eor #1
        sta reversals
        jsr set_rev_label
        lda #SFX_CLICK
        jsr sfx_play
        lda #1
        sta dirty
_draw:  lda dirty
        beq +
        jsr title_draw
        bra _loop
+       jsr wait_frame
        bra _loop
_spread:
        sta spread
        lda #SFX_CLICK
        jsr sfx_play
        jmp reading_start

title_draw:
        lda #0
        sta dirty
        lda #BG_TITLE
        jsr bg_draw
        lda #<title_buttons
        ldx #>title_buttons
        jsr buttons_draw
        ldx hover_btn                   ; what the button does, or the invitation
        cpx #5
        bcc +
        ldx #5
+       lda #188
        sta ftext_y
        lda #COL_LAVENDER
        sta ftext_col
        lda #COL_SHADOW
        sta ftext_shadow
        lda title_desc_hi,x
        pha
        lda title_desc_lo,x
        plx
        jsr ftext_centre
        jmp present

set_rev_label:
        ldx #0
        lda reversals
        beq +
        ldx #4
+       ldy #0
-       lda _onoff,x
        sta rev_label + 10,y
        inx
        iny
        cpy #4
        bne -
        rts
_onoff: .text "OFF", 0, "ON", 0, 0

title_buttons:
        .byte 5
        #BTN 104,  84, 112, 0, sn_one
        #BTN 104,  99, 112, 1, sn_three
        #BTN 104, 114, 112, 2, sn_horse
        #BTN 104, 129, 112, 3, sn_celtic
        #BTN 104, 147, 112, B_REVERSALS, rev_label
rev_label:      .text "REVERSALS ON", 0, 0

title_desc_lo:  .byte <td0, <td1, <td2, <td3, <td4, <td5
title_desc_hi:  .byte >td0, >td1, >td2, >td3, >td4, >td5
td0:            .null "ONE CARD TO LIGHT YOUR DAY"
td1:            .null "PAST, PRESENT AND FUTURE"
td2:            .null "SEVEN CARDS TO ANSWER A PROBLEM"
td3:            .null "THE ANCIENT TEN CARD READING"
td4:            .null "MAY THE CARDS FALL UPSIDE DOWN?"
td5:            .null "CHOOSE YOUR SPREAD... IF YOU DARE"

;---------------------------------------------------------------------------------------
; the reading table
;---------------------------------------------------------------------------------------
rd_n:           .byte 0                 ; cards in the spread
rd_big:         .byte 0                 ; big faces (else thumbnails)
rd_rot:         .byte 0                 ; the card lying across ($ff = none)
rd_first:       .byte 0                 ; its first pos_* entry
rd_stat_y:      .byte 0
rd_centre:      .byte 0
rd_label:       .byte 0
rd_state:       .byte 0
rd_card:        .fill 10                ; card ids
rd_rev:         .fill 10                ; 1 = reversed
rd_cs:          .fill 10                ; CS_*
rd_anim:        .fill 10                ; flip frame (negative = waiting to start)
deck_x:         .word 0
deck_y:         .byte 0
deal_i:         .byte 0
deal_t:         .byte 0
shuf_t:         .byte 0
hover_card:     .byte $ff
hover_deck:     .byte 0
deck:           .fill N_CARDS

reading_start:
        ldx spread
        lda sp_count,x
        sta rd_n
        lda sp_big,x
        sta rd_big
        lda sp_rot,x
        sta rd_rot
        lda sp_first,x
        sta rd_first
        lda sp_stat_y,x
        sta rd_stat_y
        lda sp_centre,x
        sta rd_centre
        lda sp_label,x
        sta rd_label
        lda sp_deck_y,x
        sta deck_y
        txa
        asl
        tay
        lda sp_deck_x,y
        sta deck_x
        lda sp_deck_x+1,y
        sta deck_x+1
        ldx #9
        lda #CS_NONE
-       sta rd_cs,x
        dex
        bpl -
        lda #RS_WAIT
        sta rd_state
        lda #0
        sta deal_i
        sta deal_t
        sta shuf_t
reading_resume:
        #RESET_STACK
        jsr fade_out
        lda #BG_TABLE
        sta cur_screen
        lda #$ff
        sta hover_btn
        sta hover_card
        lda #0
        sta hover_deck
        jsr rd_draw
        jsr fade_in
_loop:  jsr frame_input
        jsr rd_logic
        lda dirty
        beq +
        jsr rd_draw
        bra _loop
+       jsr wait_frame
        bra _loop

rd_logic:
        jsr rd_hover
        lda rd_state
        cmp #RS_WAIT
        beq _wait
        cmp #RS_SHUFFLE
        beq _shuffle
        cmp #RS_DEAL
        beq _deal
        jmp rd_play
_wait:  lda mouse_left_click
        beq _out
        lda hover_deck
        bne _go
        lda hover_btn
        cmp #B_BACK
        bne _out
        lda #SFX_CLICK
        jsr sfx_play
        jmp title_screen
_go:    lda #RS_SHUFFLE
        sta rd_state
        lda #0
        sta shuf_t
        sta hover_deck
        lda #$ff
        sta hover_btn
        lda #1
        sta dirty
_out:   rts
_shuffle:
        lda #1
        sta dirty
        inc shuf_t
        lda shuf_t                      ; riffle noise while the halves close up
        and #31
        cmp #10
        bcc +
        cmp #20
        bcs +
        and #1
        bne +
        lda #SFX_RIFFLE
        jsr sfx_play
+       lda shuf_t
        cmp #SHUF_N
        bne _out
        jsr shuffle_deck
        jsr prep_all
        lda #RS_DEAL
        sta rd_state
        lda #0
        sta deal_i
        sta deal_t
        rts
_deal:  lda #1
        sta dirty
        lda deal_t
        bne +
        lda #SFX_DEAL
        jsr sfx_play
+       inc deal_t
        lda deal_t
        cmp #DEAL_N
        bne _out
        ldx deal_i                      ; landed
        lda #CS_DOWN
        sta rd_cs,x
        lda #0
        sta deal_t
        inc deal_i
        lda deal_i
        cmp rd_n
        bne _out
        lda #RS_PLAY
        sta rd_state
        rts

rd_play:
        ldx #0                          ; cards turning over
        lda dbg_hold                    ; (test harness: freeze them mid-turn)
        beq _f
        inc dirty
        bra _clk
_f:     lda rd_cs,x
        cmp #CS_FLIP
        bne _n
        lda #1
        sta dirty
        inc rd_anim,x
        lda rd_anim,x
        bmi _n                          ; still waiting its turn
        bne +
        phx
        lda #SFX_FLIP
        jsr sfx_play
        plx
        bra _n
+       cmp #FLIP_N / 2                 ; the face shows: a major arcanum tolls the bell
        bne +
        lda rd_card,x
        cmp #22
        bcs _n
        phx
        lda #SFX_TOLL
        jsr sfx_play
        plx
        bra _n
+       cmp #FLIP_N
        bcc _n
        lda #CS_UP
        sta rd_cs,x
_n:     inx
        cpx rd_n
        bne _f
_clk:   lda mouse_left_click
        beq _out
        ldx hover_card
        bmi _btns
        lda rd_cs,x
        cmp #CS_DOWN
        bne +
        lda #CS_FLIP
        sta rd_cs,x
        lda #$ff
        sta rd_anim,x
        lda #1
        sta dirty
        rts
+       cmp #CS_UP
        bne _out
        stx det_i
        jmp detail_screen
_btns:  lda hover_btn
        cmp #B_REVEAL
        bne +
        jmp reveal_all
+       cmp #B_NEW
        bne _out
        lda #SFX_CLICK
        jsr sfx_play
        jmp title_screen
_out:   rts

; every face-down card turns, one after another
reveal_all:
        ldy #0                          ; delay so far
        ldx #0
_r:     lda rd_cs,x
        cmp #CS_DOWN
        bne _n
        lda #CS_FLIP
        sta rd_cs,x
        tya
        eor #$ff                        ; -(delay) - 1
        sta rd_anim,x
        tya
        clc
        adc #5
        tay
_n:     inx
        cpx rd_n
        bne _r
        lda #1
        sta dirty
        rts

; ---- what the mouse is over ----
nh_card:        .byte 0
nh_deck:        .byte 0
nh_btn:         .byte 0
hv_i:           .byte 0
rd_hover:
        lda #$ff
        sta nh_card
        sta nh_btn
        lda #0
        sta nh_deck
        lda rd_state
        cmp #RS_WAIT
        bne _play
        jsr deck_box
        jsr mouse_in_box
        bcc +
        inc nh_deck
+       lda #<rd_btn_wait
        ldx #>rd_btn_wait
        jsr buttons_find
        sta nh_btn
        bra _cmp
_play:  cmp #RS_PLAY
        bne _cmp
        ldx rd_n                        ; the top card first (the crossing card is above)
        dex
_c:     stx hv_i
        lda rd_cs,x
        beq _skip
        jsr card_box
        jsr mouse_in_box
        bcs _hit
_skip:  ldx hv_i
        dex
        bpl _c
        bra _btn
_hit:   lda hv_i
        sta nh_card
_btn:   lda #<rd_btn_play
        ldx #>rd_btn_play
        jsr buttons_find
        sta nh_btn
_cmp:   lda nh_card
        cmp hover_card
        bne _new
        lda nh_deck
        cmp hover_deck
        bne _new
        lda nh_btn
        cmp hover_btn
        bne _new
        rts
_new:   lda nh_card
        sta hover_card
        lda nh_deck
        sta hover_deck
        lda nh_btn
        sta hover_btn
        lda #1
        sta dirty
        rts

; ---- boxes ----
bx:             .word 0
by:             .byte 0
bw:             .byte 0
bh:             .byte 0
cb_off:         .byte 0                 ; card_box: the card's offset in `positions`

; X = card index -> its box as it lies (X kept)
card_box:
        txa
        clc
        adc rd_first
        sta tmp0
        asl                             ; * 7
        asl
        asl
        sec
        sbc tmp0
        tay
        sty cb_off
        lda positions,y
        sta bx
        lda positions+1,y
        sta bx+1
        lda positions+2,y
        sta by
        lda rd_big
        beq +
        lda #BIG_W
        sta bw
        lda #BIG_H
        sta bh
        rts
+       cpx rd_rot
        bne +
        lda #TH_H
        sta bw
        lda #TH_W
        sta bh
        rts
+       lda #TH_W
        sta bw
        lda #TH_H
        sta bh
        rts

deck_box:
        lda deck_x
        sta bx
        lda deck_x+1
        sta bx+1
        lda deck_y
        sta by
        lda rd_big
        beq +
        lda #BIG_W
        sta bw
        lda #BIG_H
        sta bh
        rts
+       lda #TH_W
        sta bw
        lda #TH_H
        sta bh
        rts

; carry set when the mouse is inside bx, by, bw, bh
mouse_in_box:
        sec
        lda mouse_x
        sbc bx
        sta tmp0
        lda mouse_x+1
        sbc bx+1
        bne _no
        lda tmp0
        cmp bw
        bcs _no
        sec
        lda mouse_y
        sbc by
        bcc _no
        cmp bh
        bcs _no
        sec
        rts
_no:    clc
        rts

; ---- drawing ----
dr_i:           .byte 0
dc_i:           .byte 0
rd_draw:
        lda #0
        sta dirty
        lda #BG_TABLE
        jsr bg_draw
        ldx #0                          ; empty places, names under big cards
_s:     stx dr_i
        lda rd_cs,x
        bne +
        jsr card_box
        jsr spot_outline
+       lda rd_label
        beq +
        ldx dr_i
        jsr card_label
+       ldx dr_i
        inx
        cpx rd_n
        bne _s
        lda rd_state
        cmp #RS_PLAY
        beq +
        jsr draw_deck
+       ldx #0                          ; the cards on the table
_c:     stx dr_i
        lda rd_cs,x
        beq +
        jsr draw_card
+       ldx dr_i
        inx
        cpx rd_n
        bne _c
        lda rd_state
        cmp #RS_DEAL
        bne +
        jsr draw_flying
+       jsr draw_hover
        jsr rd_status
        lda rd_state
        cmp #RS_WAIT
        bne +
        lda #<rd_btn_wait
        ldx #>rd_btn_wait
        jsr buttons_draw
        bra _done
+       cmp #RS_PLAY
        bne _done
        lda #<rd_btn_play
        ldx #>rd_btn_play
        jsr buttons_draw
_done:  jmp present

rd_btn_wait:
        .byte 1
        #BTN 124, 187, 72, B_BACK, s_back
rd_btn_play:
        .byte 2
        #BTN  56, 187, 100, B_REVEAL, s_reveal
        #BTN 164, 187, 104, B_NEW, s_new
s_back:         .null "BACK"
s_reveal:       .null "REVEAL ALL"
s_new:          .null "NEW READING"

; a dim outline where a card will land
spot_outline:
        sec
        lda bx
        sbc #1
        sta draw_x0
        lda bx+1
        sbc #0
        sta draw_x0+1
        lda by
        beq +
        dec a
+       sta draw_y0
        lda bw
        clc
        adc #2
        sta draw_w
        lda #0
        sta draw_w+1
        lda bh
        clc
        adc #2
        sta draw_h
        lda #COL_DKPURPLE
        jmp rect_outline

; X = card: its position's name centred under it
card_label:
        jsr card_box
        lda bw
        lsr
        clc
        adc bx
        sta tc_x
        lda bx+1
        adc #0
        sta tc_x+1
        lda by
        clc
        adc bh
        adc #2
        sta ftext_y
        lda #COL_LAVENDER
        sta ftext_col
        lda #COL_SHADOW
        sta ftext_shadow
        ldy cb_off
        lda positions+4,y
        tax
        lda positions+3,y
        jmp text_centre_at

; card back / face sources for card dc_i (big, turned or thumbnail)
back_src:
        lda rd_big
        beq +
        lda #<BACK_BIG
        ldx #>BACK_BIG
        bra _set
+       lda dc_i
        cmp rd_rot
        bne +
        lda #<BACK_ROT
        ldx #>BACK_ROT
        bra _set
+       lda #<BACK_TH
        ldx #>BACK_TH
_set:   sta cd_src
        stx cd_src+1
        lda #`BACK_BIG
        sta cd_src+2
        rts
face_src:
        ldx dc_i
        lda rd_big
        beq +
        lda #0
        sta cd_src
        lda big_hi,x
        sta cd_src+1
        lda #`SLOT_BIG
        sta cd_src+2
        rts
+       cpx rd_rot
        bne +
        lda #<SLOT_ROT
        sta cd_src
        lda #>SLOT_ROT
        sta cd_src+1
        lda #`SLOT_ROT
        sta cd_src+2
        rts
+       lda th_lo,x
        sta cd_src
        lda th_hi,x
        sta cd_src+1
        lda #`SLOT_TH
        sta cd_src+2
        rts
big_hi:         .byte >(range(3) * $4000)
th_lo:          .byte <(SLOT_TH + range(10) * $600)
th_hi:          .byte >(SLOT_TH + range(10) * $600)
flip_k:         .byte 8, 7, 5, 3, 2, 1, 1, 2, 3, 5, 7, 8    ; width in eighths, per flip frame

; box -> card_draw's position and size, full width
box_to_cd:
        lda bx
        sta cd_x
        lda bx+1
        sta cd_x+1
        lda by
        sta cd_y
        lda bw
        sta cd_w
        sta cd_dw
        lda bh
        sta cd_h
        rts

; X = card: draw it as it lies (back, face, or squeezed mid-flip)
draw_card:
        stx dc_i
        jsr card_box
        jsr box_to_cd
        ldx dc_i
        lda rd_cs,x
        cmp #CS_UP
        beq _face
        cmp #CS_FLIP
        bne _back
        lda rd_anim,x
        bmi _back
        tay
        lda flip_k,y                    ; width = w * k / 8 (at least 1)
        sta MULTINA
        lda bw
        sta MULTINB
        lda #0
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        lda MULTOUT+1
        sta tmp1
        lda MULTOUT
        lsr tmp1
        ror
        lsr tmp1
        ror
        lsr tmp1
        ror
        bne +
        lda #1
+       sta cd_dw
        cpy #FLIP_N / 2
        bcs _face
_back:  jsr back_src
        jmp card_draw
_face:  jsr face_src
        jmp card_draw

; the deck: a little stack, or two halves riffling
dd_k:           .byte 0
dd_off:         .byte 0
dd_lx:          .word 0
dd_rx:          .word 0
deck_size:
        lda #$fe
        sta dc_i                        ; (not the turned card, nor "none" = $ff)
        jsr back_src
        jsr deck_box
        jmp box_to_cd
draw_deck:
        jsr deck_size
        lda rd_state
        cmp #RS_SHUFFLE
        beq _shuf
        ldx #2
-       stx dd_k
        clc
        lda deck_x
        adc dd_k
        sta cd_x
        lda deck_x+1
        adc #0
        sta cd_x+1
        clc
        lda deck_y
        adc dd_k
        sta cd_y
        jsr card_draw
        ldx dd_k
        dex
        bpl -
        rts
_shuf:  lda shuf_t                      ; 0-9 apart, 10-19 together again, then rest
        and #31
        cmp #10
        bcs +
        asl
        bra _off
+       cmp #20
        bcs +
        sta tmp0
        lda #20
        sec
        sbc tmp0
        asl
        bra _off
+       lda #0
_off:   sta dd_off
        sec
        lda deck_x
        sbc dd_off
        sta dd_lx
        lda deck_x+1
        sbc #0
        sta dd_lx+1
        clc
        lda deck_x
        adc dd_off
        sta dd_rx
        lda deck_x+1
        adc #0
        sta dd_rx+1
        ldx #1                          ; left half: two cards
-       stx dd_k
        clc
        lda dd_lx
        adc dd_k
        sta cd_x
        lda dd_lx+1
        adc #0
        sta cd_x+1
        clc
        lda deck_y
        adc dd_k
        sta cd_y
        jsr card_draw
        ldx dd_k
        dex
        bpl -
        clc                             ; right half, its top card hopping
        lda dd_rx
        adc #1
        sta cd_x
        lda dd_rx+1
        adc #0
        sta cd_x+1
        lda deck_y
        inc a
        sta cd_y
        jsr card_draw
        lda dd_rx
        sta cd_x
        lda dd_rx+1
        sta cd_x+1
        lda shuf_t
        and #2
        eor #2
        sta tmp0
        sec
        lda deck_y
        sbc tmp0
        sta cd_y
        jmp card_draw

; the card being dealt, between the deck and its place (upright until it lands)
draw_flying:
        jsr deck_size                   ; the back, upright (cd_w / cd_h)
        ldx deal_i
        jsr card_box
        lda bw                          ; target: the box's centre less half the card
        lsr
        sta tmp0
        lda cd_w
        lsr
        sta tmp1
        clc
        lda bx
        adc tmp0
        sta lb
        lda bx+1
        adc #0
        sta lb+1
        sec
        lda lb
        sbc tmp1
        sta lb
        lda lb+1
        sbc #0
        sta lb+1
        lda deck_x
        sta la
        lda deck_x+1
        sta la+1
        ldy deal_t
        lda ease,y
        sta le
        jsr lerp
        lda lr
        sta cd_x
        lda lr+1
        sta cd_x+1
        lda bh
        lsr
        sta tmp0
        lda cd_h
        lsr
        sta tmp1
        clc
        lda by
        adc tmp0
        sec
        sbc tmp1
        sta lb
        lda #0
        sta lb+1
        lda deck_y
        sta la
        lda #0
        sta la+1
        jsr lerp
        lda lr
        sta cd_y
        jmp card_draw
ease:           .byte 0, 41, 78, 112, 142, 169, 192, 212, 228, 240, 249, 254

; lr = la + (lb - la) * le / 256 (signed words)
la:             .word 0
lb:             .word 0
lr:             .word 0
le:             .byte 0
ld:             .word 0
lneg:           .byte 0
lerp:
        lda #0
        sta lneg
        sec
        lda lb
        sbc la
        sta ld
        lda lb+1
        sbc la+1
        sta ld+1
        bpl +
        inc lneg
        jsr _neg
+       lda ld
        sta MULTINA
        lda ld+1
        sta MULTINA+1
        lda le
        sta MULTINB
        lda #0
        sta MULTINA+2
        sta MULTINA+3
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        lda MULTOUT+1
        sta ld
        lda MULTOUT+2
        sta ld+1
        lda lneg
        beq +
        jsr _neg
+       clc
        lda la
        adc ld
        sta lr
        lda la+1
        adc ld+1
        sta lr+1
        rts
_neg:   sec
        lda #0
        sbc ld
        sta ld
        lda #0
        sbc ld+1
        sta ld+1
        rts

; a glowing frame round what the mouse is over
draw_hover:
        ldx hover_card
        bmi +
        jsr card_box
        bra _frame
+       lda hover_deck
        bne +
        rts
+       jsr deck_box
_frame: sec
        lda bx
        sbc #2
        sta draw_x0
        lda bx+1
        sbc #0
        sta draw_x0+1
        lda by
        sec
        sbc #2
        bcs +
        lda #0
+       sta draw_y0
        lda bw
        clc
        adc #4
        sta draw_w
        lda #0
        sta draw_w+1
        lda bh
        clc
        adc #4
        sta draw_h
        lda #COL_GLOW
        jmp rect_outline

; the two status lines
rd_status:
        lda rd_stat_y
        sta ftext_y
        jsr sb_clear
        ldx hover_card
        bmi _prompt
        txa                             ; "3. THE FOUNDATION"
        jsr card_box
        lda hover_card
        inc a
        jsr sb_dec
        lda #<s_dot
        ldx #>s_dot
        jsr sb_add
        ldy cb_off
        lda positions+4,y
        tax
        lda positions+3,y
        jsr sb_add
        lda #COL_LAVENDER
        jsr status_line
        jsr sb_clear
        ldx hover_card
        lda rd_cs,x
        cmp #CS_UP
        bne _desc
        lda rd_card,x                   ; the card's name
        tay
        lda card_name_hi,y
        tax
        lda card_name_lo,y
        jsr sb_add
        ldx hover_card
        lda rd_rev,x
        beq +
        lda #<s_rev
        ldx #>s_rev
        jsr sb_add
        lda #COL_RED
        jmp status_line
+       lda #COL_BONE
        jmp status_line
_desc:  ldy cb_off                      ; face down: what the position means
        lda positions+6,y
        tax
        lda positions+5,y
        jsr sb_add
        lda #COL_GREY
        jmp status_line
_prompt:
        ldx rd_state                    ; the prompts for this moment
        cpx #RS_WAIT
        bne +
        lda hover_deck
        beq +
        ldx #4                          ; over the deck
+       cpx #RS_PLAY
        bne +
        ldy #0                          ; all face up?
-       lda rd_cs,y
        cmp #CS_UP
        bne +
        iny
        cpy rd_n
        bne -
        ldx #5
+       stx pr_i
        lda prompt1_hi,x
        tax
        ldy pr_i
        lda prompt1_lo,y
        jsr sb_add
        lda #COL_LAVENDER
        jsr status_line
        jsr sb_clear
        ldy pr_i
        lda prompt2_hi,y
        tax
        lda prompt2_lo,y
        jsr sb_add
        lda #COL_BONE
        jmp status_line
pr_i:           .byte 0                 ; (not a tmp: text drawing uses them)
s_dot:          .null ". "
s_rev:          .null " - REVERSED"
prompt1_lo:     .byte <pa0, <pa1, <pa2, <pa3, <pa4, <pa5
prompt1_hi:     .byte >pa0, >pa1, >pa2, >pa3, >pa4, >pa5
prompt2_lo:     .byte <pb0, <pb1, <pb2, <pb3, <pb4, <pb5
prompt2_hi:     .byte >pb0, >pb1, >pb2, >pb3, >pb4, >pb5
pa0:            .null "FOCUS ON YOUR QUESTION..."
pb0:            .null "THEN CLICK THE DECK TO SHUFFLE"
pa1:            .null "THE CARDS ARE MIXED..."
pb1:            .null ""
pa2:            .null "AND THEY FALL WHERE THEY MAY"
pb2:            .null ""
pa3:            .null "THE SPIRITS ARE LISTENING"
pb3:            .null "CLICK A CARD TO TURN IT OVER"
pa4:            .null "THE DECK AWAITS YOUR TOUCH"
pb4:            .null "CLICK TO SHUFFLE"
pa5:            .null "YOUR READING IS COMPLETE"
pb5:            .null "CLICK A CARD TO READ ITS MEANING"

; A = colour: sb_buf on the status line at ftext_y, then down a line
status_line:
        sta ftext_col
        lda #COL_SHADOW
        sta ftext_shadow
        lda rd_centre
        beq +
        lda #<sb_buf
        ldx #>sb_buf
        jsr ftext_centre
        bra ++
+       lda #4
        sta ftext_x
        lda #0
        sta ftext_x+1
        lda #<sb_buf
        ldx #>sb_buf
        jsr ftext_draw
+       clc
        lda ftext_y
        adc #FTEXT_LINE_H
        sta ftext_y
        rts

; ---- shuffling and preparing the spread ----
sh_i:           .byte 0
shuffle_deck:
        jsr rand_seed_hw                ; (falls back to the time when there is no RNG)
        ldx #0
-       txa
        sta deck,x
        inx
        cpx #N_CARDS
        bne -
        lda #0
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        ldx #N_CARDS - 1                ; Fisher-Yates: swap i with j in 0..i
_s:     stx sh_i
        jsr rand8
        sta MULTINA
        txa
        inc a
        sta MULTINB
        ldy MULTOUT+1
        lda deck,x
        pha
        lda deck,y
        sta deck,x
        pla
        sta deck,y
        dex
        bne _s
        ldx #0                          ; the spread takes the top cards
-       lda deck,x
        sta rd_card,x
        lda #0
        sta rd_rev,x
        lda reversals
        beq +
        jsr rand8
        and #$80
        beq +
        lda #1
        sta rd_rev,x
+       inx
        cpx rd_n
        bne -
        rts

; A = 8 fresh bits (one rand call shifts the LFSR by one bit only; X, Y kept)
rand8:
        lda #8
        sta tmp3
-       jsr rand
        dec tmp3
        bne -
        rts

; every card's picture into its slot (faces turned when reversed; the crossing card turned)
pa_i:           .byte 0
prep_all:
        ldx #0
_p:     stx pa_i
        lda rd_card,x
        sta pc_id
        lda rd_rev,x
        sta x_rev
        lda rd_big
        sta pc_big
        beq _th
        lda #0
        sta pc_dst
        lda big_hi,x
        sta pc_dst+1
        lda #`SLOT_BIG
        sta pc_dst+2
        bra _go
_th:    lda th_lo,x
        sta pc_dst
        lda th_hi,x
        sta pc_dst+1
        lda #`SLOT_TH
        sta pc_dst+2
_go:    jsr prep_image
        ldx pa_i
        cpx rd_rot
        bne +
        lda th_hi,x
        pha
        lda th_lo,x
        plx
        jsr rotate_thumb
+       ldx pa_i
        inx
        cpx rd_n
        bne _p
        rts

;---------------------------------------------------------------------------------------
; the detail view: one card, large, with its meaning
;---------------------------------------------------------------------------------------
det_i:          .byte 0
txt_keys:       .word 0
txt_up:         .word 0
txt_rev:        .word 0
TEXT_BUF_N      = 1024                  ; (build_assets.py keeps records under this)
text_buf:       .fill TEXT_BUF_N

detail_screen:
        #RESET_STACK
        jsr fade_out
        ldx det_i
        lda #CS_UP                      ; (arriving with NEXT turns a card over)
        sta rd_cs,x
        lda rd_card,x
        sta pc_id
        lda rd_rev,x
        sta x_rev
        lda #1
        sta pc_big
        lda #<SLOT_DETAIL
        sta pc_dst
        lda #>SLOT_DETAIL
        sta pc_dst+1
        lda #`SLOT_DETAIL
        sta pc_dst+2
        jsr prep_image
        jsr load_text
        lda #$ff
        sta hover_btn
        jsr det_draw
        jsr fade_in
_loop:  jsr frame_input
        lda #<det_btns
        ldx #>det_btns
        jsr buttons_find
        cmp hover_btn
        beq +
        sta hover_btn
        lda #1
        sta dirty
+       lda mouse_right_click
        bne _back
        lda mouse_left_click
        beq _draw
        lda hover_btn
        cmp #B_BACK
        beq _back
        cmp #B_PREV
        bne +
        dec det_i
        bpl _again
        lda rd_n
        dec a
        sta det_i
        bra _again
+       cmp #B_NEXT
        bne _draw
        inc det_i
        lda det_i
        cmp rd_n
        bcc _again
        lda #0
        sta det_i
_again: lda #SFX_FLIP
        jsr sfx_play
        jmp detail_screen
_back:  lda #SFX_CLICK
        jsr sfx_play
        jmp reading_resume
_draw:  lda dirty
        beq +
        jsr det_draw
        bra _loop
+       jsr wait_frame
        bra _loop

det_btns:
        .byte 3
        #BTN 116, 187, 60, B_PREV, s_prev
        #BTN 182, 187, 60, B_NEXT, s_next
        #BTN 248, 187, 64, B_BACK, s_back
s_prev:         .null "< PREV"
s_next:         .null "NEXT >"

; the card's text record from attic -> text_buf: keywords, upright, reversed
load_text:
        ldx det_i
        ldy rd_card,x
        clc
        lda text_off_lo,y
        adc #<AT_TEXT
        sta ptr1
        lda text_off_hi,y
        adc #>AT_TEXT
        sta ptr1+1
        lda #`AT_TEXT
        adc #0
        sta ptr1+2
        lda #AT_TEXT >> 24
        sta ptr1+3
        lda #<text_buf
        sta ptr2
        lda #>text_buf
        sta ptr2+1
        lda #0
        sta ptr2+2
        sta ptr2+3
        lda #<TEXT_BUF_N
        sta tmp5
        lda #>TEXT_BUF_N
        sta tmp5+1
        jsr dma_copy_far
        lda #<text_buf
        sta txt_keys
        sta sptr
        lda #>text_buf
        sta txt_keys+1
        sta sptr+1
        jsr _skip
        lda sptr
        sta txt_up
        lda sptr+1
        sta txt_up+1
        jsr _skip
        lda sptr
        sta txt_rev
        lda sptr+1
        sta txt_rev+1
        rts
_skip:  ldy #0                          ; sptr -> past the next 0
-       lda (sptr),y
        inw sptr
        cmp #0
        bne -
        rts

TX_X            = 114
det_draw:
        lda #0
        sta dirty
        lda #BG_TABLE
        jsr bg_draw
        lda #<108                       ; the panel
        sta draw_x0
        lda #0
        sta draw_x0+1
        sta draw_w+1
        lda #2
        sta draw_y0
        lda #210
        sta draw_w
        lda #181
        sta draw_h
        lda #COL_PANEL
        sta draw_col
        jsr draw_fill
        lda #COL_DIMGOLD
        jsr rect_outline
        lda #8                          ; the card in a gold frame
        sta draw_x0
        lda #22
        sta draw_y0
        lda #BIG_W + 4
        sta draw_w
        lda #BIG_H + 4
        sta draw_h
        lda #COL_GOLD
        jsr rect_outline
        lda #<SLOT_DETAIL
        sta cd_src
        lda #>SLOT_DETAIL
        sta cd_src+1
        lda #`SLOT_DETAIL
        sta cd_src+2
        lda #BIG_W
        sta cd_w
        sta cd_dw
        lda #BIG_H
        sta cd_h
        lda #10
        sta cd_x
        lda #0
        sta cd_x+1
        lda #24
        sta cd_y
        jsr card_draw
        lda #COL_SHADOW                 ; name
        sta ftext_shadow
        ldx det_i
        ldy rd_card,x
        lda card_name_hi,y
        tax
        lda card_name_lo,y
        ldy #8
        jsr _line_gold
        ldx det_i                       ; upright / reversed
        lda rd_rev,x
        beq +
        lda #COL_RED
        sta ftext_col
        lda #<s_reversed
        ldx #>s_reversed
        bra ++
+       lda #COL_GHOST
        sta ftext_col
        lda #<s_upright
        ldx #>s_upright
+       ldy #18
        jsr _line
        jsr sb_clear                    ; the position
        lda det_i
        inc a
        jsr sb_dec
        lda #<s_dot
        ldx #>s_dot
        jsr sb_add
        ldx det_i
        jsr card_box
        ldy cb_off
        lda positions+4,y
        tax
        lda positions+3,y
        jsr sb_add
        lda #COL_LAVENDER
        sta ftext_col
        lda #<sb_buf
        ldx #>sb_buf
        ldy #30
        jsr _line
        lda #COL_GREY
        sta ftext_col
        ldy cb_off
        lda positions+6,y
        tax
        lda positions+5,y
        ldy #39
        jsr _line
        lda #COL_PURPLE                 ; keywords
        sta ftext_col
        lda txt_keys
        ldx txt_keys+1
        ldy #52
        jsr _line
        lda #COL_BONE                   ; the meaning, upright or reversed
        sta ftext_col
        ldx det_i
        lda rd_rev,x
        bne +
        lda txt_up
        ldx txt_up+1
        bra ++
+       lda txt_rev
        ldx txt_rev+1
+       ldy #74
        jsr _line
        lda #<det_btns
        ldx #>det_btns
        jsr buttons_draw
        jmp present
_line_gold:
        pha
        lda #COL_GOLD
        sta ftext_col
        pla
; A/X = text at (TX_X, Y)
_line:  sty ftext_y
        ldy #<TX_X
        sty ftext_x
        ldy #0
        sty ftext_x+1
        jmp ftext_draw
s_upright:      .null "UPRIGHT"
s_reversed:     .null "REVERSED"
