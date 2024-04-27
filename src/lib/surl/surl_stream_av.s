;
; Colin Leroy-Mira <colin@colino.net>, 2024
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 3 of the License, or
; (at your option) any later version.

; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
; You should have received a copy of the GNU General Public License
; along with this program. If not, see <http://www.gnu.org/licenses/>.

        .export         _surl_stream_av
        .export         _SAMPLES_BASE

        .importzp       _zp6, _zp8, _zp9, _zp10, _zp12, _zp13, tmp1, tmp2, tmp3, ptr1, ptr2, ptr3, ptr4

        .import         _serial_putc_direct
        .import         _simple_serial_set_irq
        .import         _simple_serial_flush
        .import         _sleep, _init_text, _clrscr
        .import         _printer_slot, _data_slot

        .import         acia_status_reg_r, acia_data_reg_r

        .include        "apple2.inc"

; -----------------------------------------------------------------

MAX_LEVEL         = 31

serial_status_reg = acia_status_reg_r
serial_data_reg   = acia_data_reg_r
HAS_BYTE          = $08

MAX_OFFSET    = 126
N_BASES       = (8192/MAX_OFFSET)+1
N_TEXT_BASES  = 4

.ifdef DOUBLE_BUFFER
PAGE0_HB      = $20
PAGE1_HB      = $40
.else
PAGE0_HB      = $20
PAGE1_HB      = PAGE0_HB
.endif

SPKR         := $C030

spkr_ptr      = _zp6            ; word
last_offset   = _zp8            ; byte
cur_mix       = _zp9            ; byte
next          = _zp10           ; word
page          = _zp12           ; byte
has_byte_zp   = _zp13           ; byte

store_dest    = ptr1            ; word
page_ptr_low  = ptr3            ; word
page_ptr_high = ptr4            ; word
zp_zero       = tmp1            ; byte
zp_vflag      = tmp2            ; byte
kbd_cmd       = tmp3            ; byte
; Used to cross page
VD_PAGE_OFFSET = 254

; ---------------------------------------------------------
;
; Macros

.macro SEV_ABS                  ; We use V flag to track HGR page
        bit     abs_vflag       ; dedicate a var because BIT #IMMEDIATE
.endmacro                       ; does NOT affect V flag

.macro SEV_ZP                   ; We use V flag to track HGR page
        bit     zp_vflag        ; dedicate a var because BIT #IMMEDIATE
.endmacro                       ; does NOT affect V flag

.macro CLV_ZP                   ; We use V flag to track HGR page
        bit     zp_zero         ; dedicate a var because BIT #IMMEDIATE
.endmacro                       ; does NOT affect V flag

; ease cycle counting
.macro WASTE_2                  ; Cycles wasters
        nop
.endmacro

.macro WASTE_3
        stz     zp_zero
.endmacro

.macro WASTE_4
        nop
        nop
.endmacro

.macro WASTE_5
      WASTE_2
      WASTE_3
.endmacro

.macro WASTE_6
        nop
        nop
        nop
.endmacro

.macro WASTE_7
      WASTE_2
      WASTE_5
.endmacro

.macro WASTE_8
      WASTE_4
      WASTE_4
.endmacro

.macro WASTE_9
        WASTE_3
        WASTE_6
.endmacro

.macro WASTE_10
        WASTE_4
        WASTE_6
.endmacro

.macro WASTE_11
        WASTE_5
        WASTE_6
.endmacro

.macro WASTE_12
        WASTE_6
        WASTE_6
.endmacro

.macro WASTE_13
        WASTE_7
        WASTE_6
.endmacro

.macro WASTE_14
        WASTE_8
        WASTE_6
.endmacro

.macro WASTE_15
        WASTE_12
        WASTE_3
.endmacro

.macro WASTE_16
        WASTE_12
        WASTE_4
.endmacro

.macro WASTE_17
        WASTE_12
        WASTE_5
.endmacro

.macro WASTE_18
        WASTE_12
        WASTE_6
.endmacro

.macro WASTE_19
        WASTE_12
        WASTE_7
.endmacro

.macro WASTE_20
        WASTE_12
        WASTE_8
.endmacro

.macro WASTE_21
        WASTE_12
        WASTE_9
.endmacro

.macro WASTE_22
        WASTE_12
        WASTE_10
.endmacro

.macro WASTE_23
        WASTE_12
        WASTE_11
.endmacro

.macro WASTE_24
        WASTE_12
        WASTE_12
.endmacro

.macro WASTE_25
        WASTE_12
        WASTE_10
        WASTE_3
.endmacro

.macro WASTE_26
        WASTE_12
        WASTE_12
        WASTE_2
.endmacro

.macro WASTE_27
        WASTE_12
        WASTE_12
        WASTE_3
.endmacro

.macro WASTE_28
        WASTE_12
        WASTE_12
        WASTE_4
.endmacro

.macro WASTE_29
        WASTE_12
        WASTE_12
        WASTE_5
.endmacro

.macro WASTE_30
        WASTE_12
        WASTE_12
        WASTE_6
.endmacro

.macro WASTE_31
        WASTE_12
        WASTE_12
        WASTE_7
.endmacro

.macro WASTE_32
        WASTE_12
        WASTE_12
        WASTE_8
.endmacro

.macro WASTE_33
        WASTE_12
        WASTE_12
        WASTE_9
.endmacro

.macro WASTE_34
        WASTE_12
        WASTE_12
        WASTE_10
.endmacro

.macro WASTE_35
        WASTE_12
        WASTE_12
        WASTE_11
.endmacro

.macro WASTE_36
        WASTE_12
        WASTE_12
        WASTE_12
.endmacro

.macro WASTE_37
        WASTE_12
        WASTE_12
        WASTE_6
        WASTE_7
.endmacro

.macro WASTE_38
        WASTE_12
        WASTE_12
        WASTE_7
        WASTE_7
.endmacro

.macro WASTE_40
        WASTE_12
        WASTE_12
        WASTE_12
        WASTE_4
.endmacro

.macro WASTE_39
        WASTE_12
        WASTE_12
        WASTE_12
        WASTE_3
.endmacro

.macro WASTE_41
        WASTE_12
        WASTE_12
        WASTE_12
        WASTE_5
.endmacro

.macro WASTE_42
        WASTE_12
        WASTE_12
        WASTE_12
        WASTE_6
.endmacro

.macro WASTE_43
        WASTE_12
        WASTE_12
        WASTE_12
        WASTE_7
.endmacro

.macro WASTE_44
        WASTE_12
        WASTE_12
        WASTE_12
        WASTE_8
.endmacro

.macro WASTE_45   ; 18 nop + sta zp + 3 nop = 21+2 = 23 bytes
        WASTE_12
        WASTE_12
        WASTE_12
        WASTE_9
