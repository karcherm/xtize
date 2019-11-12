.MODEL LARGE

DEBUG = 1

.CODE

; Wrapper for int16 that ensures calling INT16 does not clear the TF.
; Many PC BIOSes terminate function 01 (Poll keyboard status) with RETF 2
; instead of IRET to pass the zero flag to the caller. This misses re-setting
; the TF, thus effectively disabling the emulator.
HelperInt16:
    pushf
    db      09Ah    ; CALL FAR
oldint16ptr dd ?
    push    bp
    mov     bp, sp
    push    ax
    lahf
    mov     [bp + 6], ah    ; Low 8 bits include all status flags except V
    pop     ax
    pop     bp
    iret

oldsp   dw ?
oldss   dw ?

_EnterSingleStep:
PUBLIC  _EnterSingleStep
    push    bp
    mov     bp,sp
    push    ds
    ; Install TF-resetting helper
    mov     ax, 3516h
    int     21h
    mov     WORD PTR [cs:oldint16ptr], bx
    mov     WORD PTR [cs:oldint16ptr+2], es
    mov     ax, 2516h
    push    cs
    pop     ds
    mov     dx, OFFSET HelperInt16
    int     21h
    ; Activate callee PSP
    les     si, [bp + 6]      ; state block
    mov     bx, [es:si + 22]  ; new PSP
    mov     ah, 50h
    int     21h

    ; Set up callee entry point registers (including TF) and save old stack
    mov     bx, [es:si + 22]
    mov     di, [es:si + 14]  ; new stack pointer
    mov     [cs:oldsp], sp
    mov     [cs:oldss], ss
    mov     ss, [es:si + 16]
    mov     sp, di
    xor     ax, ax
    push    ax          ; COM return address (PSP:0)
    mov     ah, 3       ; Set IF and TF
    push    ax
    push    [WORD PTR es:si + 20]       ; new CS:IP
    push    [WORD PTR es:si + 18]
    mov     ds, bx
    mov     es, bx
    mov     [ds:WORD PTR 0Ch], cs
    mov     [ds:WORD PTR 0Ah], offset RETURNTO
    iret
RETURNTO:
    ; Restore stack
    mov     ss, [cs:oldss]
    mov     sp, [cs:oldsp]
    ; Uninstall helpers
    mov     ax, 2516h
    lds     dx, DWORD PTR [cs:oldint16ptr]
    int     21h
    ; Return to caller environment
    pop     ds
    pop     bp
    retf

count   dd  0
_CountingSS:
PUBLIC _CountingSS
    add     [cs:WORD PTR count], 1
    adc     [cs:WORD PTR count+2], 0
    iret

_GetCount:
PUBLIC _GetCount
    mov     ax, [cs:WORD PTR count]
    mov     dx, [cs:WORD PTR count+2]
    retf

dispatch_table2:
  idx_emu_exit            = $ - OFFSET dispatch_table2
    dw      OFFSET emu_exit
  idx_emulate_enter       = $ - OFFSET dispatch_table2
    dw      OFFSET emulate_enter
  idx_emulate_leave       = $ - OFFSET dispatch_table2
    dw      OFFSET emulate_leave
  idx_emulate_push16      = $ - OFFSET dispatch_table2
    dw      OFFSET emulate_push16
  idx_emulate_push8       = $ - OFFSET dispatch_table2
    dw      OFFSET emulate_push8
  idx_emulate_imul        = $ - OFFSET dispatch_table2
    dw      OFFSET emulate_imul
  idx_emulate_shiftrotate = $ - OFFSET dispatch_table2
    dw      OFFSET emulate_shiftrotate
  idx_emulate_movsreg     = $ - OFFSET dispatch_table2
    dw      OFFSET emulate_movsreg
  idx_emulate_pop_es      = $ - OFFSET dispatch_table2
    dw      OFFSET emulate_pop_es
  idx_emulate_pop_ds      = $ - OFFSET dispatch_table2
    dw      OFFSET emulate_pop_ds

