;=======================================================================================
; Tarot 65 - Rider-Waite tarot readings on the MEGA65, by mouse.
;
; Boot: every asset file (gen/manifest.asm) goes into attic RAM through the KERNAL, then
; the machine is taken over: 320x200 Full Colour framebuffers (double-buffered), the
; mouse pointer is a 16-colour hardware sprite, SID effects, palette animation for the
; candle flames and glows. The screens are in screens.asm, the pictures in gfx.asm.
;=======================================================================================
        .cpu "45gs02"

        .include "platform.asm"
        .include "lib/zp.asm"
        .include "zp.asm"

        * = $2001                       ; BASIC stub: BANK 0 : SYS 8210
        .word (+), 2026
        .byte $fe, $02, $30
        .byte ':'
        .byte $9e
        .text "8210"
        .byte 0
+       .word 0

        * = $2012
entry:
        cld
        lda #0                          ; real RAM is random at power-on
        ldx #2
-       sta $00,x
        inx
        cpx #$90
        bne -
        sta BORDERCOL
        sta BACKCOL
        lda #<msg_boot
        ldy #>msg_boot
        jsr print
        lda #<boot_dot
        sta manifest_hook
        lda #>boot_dot
        sta manifest_hook+1
        jsr load_manifest
        bcc +
        lda #<msg_fail
        ldy #>msg_fail
        jsr print
-       bra -
+
        #TAKEOVER
        lda #$ff                        ; one palette bank for screen, sprites and edits
        sta VIC4_PALSEL
        jsr irq_install
        lda #<frame_irq
        sta irq_hook
        lda #>frame_irq
        sta irq_hook+1
        cli
        jsr copy_rom_font               ; (before the ROM area becomes picture RAM)
        jsr rom_unprotect
        jsr fcm_init
        lda #<palette_rgb
        sta pal_src
        lda #>palette_rgb
        sta pal_src+1
        lda #0                          ; all 256 entries
        sta pal_count
        jsr pal_set_level               ; black until the first fade in
        jsr hws_init
        ldx #0
        lda #<pointer_shape
        ldy #>pointer_shape
        jsr hws_shape
        jsr hws_full_colour
        jsr hws_on
        jsr mouse_init
        jsr sid_init
        jsr rand_seed_hw
        jsr expand_backgrounds
        jsr load_backs
        jsr set_rev_label
        jmp title_screen

boot_dot:
        lda #'.'
        jmp KERNAL_CHROUT
msg_boot:       .byte $93, $8e, $9c, 13
                .text "  TAROT 65", 13, 13
                .byte $9f
                .text "  SUMMONING THE SPIRITS", 0
msg_fail:       .byte 13, $1c
                .text "  THE SPIRITS ARE SILENT (DISK ERROR)", 0

frame_irq:
        jsr fcm_irq
        jmp sfx_frame

frames_drawn:   .byte 0                 ; +1 per picture shown (testing)
present:
        inc frames_drawn
        jmp fcm_present

fade_out:
        lda #10
        jmp pal_fade_out
fade_in:
        lda #10
        jmp pal_fade_in