.endmacro

; Hack to waste 1 cycle. Use absolute stx with $00nn
.macro ABS_STX  zpvar
        .byte   $8E             ; stx absolute
        .byte   zpvar
        .byte   $00
.endmacro

; Hack to waste 1 cycle. Use absolute stz with $00nn
.macro ABS_STZ  zpvar
        .byte   $9C             ; stz absolute
        .byte   zpvar
        .byte   $00
.endmacro

; Hack to waste 1 cycle. Use absolute stz with $00nn
.macro ABS_STA  zpvar
        .byte   $8D             ; sta absolute
        .byte   zpvar
        .byte   $00
.endmacro

.macro ____SPKR_DUTY____4       ; Toggle speaker
        sta     SPKR            ; 4
.endmacro

.ifdef __APPLE2ENH__
  .macro ____SPKR_DUTY____5       ; Toggle speaker slower (but without phantom-read)
          sta     (spkr_ptr)      ; 5
  .endmacro
.endif

        .code

; General principles. we expect audio to be pushed on one serial port, video on
; the other. Execution flow  is controlled via the audio stream, with each
; received byte being the next duty cycle's address high byte.
;
; This means that duty cycle functions have to be page-aligned so their low byte
; is always 00.
; Functions that don't need to be aligned are stuffed between duty_cycle functions
; when possible, to waste less space.
;
; There are 32 different duty cycles (0-31), each moving the speaker by toggling
; it on and off at a certain cycles interval (from 8 to 39).
; The tasks of each duty cycle handler is:
; - Toggle the speaker on, wait a certain amount of cycles, toggle it off
; - Fetch the next byte of audio
; - Fetch the next byte of video
; - If there is a video byte, handle it
;
; It is possible to lose audio bytes without horrible effects (the sound quality
; would just be badder), but every video byte has to be fetched and handled,
; otherwise the video handler, being a state machine, will get messed up.
; Reading the same audio byte twice has no big drawback either, but reading the
; same video byte would, for the same reasons.
; In accordance to that, we spare ourselves the cycles required to verify the
; audio serial port's status register and unconditionnaly read the audio serial
; port's data register.
;
; Each duty cycle takes 73 cycles to complete (just below the 86µs interval at
; which bytes arrive on a serial port at 115200 bps), but as precisely timing
; the speaker toggling moves the serial fetching code around, it is possible to
; lose bytes of video if we only check once per duty cycle.
;
; Hence, each duty cycle does the following:
; - Load whatever is in the audio data register into jump destination
; - If there is a video byte,
;    - Load it,
;    - Finish driving speaker,
;    - Waste the required amount of cycles
;    - Jump to video handler
; - Otherwise,
;    - Waste the required amount of cycles (less than in the first case),
;    - Check video byte again,
;    - If there is one, jump to video handler,
; - Otherwise,
;    - Load audio byte again,
;    - Waste (a lot) of cycles,
;    - Jump to the next duty cycle.
;
; Keyboard handling is cycle-expensive and can't be macroized properly, so
; reading the keyboard in cycle 15. This cycle, being in the middle, is,
; hopefully, called multiple hundreds of time per second.
;
; The video handler is responsible for jumping directly to the next duty
; cycle once the video byte is handled.
;
; As a rule of thumb, no bytes are dropped if we check for video byte around
; cycles 12-20 and 24-31.
;
; Almost every reference to serial registers is direct, so every duty cycle
; is patched in multiple places. The patched instructions are labelled like
; ad0 (audio data cycle 0), and they need to be in *_patches arrays to be
; patched at start.
; Hardcoded placeholders have $xxFF where $xx is the register's address low
; byte for my setup, for reference.
; vs = video status = $99 (printer port in slot 1)
; vd = video data   = $98 (printer port in slot 1)
; as = audio status = $A9 (modem port in slot 2)
; ad = audio data   = $A8 (modem port in slot 2)

; To emulate 22kHz, we'd have to fit 29 duty cycles in 80 cycles,
; with jmp direct, from:
; toggle4-toggle4-other29-other3-toggle4-toggle4-other29-jump3
; to:
; toggle4-other29-toggle4-other3-toggle4-other29-toggle4-jump3
; This seems difficult to achieve (8 cycles needed for the second toggling,
; going from 73 cycles without to 80 with means no wasting at all)
;
; Warning about the alignment of the 32 duty cycles: as we read the next
; sample without verifying the ACIA's status register, we may read an
; incomplete byte, while it is being landed in the data register.
;
; So, we have to align the duty cycles in a way that even when this happens,
; we do not jump to a place where we have no duty cycle. This is why, here,
; we have them from $6000 to $7F00:
; $60 = 01100000
; $7F = 01111111
;
; At worst, we'll play a wrong sample from time to time. Tests with duty
; cycles from $6400 to $8300 crashed into the monitor quite fast:
; $64 = 01100100
; $83 = 10000011
; Reading an incomplete byte there could result in reading 11111111, for
; example, but not only. We don't want that.

.align $100
_SAMPLES_BASE = *
.assert * = $6000, error
duty_cycle0:                    ; end spkr at 8
        ____SPKR_DUTY____4      ; 4      toggle speaker on
        ____SPKR_DUTY____4      ; 8      toggle speaker off
vs0:    lda     $99FF           ; 12     load video status register
ad0:    ldx     $A8FF           ; 16     load audio data register
        and     #HAS_BYTE       ; 18     check if video has byte
        beq     no_vid0         ; 20/21  branch accordingly
vd0:    ldy     $98FF           ; 24     load video data
        stx     next+1          ; 27     store next duty cycle destination
        WASTE_12                ; 39     waste extra cycles
        jmp     video_direct    ; 42=>73

no_vid0:                        ;        we had no video byte first try
        stx     next+1          ; 24     store next duty cycle destination
        WASTE_3                 ; 27     waste extra cycles
vs0b:   lda     $99FF           ; 31     check video status register again
        and     #HAS_BYTE       ; 33     do we have one?
        beq     no_vid0b        ; 35/36  branch accordingly
vd0b:   ldy     $98FF           ; 39     load video data
        jmp     video_direct    ; 42=>73

no_vid0b:                       ;        we had no video byte second try
ad0b:   ldx     $A8FF           ; 40     load audio data register again
        stx     next+1          ; 43     store next duty cycle destination
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

; -----------------------------------------------------------------
_surl_stream_av:                ; Entry point
        php
        sei                     ; Disable all interrupts

        pha

        lda     #$00            ; Disable serial interrupts
        jsr     _simple_serial_set_irq

        pla
        ; Setup pointers
        jsr     setup

        ; Clear pages
        bit     $C082
        lda     #$40
        sta     $E6
        jsr     $F3F2
        lda     #$20
        sta     $E6
        jsr     $F3F2
        bit     $C080

        lda     #$2F            ; Surl client ready
        jsr     _serial_putc_direct

        clv                     ; clear offset-received flag

        jmp     duty_start      ; And start!