dispatch_table1:
    db      256 dup (idx_emu_exit)
  org dispatch_table1 + 07h
    db      idx_emulate_pop_es        ; POP ES
  org dispatch_table1 + 37h
    db      idx_emulate_pop_ds        ; POP DS
  org dispatch_table1 + 068h
    db      idx_emulate_push16        ; PUSH imm16
    db      idx_emulate_imul          ; IMUL r16, r/m16, imm16
    db      idx_emulate_push8         ; PUSH imm8
    db      idx_emulate_imul          ; IMUL r16, r/m16, imm8
  org dispatch_table1 + 08Eh
    db      idx_emulate_movsreg       ; MOV sreg, r/m16
  org dispatch_table1 + 0C0h
    db      idx_emulate_shiftrotate   ; shift/rotate r8, imm8
    db      idx_emulate_shiftrotate   ; shift/rotate r16, imm8
  org dispatch_table1 + 0C8h
    db      idx_emulate_enter         ; ENTER
    db      idx_emulate_leave         ; LEAVE
  org dispatch_table1 + 100h

uhmsg:
    db      "286 emulation failed", 0
unhandled:
    mov     ah, 0eh
    mov     si, offset uhmsg
uhloop:
    lods    BYTE PTR [cs:si]
    int     10h
    cmp     al, 0
    jne     uhloop
    hlt
    jmp     $-1

emulate_enter:
    lodsw
    mov     WORD PTR [cs:enter_immed], ax
    lodsb
    cmp     al, 0                 ; we don't support nested frame enter
    jne     unhandled
    mov     [bp + 0], OFFSET enter_inject
    jmp     exit_for_reenter

emulate_leave:
    mov     [bp + 0], OFFSET leave_inject
    jmp     exit_for_reenter

emulate_push16:
    lodsw
pushcommon:
    mov     WORD PTR [cs:push_immed], ax
    mov     [bp + 0], OFFSET push_inject
    jmp     exit_for_reenter

IF DEBUG
printhex16:
    xchg    ah,al
    call    printhex8
    xchg    ah,al
printhex8:
    push    ax
    shr     ax,1
    shr     ax,1
    shr     ax,1
    shr     ax,1
    call    printhex4
    pop     ax
printhex4:
    and     al, 0Fh
    add     al, 90h
    daa
    adc     al, 40h
    daa
    mov     [es:bx], al
    mov     BYTE PTR [es:bx+1], 0Fh
    add     bx,2
    ret
ENDIF

; Entry-Points:
;  emu_reenter - jump here if an injected function is finished.
;                store oldbp before jumping here, and create a correct
;                interrupt stack frame returning to the final target
_EmulatingSS:
PUBLIC _EmulatingSS
    mov     WORD PTR [cs:emuss_oldbp], bp
emu_reenter:
    mov     WORD PTR [cs:emuss_oldsi], si
    mov     WORD PTR [cs:emuss_oldds], ds
    mov     WORD PTR [cs:emuss_oldax], ax
    mov     WORD PTR [cs:emuss_oldbx], bx
    mov     bp, sp
    cld
    mov     ds, [bp + 2] ; caller CS
    mov     si, [bp + 0] ; caller IP
IF DEBUG
    push    es
    mov     ax, 0B800h
    mov     es, ax
    mov     bx, 0
    mov     ax, ds
    call    printhex16
    mov     ax, si
    call    printhex16
    mov     bx, 200h
    dec     bx
    jnz     $-1
    pop     es
ENDIF
    lodsb
    mov     ah, 0
    mov     bx, ax
    mov     bl, BYTE PTR cs:[bx + offset dispatch_table1]
    jmp     WORD PTR cs:[bx + offset dispatch_table2]

emulate_push8:
    lodsb
    cbw
    jmp     pushcommon

emulate_shiftrotate:
    add     al, 12h     ; C0 -> D2, C1 -> D3
    mov     BYTE PTR [cs:sr_patch_opcode], al
    add     al, 86h - 0D2h ; generate 8-bit/16-bit XCHG opcode
    mov     BYTE PTR [cs:sr_xchg1], al
    mov     BYTE PTR [cs:sr_xchg2], al
    lodsb               ; Fetch mod/RM byte
    mov     ah, al
    or      al, 0C0h    ; set memory operand to AX/AL (for shift/rotate)
    and     al, 0F8h
    mov     BYTE PTR [cs:sr_patch_opcode+1], al
    and     ah, 0C7h    ; set register operand to AX (for XCHG instructions)
    mov     BYTE PTR [cs:sr_xchg2 + 1], ah
    mov     BYTE PTR [cs:sr_xchg1 + 1], ah
    cmp     ah, 06h     ; special encoding for baseless 16-bit address
    jne     not_mem16
    mov     ah, 80h     ; replace mode by something with a 16-bit offset