;---------------------------------------------------------------------------------------
; once a frame: the mouse (and the test harness's), the pointer, palette effects
;---------------------------------------------------------------------------------------
dbg_mx:         .word 0                 ; test harness: dbg_cmd bit 0 = move to dbg_mx/my,
dbg_my:         .byte 0                 ;   bit 1 = left click, bit 2 = right click
dbg_cmd:        .byte 0
dbg_hold:       .byte 0                 ; test harness: 1 = card flips stand still
cur_screen:     .byte 0                 ; BG_TITLE / BG_TABLE: which palette effects run

frame_input:
        jsr mouse_poll
        lda dbg_cmd
        beq _place
        and #1
        beq +
        lda dbg_mx
        sta mouse_x
        lda dbg_mx+1
        sta mouse_x+1
        lda dbg_my
        sta mouse_y
+       lda dbg_cmd
        and #2
        beq +
        lda #1
        sta mouse_left_click
+       lda dbg_cmd
        and #4
        beq +
        lda #1
        sta mouse_right_click
+       lda #0
        sta dbg_cmd
_place: lda mouse_x
        sta hws_x
        lda mouse_x+1
        sta hws_x+1
        lda mouse_y
        sta hws_y
        lda #0
        sta hws_y+1
        ldx #0
        jsr hws_place
        jsr pal_animate
        jmp rand                        ; (stirred every frame: the reading depends on when)

; candle flames flicker, the title's red and the hover glow pulse, the table's ring glows
pa_t:           .byte 0
pa_lvl:         .byte 0
ps_e:           .byte 0
ps_r:           .byte 0
ps_g:           .byte 0
ps_b:           .byte 0
pal_animate:
        lda pal_level
        cmp #255
        bne _out                        ; (not while fading)
        inc pa_t
        lda pa_t
        lsr
        and #63
        tax
        lda pulse,x
        sta pa_lvl
        ldx #COL_GLOW
        lda #<glow_rgb
        ldy #>glow_rgb
        jsr pal_scaled
        lda cur_screen
        bne _table
        ldx #TITLE_RED_E
        lda #<title_red_rgb
        ldy #>title_red_rgb
        jsr pal_scaled
        lda frame_count
        and #3
        bne _out
        jsr rand
        ora #$a0
        sta pa_lvl
        ldx #TITLE_FLAME0
        lda #<flame_rgb
        ldy #>flame_rgb
        jsr pal_scaled
        ldx #TITLE_FLAME1
        lda #<flame_rgb + 3
        ldy #>flame_rgb + 3
        jsr pal_scaled
        ldx #TITLE_FLAME2
        lda #<flame_rgb + 6
        ldy #>flame_rgb + 6
        jmp pal_scaled
_out:   rts
_table: ldx #TABLE_GOLD_E
        lda #<ring_gold_rgb
        ldy #>ring_gold_rgb
        jmp pal_scaled
        .cerror TITLE_FLAME0 == 0 || TITLE_RED_E == 0 || TABLE_GOLD_E == 0, "an animated colour is missing from the art"

; X = palette entry, A/Y = its r, g, b: set it to those times pa_lvl / 256
pal_scaled:
        sta sptr
        sty sptr+1
        stx ps_e
        lda #0
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        lda pa_lvl
        sta MULTINB
        ldy #0
        lda (sptr),y
        sta MULTINA
        lda MULTOUT+1
        sta ps_r
        iny
        lda (sptr),y
        sta MULTINA
        lda MULTOUT+1
        sta ps_g
        iny
        lda (sptr),y
        sta MULTINA
        lda MULTOUT+1
        sta ps_b
        ldx ps_e
        ldy ps_g
        ldz ps_b
        lda ps_r
        jmp pal_set
glow_rgb:       .byte 255, 220, 120
pulse:          .byte 175,183,191,198,206,213,219,226,232,237,242,246,249,252,253,255
                .byte 255,255,253,252,249,246,242,237,232,226,219,213,206,198,191,183
                .byte 175,167,159,152,144,137,131,124,118,113,108,104,101,98,97,95
                .byte 95,95,97,98,101,104,108,113,118,124,131,137,144,152,159,167

; the C64 upper-case font (screen codes 0-63) from the ROM ($29000) into font8
copy_rom_font:
        lda #<$9000
        sta ptr0
        lda #>$9000
        sta ptr0+1
        lda #$02
        sta ptr0+2
        lda #0
        sta ptr0+3
        ldz #0
        ldx #0
-       lda [ptr0],z
        sta font8,x
        inw ptr0
        inx
        bne -
-       lda [ptr0],z
        sta font8+256,x
        inw ptr0
        inx
        bne -
        rts
font8:          .fill 512
FTEXT_FONT      = font8

;---------------------------------------------------------------------------------------
; sounds (lib/sid.asm with our own table)
;---------------------------------------------------------------------------------------
SFX_TABLES_OWN  = 1
SFX_FLIP        = 0
SFX_DEAL        = 1
SFX_RIFFLE      = 2
SFX_CLICK       = 3
SFX_TOLL        = 4
;               flip  deal  riffle click toll
sfx_voice:  .byte 0,    7,    7,    14,   14    ; voice register offset
sfx_wave:   .byte $81,  $81,  $81,  $11,  $11   ; waveform + gate
sfx_fhi:    .byte $30,  $50,  $70,  $28,  $0a   ; start pitch (high byte)
sfx_fstep:  .byte $fc,  $f6,  $00,  $00,  $00   ; signed slide per frame
sfx_len:    .byte 10,   6,    2,    3,    70    ; frames
sfx_ad:     .byte $06,  $04,  $01,  $02,  $0b
sfx_sr:     .byte $00,  $00,  $00,  $00,  $0b

        .include "screens.asm"
        .include "spreads.asm"
        .include "gfx.asm"

        .include "lib/system.asm"
        .include "lib/dma.asm"
        .include "lib/loader.asm"
        .include "lib/unpack.asm"
        .include "lib/manifest.asm"
        .include "lib/video_fcm.asm"
        .include "lib/fcm_text.asm"
        .include "lib/draw.asm"
        .include "lib/palette.asm"
        .include "lib/hwsprite.asm"
        .include "lib/mouse.asm"
        .include "lib/sid.asm"
        .include "lib/math.asm"

        .include "gen/cards.asm"
        .include "gen/palette.asm"
        .include "gen/manifest.asm"

        .cerror * > $c7ff, "program overflows into screen RAM C at $C800"