; -----------------------------------------------------------------

.align $100
.assert * = _SAMPLES_BASE + $100, error
duty_cycle1:                    ; end spkr at 9
        ____SPKR_DUTY____4      ; 4
        ____SPKR_DUTY____5      ; 9
ad1:    ldx     $A8FF           ; 13
vs1:    lda     $99FF           ; 17
        and     #HAS_BYTE       ; 19
        beq     no_vid1         ; 21/22
vd1:    ldy     $98FF           ; 25
        stx     next+1          ; 28
        WASTE_11                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid1:
        WASTE_2                 ; 24
        stx     next+1          ; 27
vs1b:   lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid1b        ; 35/36
vd1b:   ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid1b:
ad1b:   ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

; -----------------------------------------------------------------
patch_addresses:                ; Patch all registers in ptr1 array with A
        ldy     #$00            ; Start at beginning
        sta     tmp1            ; Save value
next_addr:
        clc
        lda     (ptr1),y
        adc     #1              ; Add one to patch after label
        sta     ptr2
        iny
        lda     (ptr1),y
        beq     done            ; If high byte is 0, we're done
        adc     #0
        sta     ptr2+1
        iny

        lda     (ptr2)          ; Debug to be sure
        cmp     #$FF
        beq     :+
        brk
:

        lda     tmp1            ; Patch low byte
        sta     (ptr2)

        inc     ptr2            ; Patch high byte with base (in X)
        bne     :+
        inc     ptr2+1
:       txa
        sta     (ptr2)

        bra     next_addr
done:
        rts
; -----------------------------------------------------------------

.align $100
.assert * = _SAMPLES_BASE + $200, error
duty_cycle2:                    ; end spkr at 10
        ____SPKR_DUTY____4      ; 4
        WASTE_2                 ; 6
        ____SPKR_DUTY____4      ; 10
ad2:    ldx     $A8FF           ; 14
vs2:    lda     $99FF           ; 18
        and     #HAS_BYTE       ; 20
        beq     no_vid2         ; 22/23
vd2:    ldy     $98FF           ; 26
        stx     next+1          ; 29
        WASTE_10                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid2:
        ABS_STX next+1          ; 27 stx absolute
vs2b:   lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid2b        ; 35/36
vd2b:   ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid2b:
ad2b:   ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

; -----------------------------------------------------------------
patch_serial_registers:
        .ifdef IIGS
        brk                     ; Todo
        .else
        clc
        ldx     #$C0            ; Serial registers' high byte
        lda     #<(video_status_patches)
        sta     ptr1
        lda     #>(video_status_patches)
        sta     ptr1+1
        lda     _printer_slot
        asl
        asl
        asl
        asl
        adc     #$89            ; ACIA STATUS (in slot 0)
        jsr     patch_addresses

        lda     #<(video_data_patches)
        sta     ptr1
        lda     #>(video_data_patches)
        sta     ptr1+1
        lda     _printer_slot
        asl
        asl
        asl
        asl
        adc     #$88            ; ACIA DATA (in slot 0)
        pha
        jsr     patch_addresses
        pla
        clc
        adc     #2
        sta     vcmd+1
        stx     vcmd+2
        sta     vcmd2+1
        stx     vcmd2+2
        adc     #1
        sta     vctrl+1
        stx     vctrl+2

        ; Special case for vd26b, we want to cross page
        sec
        lda     vd26b+1
        sbc     #VD_PAGE_OFFSET
        sta     vd26b+1
        lda     vd26b+2
        sbc     #0
        sta     vd26b+2

        lda     #<(audio_status_patches)
        sta     ptr1
        lda     #>(audio_status_patches)
        sta     ptr1+1
        lda     _data_slot
        asl
        asl
        asl
        asl
        adc     #$89
        jsr     patch_addresses

        lda     #<(audio_data_patches)
        sta     ptr1
        lda     #>(audio_data_patches)
        sta     ptr1+1
        lda     _data_slot
        asl
        asl
        asl
        asl
        adc     #$88
        pha
        jsr     patch_addresses
        pla
        clc
        adc     #2
        sta     acmd+1
        stx     acmd+2
        adc     #1
        sta     actrl+1
        stx     actrl+2

        rts
        .endif
; -----------------------------------------------------------------

.align $100
.assert * = _SAMPLES_BASE + $300, error
duty_cycle3:                    ; end spkr at 11
        ____SPKR_DUTY____4      ; 4
        WASTE_3                 ; 7
        ____SPKR_DUTY____4      ; 11
ad3:    ldx     $A8FF           ; 15
vs3:    lda     $99FF           ; 19
        and     #HAS_BYTE       ; 21
        beq     no_vid3         ; 23/24
vd3:    ldy     $98FF           ; 27
        stx     next+1          ; 30
        WASTE_9                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid3:
        stx     next+1          ; 27
vs3b:   lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid3b        ; 35/36
vd3b:   ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid3b:
ad3b:   ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

; -----------------------------------------------------------------
video_status_patches:
                .word vss
                .word vs0
                .word vs0b
                .word vs1
                .word vs1b
                .word vs2
                .word vs2b
                .word vs3
                .word vs3b
                .word vs4
                .word vs4b
                .word vs5
                .word vs5b
                .word vs6
                .word vs6b
                .word vs7
                .word vs7b
                .word vs8
                .word vs8b
                .word vs9
                .word vs9b
                .word vs10
                .word vs10b
                .word vs11
                .word vs11b
                .word vs12
                .word vs12b
                .word vs13
                .word vs13b
                .word vs14
                .word vs14b
                .word vs15
                .word vs15b
                .word vs16
                .word vs16b
                .word vs17
                .word vs17b
                .word vs18
                .word vs18b
                .word vs19
                .word vs19b
                .word vs20
                .word vs20b
                .word vs21
                .word vs21b
                .word vs22
                .word vs22b
                .word vs23
                .word vs23b
                .word vs24
                .word vs24b
                .word vs25
                .word vs25b
                .word vs26
                .word vs26b
                .word vs27
                .word vs27b
                .word vs28
                .word vs28b
                .word vs29
                .word vs29b
                .word vs30
                .word vs30b
                .word vs31
                .word vs31b
                .word $0000
; -----------------------------------------------------------------

.align $100
.assert * = _SAMPLES_BASE + $400, error
duty_cycle4:                    ; end spkr at 12
        ____SPKR_DUTY____4      ; 4