not_mem16:
    sub     ah, 40h     ; 00..3F = 8bit, 40..7F = 16bit, 80..FF = nothing
    js      no_offset
    cmp     ah, 40h
    jae     offset16
    lodsb
    mov     ah, 90h
    jmp     SHORT ofs_common
offset16:
    lodsw
    jmp     SHORT ofs_common
no_offset:
    mov     ax, 9090h
ofs_common:
    mov     WORD PTR [cs:sr_xchg2 + 2], ax
    mov     WORD PTR [cs:sr_xchg1 + 2], ax
    lodsb
    mov     BYTE PTR [cs:sr_patch_count], al
    mov     [bp + 0], OFFSET sr_inject ; return IP
exit_for_reenter:
    mov     [bp + 2], cs ; return CS
    and     BYTE PTR [bp + 5], NOT 1        ; Clear TF
    mov     WORD PTR [cs:reenter_offset], si
    mov     WORD PTR [cs:reenter_segment], ds
emu_exit:
    mov     si, 1234h
    emuss_oldds = $-2
    mov     ds, si
    mov     si, 1234h
    emuss_oldsi = $-2
    mov     bp, 1234h
    emuss_oldbp = $-2
    mov     ax, 1234h
    emuss_oldax = $-2
    mov     bx, 1234h
    emuss_oldbx = $-2
    iret

emulate_movsreg:
    lodsb               ; Fetch mod/RM byte
    mov     BYTE PTR [cs:movsreg_instruction+1], al
    xor     al, 010h    ; Fudge register number, so that SS gets zero
    test    al, 38h     ; Z if destionation of SS
    jz      emu_exit    ; -> execute it natively.
    and     al, 0C7h    ; clear destination register
    cmp     al, 06h     ; special encoding for baseless 16-bit address
    jne     movsreg_not_mem16
    mov     al, 80h     ; replace mode by something with a 16-bit offset
movsreg_not_mem16:
    sub     al, 40h     ; 00..3F = 8bit, 40..7F = 16bit, 80..FF = nothing
    js      movsreg_no_offset
    cmp     al, 40h
    jae     movsreg_offset16
    lodsb
    mov     ah, 90h
    jmp     SHORT movsreg_ofs_common
movsreg_offset16:
    lodsw
    jmp     SHORT movsreg_ofs_common
movsreg_no_offset:
    mov     ax, 9090h
movsreg_ofs_common:
    mov     WORD PTR [cs:movsreg_instruction+2], ax
    mov     [bp + 0], OFFSET movsreg_inject ; return IP
    jmp     exit_for_reenter

emulate_pop_ds:
    mov     [bp + 0], OFFSET pop_ds_inject
    jmp     exit_for_reenter

emulate_pop_es:
    mov     [bp + 0], OFFSET pop_es_inject
    jmp     exit_for_reenter

emulate_imul:
    mov     ah, al
    lodsb
    cmp     al, 0C0h
    jb      imul_nonsrcax
    test    al, 7
    jnz     imul_nonsrcax
    mov     BYTE PTR [cs:imul_srcax_mov + 1], al
    shr     al, 1
    shr     al, 1
    shr     al, 1
    add     al, 90h - (0C0h SHR 3)
    mov     BYTE PTR [cs:imul_srcax_xchg], al
    test    ah, 2
    mov     bx, offset imul_srcax_inject
    jmp     SHORT imul_do_immed
imul_nonsrcax:
    test    al, 38h
    jnz     imul_nonax
    or      al, 28h
    mov     BYTE PTR [cs:imul_dstax_instruction+1], al
    sub     al, 40h
    xchg    ax, bx
    mov     ax, 9090h
    js      imul_dstax_ofsdone
    test    al, 40h
    jz      imul_dstax_ofs8
    lodsw
    jmp     SHORT imul_dstax_ofsdone
imul_dstax_ofs8:
    lodsb
