;
; File generated by cc65 v 2.19 - Git 51b946bf2
;
        .importzp       sp
        .importzp       tmp1, tmp2, tmp3, tmp4, ptr1
        .importzp       _prev_ram_irq_vector

        .import         decsp6
        .import         _fread
        .import         _bitbuf
        .import         _bitbuf_nohuff
        .import         _vbits
        .import         _cache_start
        .import         _cache_end
        .import         _ifp
        .import         _huff_ptr
        .export         _reset_bitbuff
        .export         _get_four_bits
        .export         _getbithuff

cur_cache_ptr = _prev_ram_irq_vector

.segment        "BSS"

_shift:
        .res        1,$00

; ---------------------------------------------------------------
; unsigned char __near__ __fastcall__ reset_bitbuff(void)
; ---------------------------------------------------------------

.segment        "LC"

.proc        _reset_bitbuff: near

.segment        "LC"

        stz     _bitbuf_nohuff
        stz     _vbits
        rts

.endproc

; ---------------------------------------------------------------
; unsigned char __near__ __fastcall__ get_four_bits(void)
; ---------------------------------------------------------------

.segment        "LC"

.proc        _get_four_bits: near

.segment        "LC"

        lda     _vbits
        bne     have_enough_vbits

        lda     _cache_end
        cmp     cur_cache_ptr
        bne     no_read_required
        ldx     _cache_end+1
        cpx     cur_cache_ptr+1
        bne     no_read_required
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
        lda     #$10
        sta     (sp),y
        dey
        lda     #0
        sta     (sp),y

        lda     _ifp
        ldx     _ifp+1
        jsr     _fread
no_read_required:
        lda     (cur_cache_ptr)
        sta     _bitbuf_nohuff

        inc     cur_cache_ptr
        bne     :+
        inc     cur_cache_ptr+1

:       ldx     #1
        stx     _vbits

        lsr     a
        lsr     a
        lsr     a
        lsr     a
        rts

have_enough_vbits:
        dec     _vbits
        lda     _bitbuf_nohuff
        and     #$0F

        rts

.segment        "BSS"

nbits:
        .res        1,$00

.endproc

; ---------------------------------------------------------------
; unsigned char __near__ __fastcall__ getbithuff (unsigned char n)
; ---------------------------------------------------------------

.segment        "LC"

.proc        _getbithuff: near

.segment        "LC"

        sta     nbits
        bne     have_nbits_h
        stz     _bitbuf
        stz     _bitbuf+1
        stz     _bitbuf+2
        stz     _bitbuf+3
        stz     _vbits
        tax
        rts
have_nbits_h:
        cmp     _vbits
        bcc     have_enough_vbits_h
        ldx     _bitbuf+2
        stx     _bitbuf+3
        ldx     _bitbuf+1
        stx     _bitbuf+2
        ldx     _bitbuf
        stx     _bitbuf+1
        stz     _bitbuf
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
        lda     #$10
        sta     (sp),y
        dey
        lda     #0
        sta     (sp),y

        lda     _ifp
        ldx     _ifp+1
        jsr     _fread
no_read_required_h:
        lda     _bitbuf
        clc
        adc     (cur_cache_ptr)
        sta     _bitbuf
        bcc     :+
        inc     _bitbuf+1
        bne     :+
        inc     _bitbuf+2
        bne     :+
        inc     _bitbuf+3

:       inc     cur_cache_ptr
        bne     :+
        inc     cur_cache_ptr+1

:       lda     #$08
        adc     _vbits
        sta     _vbits
have_enough_vbits_h:
        lda     #$20
        sec
        sbc     _vbits
        cmp     #24
        bcc     maybe_shift_16_h
        ldx     _bitbuf
        stx     tmp4
        stz     tmp3
        stz     tmp2
        stz     tmp1
        and     #$07
        beq     lshift_done_h
        tay
        txa                     ; tmp4

:       asl     a
        dey
        bpl     :-
        ror     a
        sta     tmp4
        bra     lshift_done_h
maybe_shift_16_h:
        cmp     #16
        bcc     maybe_shift_8_h
        ldx     _bitbuf+1
        stx     tmp4
        ldx     _bitbuf
        stx     tmp3
        stz     tmp2
        stz     tmp1
        and     #$07
        beq     lshift_done_h
        tay
        txa                     ; tmp3
:       asl     a
        rol     tmp4
        dey
        bne     :-
        sta     tmp3
        bra     lshift_done_h
maybe_shift_8_h:
        cmp     #8
        bcc     finish_lshift_h
        ldx     _bitbuf+2
        stx     tmp4
        ldx     _bitbuf+1
        stx     tmp3
        ldx     _bitbuf
        stx     tmp2
        stz     tmp1
finish_lshift_h:
        and     #$07
        beq     lshift_done_h
        tay

        lda     tmp1
:       asl     a
        rol     tmp2
        rol     tmp3
        rol     tmp4
        dey
        bne     :-
        sta     tmp1

lshift_done_h:
        lda     #32
        sec
        sbc     nbits
        cmp     #24
        bcc     maybe_rshift_16_h
        ldx     tmp4
        bra     rshift_done_h
maybe_rshift_16_h:
        cmp     #8
        bcc     maybe_rshift_8_h
        ldx     tmp3
        bra     rshift_done_h
maybe_rshift_8_h:
        cmp     #8
        bcc     finish_rshift_h
        ldx     tmp2
rshift_done_h:
        stx     tmp1
finish_rshift_h:
        ldx     #$00
        and     #$07
        beq     no_final_shift_h
        tay
        lda     tmp1

:       lsr     a
        dey
        bne     :-
        bra     do_huff_h
no_final_shift_h:
        lda     tmp1
do_huff_h:
        sta     tmp1
        asl     a
        bcc     :+
        inx
        clc

:       ldy     _huff_ptr+1
        beq     no_huff

        adc     _huff_ptr
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
        lda     tmp1
        ldx     #$00
        rts

.segment        "BSS"

nbits:
        .res        1,$00

.endproc