ad4:    ldx     $A8FF           ; 8
        ____SPKR_DUTY____4      ; 12
vs4:    lda     $99FF           ; 16
        and     #HAS_BYTE       ; 18
        beq     no_vid4         ; 20/21
vd4:    ldy     $98FF           ; 24
        stx     next+1          ; 27
        WASTE_12                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid4:
        WASTE_3                 ; 24
        stx   next+1            ; 27
vs4b:   lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid4b        ; 35/36
vd4b:   ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid4b:
ad4b:   ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

; -----------------------------------------------------------------
video_data_patches:
                .word vds
                .word vd0
                .word vd0b
                .word vd1
                .word vd1b
                .word vd2
                .word vd2b
                .word vd3
                .word vd3b
                .word vd4
                .word vd4b
                .word vd5
                .word vd5b
                .word vd6
                .word vd6b
                .word vd7
                .word vd7b
                .word vd8
                .word vd8b
                .word vd9
                .word vd9b
                .word vd10
                .word vd10b
                .word vd11
                .word vd11b
                .word vd12
                .word vd12b
                .word vd13
                .word vd13b
                .word vd14
                .word vd14b
                .word vd15
                .word vd15b
                .word vd16
                .word vd16b
                .word vd17
                .word vd17b
                .word vd18
                .word vd18b
                .word vd19
                .word vd19b
                .word vd20
                .word vd20b
                .word vd21
                .word vd21b
                .word vd22
                .word vd22b
                .word vd23
                .word vd23b
                .word vd24
                .word vd24b
                .word vd25
                .word vd25b
                .word vd26
                .word vd26b
                .word vd27
                .word vd27b
                .word vd28
                .word vd28b
                .word vd29
                .word vd29b
                .word vd30
                .word vd30b
                .word vd31
                .word vd31b
                .word $0000
; -----------------------------------------------------------------

.align $100
.assert * = _SAMPLES_BASE + $500, error
duty_cycle5:                    ; end spkr at 13
        ____SPKR_DUTY____4      ; 4
ad5:    ldx     $A8FF           ; 8
        ____SPKR_DUTY____5      ; 13
vs5:    lda     $99FF           ; 17
        and     #HAS_BYTE       ; 19
        beq     no_vid5         ; 21/22
vd5:    ldy     $98FF           ; 25
        stx     next+1          ; 28
        WASTE_11                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid5:
        WASTE_2                 ; 24
        stx   next+1            ; 27
vs5b:   lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid5b        ; 35/36
vd5b:   ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid5b:
ad5b:   ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

; -----------------------------------------------------------------
audio_status_patches:
                .word ass
                .word asp
                .word $0000

audio_data_patches:
                .word ads
                .word adp
                .word ad0
                .word ad0b
                .word ad1
                .word ad1b
                .word ad2
                .word ad2b
                .word ad3
                .word ad3b
                .word ad4
                .word ad4b
                .word ad5
                .word ad5b
                .word ad6
                .word ad6b
                .word ad7
                .word ad7b
                .word ad8
                .word ad8b
                .word ad9
                .word ad9b
                .word ad10
                .word ad10b
                .word ad11
                .word ad11b
                .word ad12
                .word ad12b
                .word ad13
                .word ad13b
                .word ad14
                .word ad14b
                .word ad15
                .word ad15b
                .word ad16
                .word ad16b
                .word ad17
                .word ad17b
                .word ad18
                .word ad18b
                .word ad19
                .word ad19b
                .word ad20
                .word ad20b
                .word ad21
                .word ad21b
                .word ad22
                .word ad22b
                .word ad23
                .word ad23b
                .word ad24
                .word ad24b
                .word ad25
                .word ad25b
                .word ad26
                .word ad26b
                .word ad27
                .word ad27b
                .word ad28
                .word ad28b
                .word ad29
                .word ad29b
                .word ad30
                .word ad30b
                .word ad31
                .word ad31b
                .word $0000
; -----------------------------------------------------------------

.align $100
.assert * = _SAMPLES_BASE + $600, error
duty_cycle6:                    ; end spkr at 14
        ____SPKR_DUTY____4      ; 4
ad6:    ldx     $A8FF           ; 8
        WASTE_2                 ; 10
        ____SPKR_DUTY____4      ; 14
vs6:    lda     $99FF           ; 18
        and     #HAS_BYTE       ; 20
        beq     no_vid6         ; 22/23
vd6:    ldy     $98FF           ; 26
        stx     next+1          ; 29
        WASTE_10                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid6:
        ABS_STX next+1          ; 27 stx absolute
vs6b:   lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid6b        ; 35/36
vd6b:   ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid6b:
ad6b:   ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

; --------------------------------------------------------------
duty_start:
        ; Init cycle destination
        lda     #<(duty_start)
        sta     next
        lda     #>(duty_start)
        sta     next+1

ass:    lda     $A9FF
        and     #HAS_BYTE
        beq     vss
ads:    ldx     $A8FF
        stz     next            ; video_direct will jump there
        stx     next+1

vss:    lda     $99FF
        and     #HAS_BYTE
        beq     ass
vds:    ldy     $98FF
        jmp     video_direct
; --------------------------------------------------------------

.align $100
.assert * = _SAMPLES_BASE + $700, error
duty_cycle7:                    ; end spkr at 15
        ____SPKR_DUTY____4      ; 4
ad7:    ldx     $A8FF           ; 8
        WASTE_3                 ; 11
        ____SPKR_DUTY____4      ; 15
vs7:    lda     $99FF           ; 19
        and     #HAS_BYTE       ; 21
        beq     no_vid7         ; 23/24
vd7:    ldy     $98FF           ; 27
        stx     next+1          ; 30
        WASTE_9                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid7:
        stx     next+1          ; 27
vs7b:   lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid7b        ; 35/36
vd7b:   ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid7b:
ad7b:   ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

; -----------------------------------------------------------------
calc_bases:
        ; Precalculate addresses inside pages, so we can easily jump
        ; from one to another without complicated computations. X
        ; contains the base page address's high byte on entry ($20 for
        ; page 0, $40 for page 1)
        ldy     #0              ; Y is the index - Start at base 0
        lda     #$00            ; A is the address's low byte
                                ; (and X the address's high byte)

        clc
calc_next_base:
calc_addr_low:
        sta     page0_addrs_arr_low,y        ; Store AX
        pha
        txa
calc_addr_high:
        sta     page0_addrs_arr_high,y
        pla
        iny

        adc     #(MAX_OFFSET)   ; Compute next base
        bcc     :+
        inx
        clc
:       cpy     #(N_BASES)
        bcc     calc_next_base
        rts
; -----------------------------------------------------------------

; -----------------------------------------------------------------
calc_text_bases:
        ; Precalculate text lines 20-23 adresses, so we can easily jump
        ; from one to another without complicated computations. X
        ; contains line 20's base page address high byte on entry ($02 for
        ; page 0, $06 for page 1).
        ldy     #(N_BASES)    ; Y is the index - Start after HGR bases

        clc
