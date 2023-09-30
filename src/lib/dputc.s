;
; Ullrich von Bassewitz, 06.08.1998
; Colin Leroy-Mira <colin@colino.net>, 2023
;
; void __fastcall__ dputcxy (unsigned char x, unsigned char y, char c);
; void __fastcall__ dputc (char c);
;

        .export         _dputcxy, _dputc
        .export         dnewline
        .import         gotoxy, VTABZ
        .ifdef  __APPLE2ENH__
        .import         putchardirect
        .else
        .import         putchar
        .endif
        .import         _scrollup_one

        .include        "apple2.inc"

        .code

; Plot a character - also used as internal function

special_chars:
        cmp     #$0A            ; Test for \n = line feed
        beq     dnewline
        cmp     #$08            ; Test for backspace
        beq     backspace
        cmp     #$07            ; Test for bell
        beq     bell
        .ifdef  __APPLE2ENH__
        bra     invert          ; Back to standard codepath
        .else
        jmp     invert
        .endif

_dputcxy:
        pha                     ; Save C
        jsr     gotoxy          ; Call this one, will pop params
        pla                     ; Restore C and run into _dputc

_dputc:
        cmp     #$0D            ; Test for \r = carrage return
        beq     left
        bcc     special_chars   ; Skip other tests if possible
invert: eor     #$80            ; Invert high bit

        .ifndef __APPLE2ENH__
        cmp     #$E0            ; Test for lowercase
        bcc     dputdirect
        and     #$DF            ; Convert to uppercase
        .endif

dputdirect:
        .ifndef __APPLE2ENH__
        jsr     putchar
        .else
        jsr     putchardirect
        .endif
        inc     CH              ; Bump to next column
        lda     CH
        cmp     WNDWDTH
        bcs     :+
        rts

:       jsr     dnewline
left:
        .ifdef  __APPLE2ENH__
        stz     CH              ; Goto left edge of screen
        .else
        lda     #$00
        sta     CH
        .endif
        rts

bell:
        bit     $C082
        jsr     $FF3A           ; BELL
        bit     $C080
        rts

backspace:
        lda     CH
        cmp     WNDLFT          ; are we at col 0
        bne     decrh           ; no, we can decrement 
        ldy     CV              ; yes,
        cmp     WNDTOP          ; so are we at row 0
        beq     :+              ; yes, do nothing
        dey                     ; no, decr row
        sty     CV              ; store it
        ldy     WNDWDTH         ; prepare CH for decr
        sty     CH
decrh:  dec     CH
:       rts

dnewline:
        inc     CV              ; Bump to next line
        lda     CV
        cmp     WNDBTM          ; Are we at bottom?
        bcc     :+
        dec     CV              ; Yes, decrement
        jsr     _scrollup_one   ; and scroll
        lda     CV
:       jmp     VTABZ
