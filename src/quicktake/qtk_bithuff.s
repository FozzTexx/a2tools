;
; File generated by cc65 v 2.19 - Git 51b946bf2
;
        .importzp       sp
        .importzp       tmp1, tmp2, tmp3, tmp4, ptr1, ptr2, ptr3, sreg
        .importzp       _prev_ram_irq_vector

        .import         decsp6, popptr1
        .import         _fread
        .import         _bitbuf
        .import         _bitbuf_nohuff
        .import         _vbits
        .import         _cache_start
        .import         _cache_end
        .import         _ifp
        .import         _got_four_bits
        .import         _huff_ptr
        .export         _reset_bitbuff
        .export         _get_four_bits
        .export         _getbithuff

cur_cache_ptr = _prev_ram_irq_vector

; ---------------------------------------------------------------
; unsigned char __near__ __fastcall__ reset_bitbuff(void)
; ---------------------------------------------------------------


; Don't put this one in LC as it is patched on runtime

_reset_bitbuff:
        stz     _bitbuf_nohuff
        stz     _vbits

        ; Patch end-of-cache comparisons
        lda     _cache_end
        sta     not_enough_vbits+1
        lda     _cache_end+1
        sta     cache_check_high+1
        rts

; ---------------------------------------------------------------
; unsigned char __near__ __fastcall__ get_four_bits(void)
; ---------------------------------------------------------------

; Don't put this one in LC as it is patched on runtime

_get_four_bits:
        lda     #0              ; Patched (flip-flop)
        beq     not_enough_vbits
        stz     _get_four_bits+1; Patch flip-flop
low_nibble:
        ldx     #$00            ; Patched
        jmp     _got_four_bits

not_enough_vbits:
        lda     #0              ; Patched when resetting (_cache_end)
        cmp     cur_cache_ptr
        beq     cache_check_high

fetch_vbits:
        lda     (cur_cache_ptr)
        tay

        and     #$0F            ; Patch low nibble for next call
        sta     low_nibble+1

        inc     cur_cache_ptr
        bne     :+
        inc     cur_cache_ptr+1

:       inc     _get_four_bits+1; Patch flip-flop
        ldx     high_nibble,y
        jmp     _got_four_bits

cache_check_high:
        ldx     #0              ; Patched when resetting (_cache_end+1)
        cpx     cur_cache_ptr+1
        bne     fetch_vbits

must_read:
        jsr     decsp6

        ; Push fread dest pointer
        ldy     #$05

        lda     _cache_start+1
        sta     cur_cache_ptr+1
        sta     (sp),y

        lda     _cache_start
        sta     cur_cache_ptr
        dey
        sta     (sp),y

        ; Push size (1)
        dey
        lda     #0
        sta     (sp),y
        dey
        inc     a
        sta     (sp),y

        ; Push count ($1000, CACHE_SIZE)
        dey
        lda     #>CACHE_SIZE
        sta     (sp),y
        dey
        lda     #<CACHE_SIZE
        sta     (sp),y

        lda     _ifp
        ldx     _ifp+1
        jsr     _fread
        jmp     fetch_vbits

.segment        "BSS"

nbits:
        .res        1,$00

; ---------------------------------------------------------------
; unsigned char __near__ __fastcall__ getbithuff (unsigned char n)
; ---------------------------------------------------------------

.segment        "LC"
_getbithuff:
        sta     nbits
        cmp     _vbits
        bcc     have_enough_vbits_h
        ldx     _bitbuf+2
        stx     _bitbuf+3
        ldx     _bitbuf+1
        stx     _bitbuf+2
        ldx     _bitbuf
        stx     _bitbuf+1
        ; _bitbuf low byte will be set below

        lda     _cache_end
        cmp     cur_cache_ptr
        bne     no_read_required_h
        ldx     _cache_end+1
        cpx     cur_cache_ptr+1
        bne     no_read_required_h
        jsr     decsp6

        ; Push fread dest pointer
        ldy     #$05
        lda     _cache_start+1
        sta     cur_cache_ptr+1
        sta     (sp),y

        lda     _cache_start
        sta     cur_cache_ptr
        dey
        sta     (sp),y

        ; Push size (1)
        dey
        lda     #0
        sta     (sp),y
        dey
        inc     a
        sta     (sp),y

        ; Push count ($1000, CACHE_SIZE)
        dey
        lda     #>CACHE_SIZE
        sta     (sp),y
        dey
        lda     #<CACHE_SIZE
        sta     (sp),y

        lda     _ifp
        ldx     _ifp+1
        jsr     _fread

no_read_required_h:
        lda     (cur_cache_ptr)
        sta     _bitbuf

        inc     cur_cache_ptr
        bne     :+
        inc     cur_cache_ptr+1

:       clc
        lda     #$08
        adc     _vbits
        sta     _vbits

have_enough_vbits_h:
        ldx     _vbits
        lda     min32,x
        cmp     #24
        bcc     maybe_shift_16_h
        ldy     _bitbuf         ; take low byte to high
        ldx     #0
        jmp     finish_lshift_h
maybe_shift_16_h:
        cmp     #16
        bcc     maybe_shift_8_h
        ldy     _bitbuf+1       ; two low bytes to high
        ldx     _bitbuf
        jmp     finish_lshift_h
maybe_shift_8_h:
        cmp     #8
        bcc     finish_lshift_h
        ldy     _bitbuf+2       ; mid bytes to high
        ldx     _bitbuf+1
        ; Don't care about the two low bytes
finish_lshift_h:
        sty     tmp4
        and     #$07
        beq     lshift_done_h
        tay
        txa
        ; We can shift only the two high bytes, they'll be the only ones counting later
:       asl     a
        rol     tmp4
        dey
        bne     :-
        ; And we don't care saving tmp3

lshift_done_h:
        ldx     nbits           ; Now we shift right
        lda     min8,x
        beq     no_final_shift_h
        tay
        lda     tmp4

:       lsr     a
        dey
        bne     :-
        jmp     do_huff_h
no_final_shift_h:
        lda     tmp4
do_huff_h:
        tax                     ; backup for no_huff case
        ldy     _huff_ptr+1
        beq     no_huff

        ldx     #$00
        asl     a
        bcc     :+
        inx
        clc

:       adc     _huff_ptr
        sta     ptr1
        txa
        adc     _huff_ptr+1
        sta     ptr1+1
        ldy     #$01
        lda     (ptr1),y
        eor     #$FF
        sec
        adc     _vbits
        sta     _vbits
        ldx     #$00
        lda     (ptr1)
        rts
no_huff:
        lda     _vbits
        sec
        sbc     nbits
        sta     _vbits
        txa
        ldx     #$00
        rts

.segment        "DATA"
min32:  .byte 32
        .byte 31
        .byte 30
        .byte 29
        .byte 28
        .byte 27
        .byte 26
        .byte 25
        .byte 24
        .byte 23
        .byte 22
        .byte 21
        .byte 20
        .byte 19
        .byte 18
        .byte 17
        .byte 16
        .byte 15
        .byte 14
        .byte 13
        .byte 12
        .byte 11
        .byte 10
        .byte 9
min8:   .byte 8
        .byte 7
        .byte 6
        .byte 5
        .byte 4
        .byte 3
        .byte 2
        .byte 1
        .byte 0

high_nibble:
    .repeat 256, I
        .byte I >> 4
    .endrep