calc_next_text_base:
calc_addr_text_low:
        sta     page0_addrs_arr_low,y        ; Store AX
        pha
        txa
calc_addr_text_high:
        sta     page0_addrs_arr_high,y
        pla
        iny

        adc     #$80                         ; Compute next base
        bcc     :+
        inx
        clc
:       cpy     #(N_BASES+4+1)
        bcc     calc_next_text_base
        rts
; -----------------------------------------------------------------

.align $100
.assert * = _SAMPLES_BASE + $800, error
duty_cycle8:                    ; end spkr at 16
        ____SPKR_DUTY____4      ; 4
ad8:    ldx     $A8FF           ; 8
vs8:    lda     $99FF           ; 12
        ____SPKR_DUTY____4      ; 16
        and     #HAS_BYTE       ; 18
        beq     no_vid8         ; 20/21
vd8:    ldy     $98FF           ; 24
        stx     next+1          ; 27
        WASTE_12                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid8:
        WASTE_3                 ; 24
        stx     next+1          ; 27
vs8b:   lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid8b        ; 35/36
vd8b:   ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid8b:
ad8b:   ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

; -----------------------------------------------------------------
setup:
        ; Setup pointer access to SPKR
        lda     #<(SPKR)
        sta     spkr_ptr
        lda     #>(SPKR)
        sta     spkr_ptr+1

        ; Calculate bases for HGR page 0
        lda     #>(page0_addrs_arr_low)
        sta     calc_addr_low+2
        sta     calc_addr_high+2
        sta     calc_addr_text_low+2
        sta     calc_addr_text_high+2
        ldx     #PAGE0_HB
        jsr     calc_bases
        lda     #$50
        ldx     #$06
        jsr     calc_text_bases

        ; Calculate bases for HGR page 1
        lda     #>(page1_addrs_arr_low)
        sta     calc_addr_low+2
        sta     calc_addr_high+2
        sta     calc_addr_text_low+2
        sta     calc_addr_text_high+2
        ldx     #PAGE1_HB
        jsr     calc_bases
        lda     #$50
        ldx     #$0A
        jsr     calc_text_bases

        ; Init vars
        stz     page
        stz     kbd_cmd
        stz     cur_mix

        ; Extra ZP variable to be able to waste one cycle using CMP ZP instead
        ; of CMP IMM in some duty cycles
        lda     #HAS_BYTE
        sta     has_byte_zp

        ; Vars to emulate "sev" (set overflow), in either 3 or 4 cycles
        lda     #$40
        sta     zp_vflag
        sta     abs_vflag

        ; Setup serial registers
        jsr     patch_serial_registers

acmd:   lda     $A8FF           ; Copy command and control registers from
vcmd:   sta     $98FF           ; the main serial port to the second serial
actrl:  lda     $A8FF           ; port, it's easier than setting it up from
vctrl:  sta     $98FF           ; scratch

        lda     #<(page0_addrs_arr_low)
        sta     page_ptr_low
        lda     #>(page0_addrs_arr_low)
        sta     page_ptr_low+1

        lda     #<(page0_addrs_arr_high)
        sta     page_ptr_high
        lda     #>(page0_addrs_arr_high)
        sta     page_ptr_high+1

        rts
; -----------------------------------------------------------------

.align $100
.assert * = _SAMPLES_BASE + $900, error
duty_cycle9:                    ; end spkr at 17
        ____SPKR_DUTY____4      ; 4
ad9:    ldx     $A8FF           ; 8
vs9:    lda     $99FF           ; 12
        ____SPKR_DUTY____5      ; 17
        and     #HAS_BYTE       ; 19
        beq     no_vid9         ; 21/22
vd9:    ldy     $98FF           ; 25
        stx     next+1          ; 28
        WASTE_11                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid9:
        WASTE_2                 ; 24
        stx     next+1          ; 27
vs9b:   lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid9b        ; 35/36
vd9b:   ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid9b:
ad9b:   ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $A00, error
duty_cycle10:                    ; end spkr at 18
        ____SPKR_DUTY____4      ; 4
ad10:   ldx     $A8FF           ; 8
vs10:   lda     $99FF           ; 12
        WASTE_2                 ; 14
        ____SPKR_DUTY____4      ; 18
        and     #HAS_BYTE       ; 20
        beq     no_vid10        ; 22/23
vd10:   ldy     $98FF           ; 26
        stx     next+1          ; 29
        WASTE_10                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid10:
        ABS_STX next+1          ; 27 stx absolute
vs10b:  lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid10b       ; 35/36
vd10b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid10b:
ad10b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle


.align $100
.assert * = _SAMPLES_BASE + $B00, error
duty_cycle11:                    ; end spkr at 19
        ____SPKR_DUTY____4      ; 4
ad11:   ldx     $A8FF           ; 8
vs11:   lda     $99FF           ; 12
        WASTE_3                 ; 15
        ____SPKR_DUTY____4      ; 19
        and     #HAS_BYTE       ; 21
        beq     no_vid11        ; 23/24
vd11:   ldy     $98FF           ; 27
        stx     next+1          ; 30
        WASTE_9                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid11:
        stx     next+1          ; 27
vs11b:  lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid11b       ; 35/36
vd11b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid11b:
ad11b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle


.align $100
.assert * = _SAMPLES_BASE + $C00, error
duty_cycle12:                    ; end spkr at 20
        ____SPKR_DUTY____4      ; 4
ad12:   ldx     $A8FF           ; 8
vs12:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        WASTE_2                 ; 16
        ____SPKR_DUTY____4      ; 20
        beq     no_vid12        ; 22/23
vd12:   ldy     $98FF           ; 26
        stx     next+1          ; 29
        WASTE_10                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid12:
        ABS_STX next+1          ; 27 stx absolute
vs12b:  lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid12b       ; 35/36
vd12b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid12b:
ad12b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $D00, error
duty_cycle13:                    ; end spkr at 21
        ____SPKR_DUTY____4      ; 4
ad13:   ldx     $A8FF           ; 8
vs13:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid13        ; 16/17
        ____SPKR_DUTY____5      ; 21
vd13:   ldy     $98FF           ; 25
        stx     next+1          ; 28
        WASTE_11                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid13:
        ____SPKR_DUTY____4      ; 21
        stx     next+1          ; 24
        WASTE_3                 ; 27
vs13b:  lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid13b       ; 35/36
vd13b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid13b:
ad13b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $E00, error
duty_cycle14:                    ; end spkr at 22
        ____SPKR_DUTY____4      ; 4
