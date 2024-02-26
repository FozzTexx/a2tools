
        .importzp             ptr1, ptr2, ptr3

        .import               _serial_read_byte_no_irq
        .import               _simple_serial_setup_no_irq_regs
        .import               _simple_serial_set_irq
        .import               _simple_serial_flush
        .import               _serial_putc_direct
        .import               _cgetc

        .export               _surl_stream


KBD     :=      $C000   ; Read keyboard
KBDSTRB :=      $C010   ; Clear keyboard strobe

MAX_OFFSET =126
NUM_BASES  =(8192/MAX_OFFSET)+1

calc_bases:
        sta     ptr1
        sty     ptr1+1

        ldy     #0
        lda     #$00

        clc

next_base:
        sta     (ptr1),y
        iny
        pha
        txa
        sta     (ptr1),y
        pla
        iny

        adc     #(MAX_OFFSET)
        bcc     :+
        inx
        clc
:       cpy     #(NUM_BASES*2)
        bcc     next_base
        rts

handle_kbd:
        cmp    #' '
        bne    :+
        jsr    _serial_putc_direct ; Pause
        jsr    _cgetc           ; Wait for play.
        lda    #$00
:       cmp    #$1B             ; Escape
        bne    :+
        sta    Stop
:       jsr    _serial_putc_direct
        ldy    #$00             ; Main loop expects Y 0 there
        rts

frame_done:
.ifdef DOUBLE_BUFFER

        ldx     #$54            ; Double buffer
        lda     #<(ptr3)
        cpx     page_softswitch+1
        bne     :+
        inx
        lda     #<(ptr2)
:       stx     page_softswitch+1
        sta     base_ptr_a+1
        sta     base_ptr_b+1
        ldx     #$00            ; X (offset) is supposed to be 0 after this
page_softswitch:
        bit     $C054
.endif
        lda     KBD
        bpl     :+
        and     #$7F            ; Clear high bit
        bit     KBDSTRB         ; Clear keyboard strobe
        jmp     handle_kbd
:       lda     #$00
        jmp     _serial_putc_direct

cleanup:
        lda     #$01
        jsr     _simple_serial_set_irq
        jsr     _simple_serial_flush
        lda     #$00
        tax
        rts

_surl_stream:
        lda     #$00
        sta     Stop

        lda     #<(base_addr1)  ; Calculate bases for HGR page 1
        ldy     #>(base_addr1)
        sta     ptr2
        sty     ptr2+1
        ldx     #$20
        jsr     calc_bases

.ifdef DOUBLE_BUFFER

        lda     #<(base_addr2)  ; Calculate bases for HGR page 2
        ldy     #>(base_addr2)
        sta     ptr3
        sty     ptr3+1
        ldx     #$40
        jsr     calc_bases

.endif

        jsr     _simple_serial_setup_no_irq_regs
        lda     #$00
        jsr     _simple_serial_set_irq

        jsr     _serial_read_byte_no_irq
        bit     $C052           ; Clear HGR mix
        cmp     #$27            ; SURL_ANSWER_STREAM_START
        beq     :+
        lda     #$FF
        tax
        rts

:       ldx     #$00            ; Offset
        lda     #($00|$80)      ; Base
        jmp     loop

set_base:
        cmp     #$FF            ; Is it a rep in reality ?
        beq     do_rep
        and     #%01111111      ; Get rid of the sign
        asl     a               ; shift for array index
        tay
        bne     :+
        jsr     frame_done      ; Sync point, send $00 and check kbd
        lda     Stop
        beq     :+
        jmp     cleanup
:       cmp     #((NUM_BASES+1)*2) ; End of stream?
        bne     :+
        jmp     cleanup
:       
base_ptr_a:
        lda     (ptr2),y
        sta     store_dest+1
        iny
base_ptr_b:
        lda     (ptr2),y
        sta     store_dest+2

loop:
        ldy     #$01
        jsr     _serial_read_byte_no_irq
        bpl     store_dest
        cmp     #$FF            ; Is it a rep?
        bne     set_offset
do_rep:
        ; handle repetitions
        jsr     _serial_read_byte_no_irq ; get repetitions
        tay
        jsr     _serial_read_byte_no_irq ; get value
store_dest:
        sta     $FFFF,x
        inx
        dey
        bne    store_dest
        jmp    loop

set_offset:
        and     #%01111111      ; Get rid of sign
        tax                     ; set offset
        jsr     _serial_read_byte_no_irq
        bmi     set_base        ; We also have a new base (or repetition?)
        jmp     store_dest      ; Otherwise it's a value


        .bss
base_addr1:     .res (NUM_BASES*2)
base_addr2:     .res (NUM_BASES*2)
Stop:           .res 1
