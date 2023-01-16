;
; Ullrich von Bassewitz, 06.08.1998
;
; void cputsxy (unsigned char x, unsigned char y, const char* s);
; void cputs (const char* s);
;

        .export         _dputsxy, _dputs
        .import         gotoxy, _dputc
        .importzp       ptr1, tmp1

_dputsxy:
        sta     ptr1            ; Save s for later
        stx     ptr1+1
        jsr     gotoxy          ; Set cursor, pop x and y
        jmp     L0              ; Same as dputs...

_dputs: sta     ptr1            ; Save s
        stx     ptr1+1
L0:     ldy     #0
L1:     lda     (ptr1),y
        beq     L9              ; Jump if done
        iny
        sty     tmp1            ; Save offset
        jsr     _dputc          ; Output char, advance cursor
        ldy     tmp1            ; Get offset
        bne     L1              ; Next char
        inc     ptr1+1          ; Bump high byte
        bne     L1

; Done

L9:     rts