ad14:   ldx     $A8FF           ; 8
vs14:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid14        ; 16/17
        WASTE_2                 ; 18
        ____SPKR_DUTY____4      ; 22
vd14:   ldy     $98FF           ; 26
        stx     next+1          ; 29
        WASTE_10                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid14:
        ____SPKR_DUTY____5      ; 22
        stx     next+1          ; 25
        WASTE_2                 ; 27
vs14b:  lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid14b       ; 35/36
vd14b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid14b:
ad14b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $F00, error
duty_cycle15:                    ; end spkr at 23
        ____SPKR_DUTY____4      ; 4
ad15:   ldx     $A8FF           ; 8
vs15:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid15        ; 16/17
        WASTE_3                 ; 19
        ____SPKR_DUTY____4      ; 23
vd15:   ldy     $98FF           ; 27
        stx     next+1          ; 30
        WASTE_9                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid15:
        WASTE_2                 ; 19
        ____SPKR_DUTY____4      ; 23
        ABS_STX next+1          ; 27 stx absolute
vs15b:  lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid15b       ; 35/36
vd15b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid15b:
asp:    lda     $FFFF           ; 40     check serial tx empty
        and     #$10            ; 42
        beq     noser           ; 44/45

        lda     KBD             ; 48     keyboard handling
        bpl     nokbd           ; 50/51
        sta     KBDSTRB         ; 54     we have a key, clear strobe
        and     #$7F            ; 56
adp:    sta     $FFFF           ; 60     send cmd
        cmp     #$1B            ; 62
        beq     out             ; 64/65  if escape, exit forcefully
        sta     kbd_cmd         ; 67
        jmp     (next)          ; 73     jump to next duty cycle
nokbd:
ad15b:  ldx     $A8FF           ; 55
        stx     next+1          ; 58
        WASTE_9                 ; 67
        jmp     (next)          ; 73     jump to next duty cycle
noser:  WASTE_22                ; 67
        jmp     (next)          ; 73     jump to next duty cycle
out:    jmp     break_out

.align $100
.assert * = _SAMPLES_BASE + $1000, error
duty_cycle16:                    ; end spkr at 24
        ____SPKR_DUTY____4      ; 4
ad16:   ldx     $A8FF           ; 8
vs16:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid16        ; 16/17
vd16:   ldy     $98FF           ; 20
        ____SPKR_DUTY____4      ; 24
        stx     next+1          ; 27
        WASTE_12                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid16:
        stx     next+1          ; 20
        ____SPKR_DUTY____4      ; 24
        WASTE_3                 ; 27
vs16b:  lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid16b       ; 35/36
vd16b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid16b:
ad16b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        lda     kbd_cmd         ; 46     handle subtitles switch
        ldx     cur_mix         ; 49
        cmp     #$09            ; 51
        bne     not_tab         ; 53/54
        lda     $C052,x         ; 57     not BIT, to preserve V flag
        txa                     ; 59
        eor     #$01            ; 61
        sta     cur_mix         ; 64
        stz     kbd_cmd         ; 67
        jmp     (next)          ; 73     jump to next duty cycle

not_tab:
        WASTE_13                ; 67
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $1100, error
duty_cycle17:                    ; end spkr at 25
        ____SPKR_DUTY____4      ; 4
ad17:   ldx     $A8FF           ; 8
vs17:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid17        ; 16/17
vd17:   ldy     $98FF           ; 20
        ____SPKR_DUTY____5      ; 25
        stx     next+1          ; 28
        WASTE_11                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid17:
        stx     next+1          ; 20
        ____SPKR_DUTY____5      ; 25
        WASTE_2                 ; 27
vs17b:  lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid17b       ; 35/36
vd17b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid17b:
ad17b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $1200, error
duty_cycle18:                    ; end spkr at 26
        ____SPKR_DUTY____4      ; 4
ad18:   ldx     $A8FF           ; 8
vs18:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid18        ; 16/17
vd18:   ldy     $98FF           ; 20
        WASTE_2                 ; 22
        ____SPKR_DUTY____4      ; 26
        stx     next+1          ; 29
        WASTE_10                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid18:
        ABS_STX next+1          ; 21
        ____SPKR_DUTY____5      ; 26
vs18b:  lda     $99FF           ; 30
        and     has_byte_zp     ; 33
        beq     no_vid18b       ; 35/36
vd18b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid18b:
ad18b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $1300, error
duty_cycle19:                    ; end spkr at 27
        ____SPKR_DUTY____4      ; 4
ad19:   ldx     $A8FF           ; 8
vs19:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid19        ; 16/17
vd19:   ldy     $98FF           ; 20
        WASTE_2                 ; 22
        ____SPKR_DUTY____5      ; 27
        stx     next+1          ; 30
        WASTE_9                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid19:
        WASTE_2                 ; 19
        ABS_STX next+1          ; 23 stx absolute
        ____SPKR_DUTY____4      ; 27
vs19b:  lda     $99FF           ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid19b       ; 35/36
vd19b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid19b:
ad19b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $1400, error
duty_cycle20:                    ; end spkr at 28
        ____SPKR_DUTY____4      ; 4
ad20:   ldx     $A8FF           ; 8
vs20:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid20        ; 16/17
vd20:   ldy     $98FF           ; 20
        WASTE_4                 ; 24
        ____SPKR_DUTY____4      ; 28
        stx     next+1          ; 31
        WASTE_8                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid20:
        stx     next+1          ; 20
vs20b:  lda     $99FF           ; 24
        ____SPKR_DUTY____4      ; 28
        WASTE_3                 ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid20b       ; 35/36
vd20b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid20b:
ad20b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $1500, error
duty_cycle21:                    ; end spkr at 29
        ____SPKR_DUTY____4      ; 4
ad21:   ldx     $A8FF           ; 8
vs21:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid21        ; 16/17
vd21:   ldy     $98FF           ; 20
        stx     next+1          ; 23
        WASTE_2                 ; 25
        ____SPKR_DUTY____4      ; 29
        WASTE_10                ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid21:
        ABS_STX next+1          ; 21 stx absolute
vs21b:  lda     $99FF           ; 25
        ____SPKR_DUTY____4      ; 29
        WASTE_2                 ; 31
        and     #HAS_BYTE       ; 33
        beq     no_vid21b       ; 35/36
vd21b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid21b:
ad21b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $1600, error
duty_cycle22:                    ; end spkr at 30
        ____SPKR_DUTY____4      ; 4
ad22:   ldx     $A8FF           ; 8
vs22:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid22        ; 16/17
vd22:   ldy     $98FF           ; 20
        stx     next+1          ; 23
        WASTE_3                 ; 26
        ____SPKR_DUTY____4      ; 30
        WASTE_9                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid22:
        stx     next+1          ; 20