imul_dstax_ofsdone:
    mov     WORD PTR [cs:imul_dstax_instruction+2], ax
    test    bh, 2
    mov     bx, offset imul_dstax_inject
    jmp     SHORT imul_do_immed
imul_nonax:
    mov     bx, ax
    and     al, 38h
    shr     al, 1
    shr     al, 1
    shr     al, 1
    add     al, 90h
    mov     BYTE PTR [cs:imul_nonax_xchg], al
    xchg    ax, bx
    and     al, 0C7h
    or      al, 28h
    mov     BYTE PTR [cs:imul_nonax_instruction+1], al
    sub     al, 40h
    xchg    ax, bx
    mov     ax, 9090h
    js      imul_nonax_ofsdone
    test    al, 40h
    jz      imul_nonax_ofs8
    lodsw
    jmp     SHORT imul_nonax_ofsdone
imul_nonax_ofs8:
    lodsb
imul_nonax_ofsdone:
    mov     WORD PTR [cs:imul_nonax_instruction+2], ax
    test    bh, 2
    mov     bx, offset imul_nonax_inject
imul_do_immed:
    jnz     short imul_immed8
    lodsw
    jmp     short imul_immed_done
imul_immed8:
    lodsb
    cbw
imul_immed_done:
    mov     WORD PTR [cs:imul_immed], ax
    mov     [bp+0], bx
    jmp     exit_for_reenter

; This code gets injected after IRET by patching the return address
; to point here and patching the original return address into this
; code. This design was chosen, because
;  1. rcl/rcr takes the carry flag as input, so some kind of popf is
;     needed anyway
;  2. flag output is relevant, so we don't want to end with IRET
;  3. we want all registers restored, so we can blindly copy the
;     addressing scheme from the 286 instruction into the xchg
;     instructions
; This design is broken, because
;  1. after IRET, the IF is set, so an interrupt might occur while running
;     the self-modifying, non-reentrant code here. This does not matter
;     until we add a TF setting interrupt handler wrapper, though.
sr_inject:
    sr_xchg1 = $
    xchg    ax, WORD PTR [ds:1234h]     ; TODO: segment prefixes
    push    cx
    mov     cl, 12h
    sr_patch_count = $-1
    sr_patch_opcode = $
    shl     ax, cl
    pop     cx
    sr_xchg2 = $
    xchg    ax, WORD PTR [ds:1234h]     ; TODO: segment prefixes
prepare_reenter:
    pushf
    mov     WORD PTR [cs:emuss_oldbp], bp
    mov     bp, sp
    or      BYTE PTR [bp + 1], 1        ; Re-Set TF
    mov     bp, 1234h
  reenter_segment = $-2
    push    bp
    mov     bp, 5678h
  reenter_offset  = $-2
    push    bp
    jmp     emu_reenter

imul_nonax_inject:
    push    ax
    push    dx
    mov     ax, 1234h
  imul_immed             = $-2
  imul_nonax_instruction = $
    imul    WORD PTR ds:1234h
    pop     dx
  imul_nonax_xchg        = $
    xchg    ax, bx
    pop     ax
    jmp     prepare_reenter

imul_dstax_inject:
    push    dx
    mov     ax, WORD PTR [cs:imul_immed]
  imul_dstax_instruction = $
    imul    WORD PTR ds:1234h
    pop     dx
    jmp     prepare_reenter

imul_srcax_inject:
  imul_srcax_mov  = $
    mov     ax, [bx]
    push    dx
    imul    WORD PTR [cs:imul_immed]
    pop     dx
  imul_srcax_xchg = $
    xchg    ax, bx
    jmp     prepare_reenter

push_immed  dw ?
push_inject:
    push    WORD PTR [cs:push_immed]
    jmp     prepare_reenter

enter_inject:
    push    bp
    mov     bp, sp
    sub     sp, 1234h
  enter_immed = $-2
    jmp     prepare_reenter

leave_inject:
    mov     sp, bp
    pop     bp
    jmp     prepare_reenter

movsreg_inject:
  movsreg_instruction = $
    mov     ds, WORD PTR ds:1234h
    jmp     prepare_reenter

pop_es_inject:
    pop     es
    jmp     NEAR PTR prepare_reenter

pop_ds_inject:
    pop     ds
    jmp     NEAR PTR prepare_reenter
END