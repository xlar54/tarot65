;=======================================================================================
; gfx.asm - card pictures and screen furniture.
;
;   expand4        4 bits a pixel -> 8 (through xlut), forwards or backwards (a backwards
;                  column-major picture is the picture turned 180 degrees: a reversed card)
;   prep_image     one card (pc_id, pc_big, x_rev) from attic into chip RAM at pc_dst
;   rotate_thumb   a thumbnail turned 90 degrees clockwise (the Celtic Cross's crossing card)
;   card_draw      a column-major picture squeezed to cd_dw columns about its centre (the
;                  flip); colour 0 transparent
;   bg_draw        A = BG_TITLE / BG_TABLE: the 8-bit background into the back buffer
;   buttons_draw / buttons_find   A/X = button list (see BTN)
;   text helpers   strlen, text_centre_at, the string builder sb_*
;=======================================================================================

; chip-RAM pictures (the ROM area, unprotected at boot). None crosses a 64 KB bank.
SLOT_BIG        = $20000                ; + i * $4000, i = 0-2 (one- and three-card spreads)
SLOT_DETAIL     = $2C000                ; the detail view's card
SLOT_TH         = $30000                ; + i * $600, i = 0-9
SLOT_ROT        = $34000                ; the crossing card, turned
BACK_BIG        = $35000                ; the card backs (8 bpp, from AT_BACKS)
BACK_TH         = $39000
BACK_ROT        = $39800
STAGE4          = $3A000                ; one 4 bpp card on its way from attic

BG_TITLE        = 0
BG_TABLE        = 1
BTN_H           = 12

xlut:           .fill 16                ; nibble -> palette entry
x_rev:          .byte 0                 ; expand4 writes backwards
pc_id:          .byte 0                 ; prep_image: card id
pc_big:         .byte 0                 ;   1 = 88 x 152 face, 0 = 28 x 48 thumbnail
pc_dst:         .fill 3                 ;   chip-RAM address of the 8-bit picture
rt_x:           .byte 0

; ---- expand4: xcount bytes at [cptr] -> 2 * xcount pixels at [dptr] (x_rev: dptr is the
;      LAST pixel and the pixels go backwards) ----
expand4:
        ldz #0
        lda x_rev
        bne _rev
_fwd:   lda [cptr],z
        tay
        lsr
        lsr
        lsr
        lsr
        tax
        lda xlut,x
        sta [dptr],z
        inw dptr
        tya
        and #$0f
        tax
        lda xlut,x
        sta [dptr],z
        inw dptr
        inw cptr
        dew xcount
        lda xcount
        ora xcount+1
        bne _fwd
        rts
_rev:   lda [cptr],z
        tay
        lsr
        lsr
        lsr
        lsr
        tax
        lda xlut,x
        sta [dptr],z
        dew dptr
        tya
        and #$0f
        tax
        lda xlut,x
        sta [dptr],z
        dew dptr
        inw cptr
        dew xcount
        lda xcount
        ora xcount+1
        bne _rev
        rts

; ---- prep_image: card pc_id (face if pc_big, else thumbnail) -> pc_dst, turned 180
;      degrees when x_rev ----
prep_image:
        lda pc_id                       ; its 16 colours
        sta sptr
        lda #0
        sta sptr+1
        ldx #4
-       asl sptr
        rol sptr+1
        dex
        bne -
        clc
        lda sptr
        adc #<card_lut
        sta sptr
        lda sptr+1
        adc #>card_lut
        sta sptr+1
        ldy #15
-       lda (sptr),y
        sta xlut,y
        dey
        bpl -
        ; attic address = base + id * size
        lda #0
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        sta MULTINB+2
        sta MULTINB+3
        lda pc_id
        sta MULTINA
        ldx pc_big
        lda _size_lo,x
        sta MULTINB
        sta tmp5
        sta xcount
        lda _size_hi,x
        sta MULTINB+1
        sta tmp5+1
        sta xcount+1
        clc
        lda MULTOUT
        adc _base0,x
        sta ptr1
        lda MULTOUT+1
        adc _base1,x
        sta ptr1+1
        lda MULTOUT+2
        adc _base2,x
        sta ptr1+2
        lda #AT_CARDS >> 24
        sta ptr1+3
        lda #<STAGE4
        sta ptr2
        sta cptr
        lda #>STAGE4
        sta ptr2+1
        sta cptr+1
        lda #`STAGE4
        sta ptr2+2
        sta cptr+2
        lda #0
        sta ptr2+3
        sta cptr+3
        jsr dma_copy_far
        ; destination (the last pixel when backwards)
        lda pc_dst
        sta dptr
        lda pc_dst+1
        sta dptr+1
        lda pc_dst+2
        sta dptr+2
        lda #0
        sta dptr+3
        lda x_rev
        beq +
        ldx pc_big
        clc
        lda dptr
        adc _last_lo,x
        sta dptr
        lda dptr+1
        adc _last_hi,x
        sta dptr+1
+       jmp expand4
_size_lo:       .byte <TH_BYTES, <BIG_BYTES
_size_hi:       .byte >TH_BYTES, >BIG_BYTES
_last_lo:       .byte <(TH_W * TH_H - 1), <(BIG_W * BIG_H - 1)
_last_hi:       .byte >(TH_W * TH_H - 1), >(BIG_W * BIG_H - 1)
_base0:         .byte <AT_THUMBS, <AT_CARDS
_base1:         .byte >AT_THUMBS, >AT_CARDS
_base2:         .byte `AT_THUMBS, `AT_CARDS

; ---- rotate_thumb: the 28 x 48 picture at cptr (bank-3 address in A/X lo/hi) -> 48 x 28
;      at SLOT_ROT, turned clockwise: new(x', y') = old(y', 47 - x') ----
rotate_thumb:
        sta _src
        stx _src+1
        lda #<SLOT_ROT
        sta dptr
        lda #>SLOT_ROT
        sta dptr+1
        lda #`SLOT_ROT
        sta dptr+2
        sta cptr+2
        lda #0
        sta dptr+3
        sta cptr+3
        sta rt_x
        ldz #0
_col:   sec                             ; cptr = old column 0, row 47 - x'
        lda #TH_H - 1
        sbc rt_x
        clc
        adc _src
        sta cptr
        lda _src+1
        adc #0
        sta cptr+1
        ldx #TH_W
_row:   lda [cptr],z
        sta [dptr],z
        inw dptr
        clc
        lda cptr
        adc #TH_H
        sta cptr
        bcc +
        inc cptr+1
+       dex
        bne _row
        inc rt_x
        lda rt_x
        cmp #TH_H
        bne _col
        rts
_src:   .word 0

; ---- card_draw ----
cd_src:         .fill 3                 ; chip-RAM address of column 0
cd_w:           .byte 0                 ; picture size
cd_h:           .byte 0
cd_x:           .word 0                 ; where the full-width picture's left edge would be
cd_y:           .byte 0
cd_dw:          .byte 0                 ; columns to draw (cd_w = all; fewer = squeezed)
cd_cx:          .word 0
cd_yo:          .word 0
cd_col:         .byte 0
cd_r:           .byte 0
cd_n:           .byte 0

card_draw:
        lda cd_dw
        bne +
        rts
+       sec                             ; centred: x += (w - dw) / 2
        lda cd_w
        sbc cd_dw
        lsr
        clc
        adc cd_x
        sta cd_cx
        lda cd_x+1
        adc #0
        sta cd_cx+1
        lda cd_y                        ; y * 8: rows are 8 bytes apart in a char column
        sta cd_yo
        lda #0
        sta cd_yo+1
        ldx #3
-       asl cd_yo
        rol cd_yo+1
        dex
        bne -
        lda fb_bank
        sta dmab_dst_bank
        lda cd_h
        sta dmab_count
        sta MULTINB
        lda #0
        sta dmab_count+1
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        sta cd_col
        sta cd_r
        lda cd_src+2
        sta dmab_src_bank
        lda cd_dw
        sta cd_n
_col:   lda cd_col                      ; source column cd_col
        sta MULTINA
        clc
        lda MULTOUT
        adc cd_src
        sta dmab_src
        lda MULTOUT+1
        adc cd_src+1
        sta dmab_src+1
        ldx #0                          ; char column (x >> 3), +32 from x = 256
        lda cd_cx+1
        beq +
        ldx #32
+       stx tmp0
        lda cd_cx
        lsr
        lsr
        lsr
        clc
        adc tmp0
        tay
        lda cd_cx
        and #7
        ora cd_yo
        clc
        adc fbcol_lo,y
        sta dmab_dst
        lda cd_yo+1
        adc fbcol_hi,y
        sta dmab_dst+1
        #DMA_RUN dma_blit
        inc cd_cx
        bne +
        inc cd_cx+1
+       clc                             ; next source column: col = j * w / dw
        lda cd_r
        adc cd_w
-       cmp cd_dw
        bcc +
        sbc cd_dw
        inc cd_col
        bra -
+       sta cd_r
        dec cd_n
        bne _col
        rts

; ---- bg_draw: A = BG_TITLE / BG_TABLE ----
bg_draw:
        tax
        lda #<AT_TITLE8
        sta ptr1
        lda #>AT_TITLE8
        sta ptr1+1
        lda bg_banks,x
        sta ptr1+2
        lda #AT_TITLE8 >> 24
        sta ptr1+3
        lda #0
        sta ptr2
        sta ptr2+1
        sta ptr2+3
        lda fb_bank
        sta ptr2+2
        lda #<FB_SIZE
        sta tmp5
        lda #>FB_SIZE
        sta tmp5+1
        jmp dma_copy_far
bg_banks:       .byte `AT_TITLE8, `AT_TABLE8
        .cerror (AT_TITLE8 & $ffff) != 0 || (AT_TABLE8 & $ffff) != 0, "backgrounds must be 64 KB aligned"

; at boot: the 4 bpp backgrounds -> 8 bpp in attic (through framebuffer A)
expand_backgrounds:
        ldx #0
        jsr _one
        ldx #1
_one:   stx _which
        txa                             ; colours base + n
        asl
        asl
        asl
        asl
        clc
        adc #TITLE_BASE
        ldy #0
-       sta xlut,y
        inc a
        iny
        cpy #16
        bne -
        ldx _which
        lda #<AT_TITLE4
        sta cptr
        lda _src_hi,x
        sta cptr+1
        lda #`AT_TITLE4
        sta cptr+2
        lda #AT_TITLE4 >> 24
        sta cptr+3
        lda #<FB0
        sta dptr
        sta ptr1
        lda #>FB0
        sta dptr+1
        sta ptr1+1
        lda #`FB0
        sta dptr+2
        sta ptr1+2
        lda #0
        sta dptr+3
        sta ptr1+3
        sta x_rev
        lda #<(FB_SIZE / 2)
        sta xcount
        lda #>(FB_SIZE / 2)
        sta xcount+1
        jsr expand4
        ldx _which
        lda #0
        sta ptr2
        sta ptr2+1
        lda bg_banks,x
        sta ptr2+2
        lda #AT_TITLE8 >> 24
        sta ptr2+3
        lda #<FB_SIZE
        sta tmp5
        lda #>FB_SIZE
        sta tmp5+1
        jmp dma_copy_far
_which: .byte 0
_src_hi: .byte >AT_TITLE4, >AT_TABLE4
        .cerror (AT_TITLE4 & $ff) != 0 || ((AT_TITLE4 ^ AT_TABLE4) & $fff0000) != 0, "expand_backgrounds expects both 4 bpp backgrounds in one bank"
        .cerror TABLE_BASE != TITLE_BASE + 16, "the table's colours follow the title's"

; at boot: the three card backs from attic to chip RAM
load_backs:
        lda #<AT_BACKS
        sta ptr1
        lda #>AT_BACKS
        sta ptr1+1
        lda #`AT_BACKS
        sta ptr1+2
        lda #AT_BACKS >> 24
        sta ptr1+3
        ldx #0
_one:   lda _dst_lo,x
        sta ptr2
        lda _dst_hi,x
        sta ptr2+1
        lda #`BACK_BIG
        sta ptr2+2
        lda #0
        sta ptr2+3
        lda _len_lo,x
        sta tmp5
        lda _len_hi,x
        sta tmp5+1
        phx
        jsr dma_copy_far
        plx
        clc                             ; next source (dma_copy_far moves ptr1 only on a split)
        lda ptr1
        adc _len_lo,x
        sta ptr1
        lda ptr1+1
        adc _len_hi,x
        sta ptr1+1
        inx
        cpx #3
        bne _one
        rts
_dst_lo: .byte <BACK_BIG, <BACK_TH, <BACK_ROT
_dst_hi: .byte >BACK_BIG, >BACK_TH, >BACK_ROT
_len_lo: .byte <(BIG_W * BIG_H), <(TH_W * TH_H), <(TH_W * TH_H)
_len_hi: .byte >(BIG_W * BIG_H), >(TH_W * TH_H), >(TH_W * TH_H)
        .cerror (`BACK_BIG) != (`BACK_ROT), "card backs in one bank"
        .cerror (AT_BACKS & $ffff) != 0, "AT_BACKS 64 KB aligned (no carries past 16 bits)"

; ---- rectangles ----
; rect_xywh: draw_x0 / draw_y0 / draw_w / draw_h set; A = colour: outline
rect_outline:
        sta draw_col
        jmp draw_rect

; ---- buttons ----
; a list: count, then BTN entries
BTN     .macro bx, by, bw, id, label
        .word \bx
        .byte \by, \bw, \id
        .word \label
        .endmacro
BTN_SIZE        = 7

hover_btn:      .byte $ff
bt_n:           .byte 0
bt_x:           .word 0
bt_y:           .byte 0
bt_w:           .byte 0
bt_id:          .byte 0
bt_lab:         .word 0

; A/X = list
buttons_draw:
        sta blist
        stx blist+1
        ldy #0
        lda (blist),y
        beq _out
        sta bt_n
        inw blist
_btn:   jsr bt_fetch
        lda bt_x
        sta draw_x0
        lda bt_x+1
        sta draw_x0+1
        lda bt_y
        sta draw_y0
        lda bt_w
        sta draw_w
        lda #0
        sta draw_w+1
        lda #BTN_H
        sta draw_h
        ldx #0                          ; X = 1 when hovered
        lda bt_id
        cmp hover_btn
        bne +
        inx
+       phx
        lda _fill,x
        sta draw_col
        jsr draw_fill
        plx
        phx
        lda _edge,x
        jsr rect_outline
        lda bt_lab                      ; label centred
        ldx bt_lab+1
        jsr strlen
        asl
        asl
        asl
        sta tmp0
        sec
        lda bt_w
        sbc tmp0
        lsr
        clc
        adc bt_x
        sta ftext_x
        lda bt_x+1
        adc #0
        sta ftext_x+1
        lda bt_y
        clc
        adc #2
        sta ftext_y
        plx
        lda _ink,x
        sta ftext_col
        lda #0
        sta ftext_shadow
        lda bt_lab
        ldx bt_lab+1
        jsr ftext_draw
        clc
        lda blist
        adc #BTN_SIZE
        sta blist
        bcc +
        inc blist+1
+       dec bt_n
        bne _btn
_out:   rts
_fill:  .byte COL_BTN, COL_BTNHI
_edge:  .byte COL_DIMGOLD, COL_GLOW
_ink:   .byte COL_BONE, COL_GLOW

; the entry at blist -> bt_*
bt_fetch:
        ldy #0
        lda (blist),y
        sta bt_x
        iny
        lda (blist),y
        sta bt_x+1
        iny
        lda (blist),y
        sta bt_y
        iny
        lda (blist),y
        sta bt_w
        iny
        lda (blist),y
        sta bt_id
        iny
        lda (blist),y
        sta bt_lab
        iny
        lda (blist),y
        sta bt_lab+1
        rts

; A/X = list -> A = id of the button under the mouse, or $ff
buttons_find:
        sta blist
        stx blist+1
        ldy #0
        lda (blist),y
        beq _none
        sta bt_n
        inw blist
_btn:   jsr bt_fetch
        sec                             ; tmp4 = mouse_x - x (16-bit): 0 <= it < w?
        lda mouse_x
        sbc bt_x
        sta tmp4
        lda mouse_x+1
        sbc bt_x+1
        bne _next
        lda tmp4
        cmp bt_w
        bcs _next
        sec
        lda mouse_y
        sbc bt_y
        bcc _next
        cmp #BTN_H
        bcs _next
        lda bt_id
        rts
_next:  clc
        lda blist
        adc #BTN_SIZE
        sta blist
        bcc +
        inc blist+1
+       dec bt_n
        bne _btn
_none:  lda #$ff
        rts

; ---- text ----
; A/X = string -> A = length
strlen:
        sta sptr
        stx sptr+1
        ldy #0
-       lda (sptr),y
        beq +
        iny
        bne -
+       tya
        rts

; A/X = one-line string, drawn centred on x = tc_x at ftext_y
tc_x:   .word 0
text_centre_at:
        pha
        phx
        jsr strlen
        asl
        asl                             ; len * 4
        sta tmp0
        sec
        lda tc_x
        sbc tmp0
        sta ftext_x
        lda tc_x+1
        sbc #0
        sta ftext_x+1
        plx
        pla
        jmp ftext_draw

; the string builder: sb_clear, sb_add (A/X string), sb_char (A), sb_dec (A = 0-99)
SB_MAX          = 47
sb_buf:         .fill SB_MAX + 1
sb_len:         .byte 0
sb_clear:
        lda #0
        sta sb_len
        sta sb_buf
        rts
sb_add:
        sta sptr
        stx sptr+1
        ldy #0
-       lda (sptr),y
        beq +
        jsr sb_char
        iny
        bne -
+       rts
sb_char:
        ldx sb_len
        cpx #SB_MAX
        bcs +
        sta sb_buf,x
        inx
        stx sb_len
        lda #0
        sta sb_buf,x
+       rts
sb_dec:
        ldx #0
-       cmp #10
        bcc +
        sbc #10
        inx
        bra -
+       pha
        txa
        beq +
        ora #'0'
        jsr sb_char
+       pla
        ora #'0'
        jmp sb_char