vs22b:  lda     $99FF           ; 24
        and     #HAS_BYTE       ; 26
        ____SPKR_DUTY____4      ; 30
        beq     no_vid22b       ; 32/33
        WASTE_3                 ; 35
vd22b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid22b:
ad22b:  ldx     $A8FF           ; 37
        stx     next+1          ; 40
        WASTE_27                ; 67
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $1700, error
duty_cycle23:                    ; end spkr at 31
        ____SPKR_DUTY____4      ; 4
ad23:   ldx     $A8FF           ; 8
vs23:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid23        ; 16/17
vd23:   ldy     $98FF           ; 20
        stx     next+1          ; 23
        WASTE_4                 ; 27
        ____SPKR_DUTY____4      ; 31
        WASTE_8                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid23:
        stx     next+1          ; 20
vs23b:  lda     $99FF           ; 24
        and     #HAS_BYTE       ; 26
        ____SPKR_DUTY____5      ; 31
        WASTE_2                 ; 33
        beq     no_vid23b       ; 35/36
vd23b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid23b:
ad23b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle


.align $100
.assert * = _SAMPLES_BASE + $1800, error
duty_cycle24:                    ; end spkr at 32
        ____SPKR_DUTY____4      ; 4
ad24:   ldx     $A8FF           ; 8
vs24:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid24        ; 16/17
vd24:   ldy     $98FF           ; 20
        stx     next+1          ; 23
        WASTE_5                 ; 28
        ____SPKR_DUTY____4      ; 32
        WASTE_7                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid24:
        WASTE_2                 ; 19
vs24b:  lda     $99FF           ; 23
        and     #HAS_BYTE       ; 25
        beq     no_vid24b       ; 27/28
        ____SPKR_DUTY____5      ; 32
        stx     next+1          ; 35
vd24b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid24b:
        ____SPKR_DUTY____4      ; 32
ad24b:  ldx     $A8FF           ; 36
        stx     next+1          ; 39
        WASTE_28                ; 67
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $1900, error
duty_cycle25:                    ; end spkr at 33
        ____SPKR_DUTY____4      ; 4
ad25:   ldx     $A8FF           ; 8
vs25:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid25        ; 16/17
vd25:   ldy     $98FF           ; 20
        stx     next+1          ; 23
        WASTE_6                 ; 29
        ____SPKR_DUTY____4      ; 33
        WASTE_6                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid25:
        stx     next+1          ; 20
vs25b:  lda     $99FF           ; 24
        and     #HAS_BYTE       ; 26
        beq     no_vid25b       ; 28/29
        ____SPKR_DUTY____5      ; 33
        WASTE_2                 ; 35
vd25b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid25b:
        ____SPKR_DUTY____4      ; 33
ad25b:  ldx     $A8FF           ; 37
        stx     next+1          ; 40
        WASTE_27                ; 67
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $1A00, error
duty_cycle26:                    ; end spkr at 34
        ____SPKR_DUTY____4      ; 4
ad26:   ldx     $A8FF           ; 8
vs26:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid26        ; 16/17
vd26:   ldy     $98FF           ; 20
        stx     next+1          ; 23
        WASTE_7                 ; 30
        ____SPKR_DUTY____4      ; 34
        WASTE_5                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid26:
        stx     next+1          ; 20
vs26b:  lda     $99FF           ; 24
        and     #HAS_BYTE       ; 26
        beq     no_vid26b       ; 28/29
        ldx     #VD_PAGE_OFFSET ; 30
        ____SPKR_DUTY____4      ; 34
vd26b:  ldy     $98FF,x         ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid26b:
        ____SPKR_DUTY____5      ; 34
ad26b:  ldx     $A8FF           ; 38
        stx     next+1          ; 41
        WASTE_26                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $1B00, error
duty_cycle27:                    ; end spkr at 35
        ____SPKR_DUTY____4      ; 4
ad27:   ldx     $A8FF           ; 8
vs27:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid27        ; 16/17
vd27:   ldy     $98FF           ; 20
        stx     next+1          ; 23
        WASTE_8                 ; 31
        ____SPKR_DUTY____4      ; 35
        WASTE_4                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid27:
        stx     next+1          ; 20
        WASTE_2                 ; 22
vs27b:  lda     $99FF           ; 26
        and     #HAS_BYTE       ; 28
        beq     no_vid27b       ; 30/31
        ____SPKR_DUTY____5      ; 35
vd27b:  ldy     $98FF           ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid27b:
        ____SPKR_DUTY____4      ; 35
ad27b:  ldx     $A8FF           ; 39
        stx     next+1          ; 42
        WASTE_25                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $100
.assert * = _SAMPLES_BASE + $1C00, error
duty_cycle28:                    ; end spkr at 36
        ____SPKR_DUTY____4      ; 4
ad28:   ldx     $A8FF           ; 8
vs28:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid28        ; 16/17
vd28:   ldy     $98FF           ; 20
        stx     next+1          ; 23
        WASTE_9                 ; 32
        ____SPKR_DUTY____4      ; 36
        WASTE_3                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid28:
        WASTE_3                 ; 20
vs28b:  lda     $99FF           ; 24
        and     #HAS_BYTE       ; 26
        beq     no_vid28b       ; 28/29
vd28b:  ldy     $98FF           ; 32
        ____SPKR_DUTY____4      ; 36
        stx     next+1          ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid28b:
        WASTE_3                 ; 32
        ____SPKR_DUTY____4      ; 36
ad28b:  ldx     $A8FF           ; 40
        stx     next+1          ; 43
        WASTE_24                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle


.align $100
.assert * = _SAMPLES_BASE + $1D00, error
duty_cycle29:                    ; end spkr at 37
        ____SPKR_DUTY____4      ; 4
ad29:   ldx     $A8FF           ; 8
vs29:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid29        ; 16/17
vd29:   ldy     $98FF           ; 20
        stx     next+1          ; 23
        WASTE_10                ; 33
        ____SPKR_DUTY____4      ; 37
        WASTE_2                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid29:
        stx     next+1          ; 20
vs29b:  lda     $99FF           ; 24
        and     #HAS_BYTE       ; 26
        beq     no_vid29b       ; 28/29
vd29b:  ldy     $98FF           ; 32
        ____SPKR_DUTY____5      ; 37
        WASTE_2                 ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid29b:
        WASTE_4                 ; 33
        ____SPKR_DUTY____4      ; 37
ad29b:  ldx     $A8FF           ; 41
        stx     next+1          ; 44
        WASTE_23                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $20 ; page0_ and page1_ addresses arrays must share the same low byte
