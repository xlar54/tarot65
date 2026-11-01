;=======================================================================================
; spreads.asm - the four layouts: where each card lands, what its position means.
; Positions are the top-left of the card as it lies (the Celtic Cross's crossing card,
; sp_rot, lies turned: 48 x 28). One- and three-card spreads use the big 88 x 152 faces,
; the others the 28 x 48 thumbnails.
;=======================================================================================

SP_ONE          = 0
SP_THREE        = 1
SP_HORSESHOE    = 2
SP_CELTIC       = 3

sp_count:       .byte 1, 3, 7, 10
sp_big:         .byte 1, 1, 0, 0
sp_rot:         .byte $ff, $ff, $ff, 1      ; the card that lies across another
sp_first:       .byte 0, 1, 4, 11           ; first entry in the pos_* tables
sp_deck_x:      .word 116, 116, 154, 226    ; where the deck sits
sp_deck_y:      .byte 4, 4, 14, 56
sp_stat_y:      .byte 168, 168, 166, 163    ; two status lines from here
sp_centre:      .byte 1, 1, 1, 0            ; status text centred (else at x = 4)
sp_label:       .byte 1, 1, 0, 0            ; position names under the cards
sp_name_lo:     .byte <sn_one, <sn_three, <sn_horse, <sn_celtic
sp_name_hi:     .byte >sn_one, >sn_three, >sn_horse, >sn_celtic
sn_one:         .null "ONE CARD"
sn_three:       .null "THREE CARDS"
sn_horse:       .null "HORSESHOE"
sn_celtic:      .null "CELTIC CROSS"

POS     .macro px, py, name, desc
        .word \px
        .byte \py
        .word \name, \desc
        .endmacro
POS_SIZE        = 7

positions:
        ; one card
        #POS 116,   4, p_card,     d_card
        ; three cards
        #POS  20,   4, p_past,     d_past
        #POS 116,   4, p_present,  d_present
        #POS 212,   4, p_future,   d_future
        ; horseshoe: a V opening upwards
        #POS  22,  14, p_hpast,    d_hpast
        #POS  66,  50, p_hpresent, d_hpresent
        #POS 110,  86, p_hidden,   d_hidden
        #POS 154, 112, p_obstacle, d_obstacle
        #POS 198,  86, p_others,   d_others
        #POS 242,  50, p_advice,   d_advice
        #POS 286,  14, p_outcome,  d_outcome
        ; Celtic Cross: the cross, then the staff on the right from the bottom up
        #POS 110,  56, p_cpresent, d_cpresent
        #POS 100,  66, p_challenge, d_challenge
        #POS 110, 110, p_found,    d_found
        #POS  54,  56, p_recent,   d_recent
        #POS 110,   2, p_crown,    d_crown
        #POS 166,  56, p_near,     d_near
        #POS 284, 148, p_self,     d_self
        #POS 284,  99, p_environ,  d_environ
        #POS 284,  50, p_hopes,    d_hopes
        #POS 284,   1, p_coutcome, d_coutcome

p_card:         .null "YOUR CARD"
d_card:         .null "THE HEART OF THE MATTER"
p_past:         .null "PAST"
d_past:         .null "WHAT HAS SHAPED YOU"
p_present:      .null "PRESENT"
d_present:      .null "WHERE YOU STAND NOW"
p_future:       .null "FUTURE"
d_future:       .null "WHERE THE PATH LEADS"
p_hpast:        .null "THE PAST"
d_hpast:        .null "INFLUENCES BEHIND YOU"
p_hpresent:     .null "THE PRESENT"
d_hpresent:     .null "YOUR SITUATION NOW"
p_hidden:       .null "HIDDEN INFLUENCES"
d_hidden:       .null "WHAT YOU CANNOT SEE"
p_obstacle:     .null "THE OBSTACLE"
d_obstacle:     .null "WHAT STANDS IN THE WAY"
p_others:       .null "OTHERS"
d_others:       .null "THE PEOPLE AROUND YOU"
p_advice:       .null "ADVICE"
d_advice:       .null "WHAT YOU SHOULD DO"
p_outcome:      .null "THE OUTCOME"
d_outcome:      .null "WHERE THIS LEADS"
p_cpresent:     .null "THE PRESENT"
d_cpresent:     .null "THE HEART OF THE MATTER"
p_challenge:    .null "THE CHALLENGE"
d_challenge:    .null "WHAT CROSSES YOU"
p_found:        .null "THE FOUNDATION"
d_found:        .null "THE ROOT OF THE MATTER"
p_recent:       .null "THE RECENT PAST"
d_recent:       .null "WHAT IS PASSING AWAY"
p_crown:        .null "THE CROWN"
d_crown:        .null "THE BEST THAT CAN BE"
p_near:         .null "THE NEAR FUTURE"
d_near:         .null "WHAT COMES NEXT"
p_self:         .null "YOURSELF"
d_self:         .null "YOUR OWN ATTITUDE"
p_environ:      .null "YOUR SURROUNDINGS"
d_environ:      .null "HOME, WORK AND OTHERS"
p_hopes:        .null "HOPES AND FEARS"
d_hopes:        .null "WHAT YOU WISH OR DREAD"
p_coutcome:     .null "THE OUTCOME"
d_coutcome:     .null "WHERE ALL THIS LEADS"
