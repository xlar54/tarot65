;=======================================================================================
; Project base-page variables, after the library's (lib/zp.asm). Keep below $90 if the
; program loads files with the KERNAL at boot.
;=======================================================================================
        .virtual LIB_ZP_END
cptr:           .dword ?                ; gfx.asm: source for [cptr],z
dptr:           .dword ?                ;   destination for [dptr],z
xcount:         .word ?                 ;   bytes left to expand
blist:          .word ?                 ; button list being drawn / tested
sptr:           .word ?                 ; string / table pointer
zp_end:
        .endv
        .cerror zp_end > $90, "base page variables overflow into KERNAL space"