.assert * = _SAMPLES_BASE + $1D60, error
PAGE0_ARRAY = *
page0_addrs_arr_low: .res (N_BASES+4+1)          ; Base addresses arrays
page0_addrs_arr_high:.res (N_BASES+4+1)          ; Base addresses arrays

.align $100
.assert * = _SAMPLES_BASE + $1E00, error
; Duty cycle 30 must toggle off speaker at cycle 38, but we would have to jump
; to video_direct at cycle 39, so this one uses different entry points to
; the video handler to fix this.
duty_cycle30:                    ; end spkr at 38
        ____SPKR_DUTY____4      ; 4
ad30:   ldx     $A8FF           ; 8
vs30:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid30        ; 16/17
vd30:   ldy     $98FF           ; 20
        WASTE_11                ; 31
        jmp     video_tog_spkr  ; 34=>73 (turns spkr off, jumps to next)

no_vid30:
        jmp     duty_cycle30_v2 ; 20=>73 (takes 53 cycles)

no_vid30b:
        WASTE_2                 ; 34
        ____SPKR_DUTY____4      ; 38
ad30b:  ldx     $A8FF           ; 42
        stx     next+1          ; 45
        WASTE_22                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

duty_cycle30_v2:                ; Alternate entry point for duty cycle 30
vs30b:  lda     $99FF           ; 24
        and     has_byte_zp     ; 27
        bne     vd30b           ; 29/30
        jmp     no_vid30b       ; 32

vd30b:  ldy     $98FF           ; 34

; -----------------------------------------------------------------
; VIDEO HANDLER

video_tog_spkr:                 ; Alternate entry point for duty cycle 30
        ____SPKR_DUTY____4      ; 38
        ABS_STX next+1          ; 42

; Video handler expects the video byte in Y register, and the N flag set by
; its loading.
; Video handler must take 33 cycles on every code path.
video_direct:
        bmi     @set_pixel              ; 2/3   Is it a control byte?
@control:                               ;       It is a control byte
        cpy     #$7F                    ; 4     Is it the page toggle command?
        bne     @dest_ctrl              ; 6/7   Yes

@toggle_page:                           ;       Page toggling command (branch takes 23 cycles minimum)
.ifdef DOUBLE_BUFFER
        ldx     page                    ; 9
        bne     @page0                  ; 11/12
@page1:                                 ;       (branch takes 21 cycles minimum)
        sta     $C055                   ; 15    Activate page 1
        lda     #>(page0_addrs_arr_low) ; 17    Write to page 0
        sta     page_ptr_low+1          ; 20    Update pointers to page 0
        sta     page_ptr_high+1         ; 23
        WASTE_2                         ; 25    No time to update page flag,
        jmp     (next)                  ; 31    We'll do it in @set_offset

@page0:                                 ;       (branch takes 20 cycles minimum)
        sta     $C054                   ; 16    Activate page 0
        lda     #>(page1_addrs_arr_low) ; 18    Write to page 1
        sta     page_ptr_low+1          ; 21    Update pointers to page 1
        ABS_STA page_ptr_high+1         ; 25
        jmp     (next)                  ; 31
.else
        WASTE_19                        ; 25
        jmp     (next)                  ; 31
.endif

@dest_ctrl:
        bvc     @set_offset             ; 9/10 If yes, this one is a base byte

@set_base:                              ;       This is a base byte (branch takes 22 cycles minimum)
        lda     (page_ptr_low),y        ; 14    Load base pointer low byte from base array
        sta     store_dest              ; 17    Store it to destination pointer low byte
        lda     (page_ptr_high),y       ; 22    Load base pointer high byte from base array
        sta     store_dest+1            ; 25    Store it to destination pointer high byte
        jmp     (next)                  ; 31    Done, go to next duty cycle

@set_offset:                            ;       No, so set offset (branch takes 14 cyles minimum)
        sty     last_offset             ; 13    Store offset
        SEV_ZP                          ; 16    Set the offset-received flag
        lda     page_ptr_high+1         ; 19    Update the page flag here, where we have time
        eor     #>(PAGE1_ARRAY)        ; 21
        ABS_STA page                    ; 25
        jmp     (next)                  ; 31    Done, go to next duty cycle

@set_pixel:                             ;       No, it is a data byte (branch takes 25 cycles minimum)
        tya                             ; 5
        ldy     last_offset             ; 8    Load the offset to the start of the base
        sta     (store_dest),y          ; 14    Store data byte
        inc     last_offset             ; 19    and store it.
        clv                             ; 21    Reset the offset-received flag.
        WASTE_4                         ; 25
        jmp     (next)                  ; 31    Done, go to next duty cycle


; -----------------------------------------------------------------

.align $100
.assert * = _SAMPLES_BASE + $1F00, error
duty_cycle31:                    ; end spkr at 39
        ____SPKR_DUTY____4      ; 4
ad31:   ldx     $A8FF           ; 8
vs31:   lda     $99FF           ; 12
        and     #HAS_BYTE       ; 14
        beq     no_vid31        ; 16/17
vd31:   ldy     $98FF           ; 20
        stx     next+1          ; 23
        WASTE_12                ; 35
        ____SPKR_DUTY____4      ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid31:
        stx     next+1          ; 20
        WASTE_2                 ; 22
vs31b:  lda     $99FF           ; 26
        and     #HAS_BYTE       ; 28
        beq     no_vid31b       ; 30/31
vd31b:  ldy     $98FF           ; 34
        ____SPKR_DUTY____5      ; 39
        jmp     video_direct    ; 42=>73 (takes 31 cycles, jumps to next)

no_vid31b:
        WASTE_4                 ; 35
        ____SPKR_DUTY____4      ; 39
ad31b:  ldx     $A8FF           ; 43
        stx     next+1          ; 46
        WASTE_21                ; 67     waste extra cycles
        jmp     (next)          ; 73     jump to next duty cycle

.align $20
.assert * = _SAMPLES_BASE + $1F60, error
PAGE1_ARRAY = *
page1_addrs_arr_low: .res (N_BASES+4+1)          ; Base addresses arrays
page1_addrs_arr_high:.res (N_BASES+4+1)          ; Base addresses arrays

abs_vflag:      .byte $40

.align $100
.assert * = _SAMPLES_BASE+$2000, error
break_out:
        jsr     _clrscr
        jsr     _init_text
        lda     #$01
        ldx     #$00
        jsr     _sleep

        lda     #$02            ; Disable second port
vcmd2:  sta     $98FF

        plp                     ; Reenable all interrupts
        lda     #$01            ; Reenable serial interrupts and flush
        jsr     _simple_serial_set_irq
        jsr     _simple_serial_flush
        lda     #$2F            ; SURL_CLIENT_READY
        jmp     _serial_putc_direct
