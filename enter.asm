.MODEL LARGE

.CODE
oldsp	dw ?
oldss	dw ?

_EnterSingleStep:
PUBLIC	_EnterSingleStep
	push 	bp
	mov  	bp,sp
	push	ds
	les		si, [bp + 6]   	  ; state block
	mov		bx, [es:si + 22]  ; new PSP
	mov		ah, 50h
	int		21h

	mov		bx, [es:si + 22]
	mov		di, [es:si + 14]  ; new stack pointer
	mov		[cs:oldsp], sp
	mov		[cs:oldss], ss
	mov		ss, [es:si + 16]
	mov 	sp, di
	xor     ax, ax
	push    ax  		; COM return address (PSP:0)
	mov		ah, 3       ; Set IF and TF
	push    ax
	push	[WORD PTR es:si + 20]       ; new CS:IP
	push	[WORD PTR es:si + 18]
	mov 	ds, bx
	mov 	es, bx
	mov 	[ds:WORD PTR 0Ch], cs
	mov     [ds:WORD PTR 0Ah], offset RETURNTO
	iret
RETURNTO:
	mov		ss, [cs:oldss]
	mov		sp, [cs:oldsp]
	pop		ds
	pop		bp
	retf

count	dd	0
_CountingSS:
PUBLIC _CountingSS
	add     [cs:WORD PTR count], 1
	adc     [cs:WORD PTR count+2], 0
	iret

_GetCount:
PUBLIC _GetCount
	mov		ax, [cs:WORD PTR count]
	mov		dx, [cs:WORD PTR count+2]
	retf

; Error message with courtesy to a well-known un-fellow from the MBR
uhmsg:
	db 		"286 CHECK", 0
unhandled:
	mov		ax,1h
	int		10h
	mov		ah, 0eh
	mov		si, offset uhmsg
uhloop:
	lods    BYTE PTR [cs:si]
	int		10h
	cmp		al, 0
	jne		uhloop
	hlt
	jmp 	$-1

emulate_enter:
	cmp     byte ptr [ds:bx+3], 0h  ; we don't support nested frame enter
	jne		unhandled
	mov		WORD PTR [cs:emuenter_oldax], ax
	mov     ax, WORD PTR [cs:emuss_oldbp]
	xchg	ax, [bp + 4] ; replace caller flags by old bp (PUSH BP)

	add     sp, 4                 ; for PUSH BP
	mov     WORD PTR [cs:emuss_oldbp], sp  ; MOV BP, SP part of ENTER
	sub		sp, 6

	sub		sp, word ptr [bx + 1] ; SUB SP,#imm16 part of ENTER
	add     bx, 4
elcommon:
	mov     bp, sp
	mov     [bp + 0], bx          ; original IP
	mov     [bp + 2], ds          ; original CS
	mov     [bp + 4], ax          ; original flags
	mov     ax, 1234h
	emuenter_oldax = $-2
	jmp		emu_exit

emulate_leave:
	inc		bx					  ; skip LEAVE opcode
	mov		WORD PTR [cs:emuenter_oldax], ax
	mov		ax, [bp + 4] 		  ; get original flags
	mov		sp, WORD PTR [cs:emuss_oldbp] ; MOV SP, BP part of LEAVE
	pop		WORD PTR [cs:emuss_oldbp]	  ; POP BP part of LEAVE
	sub		sp, 6
	jmp		elcommon

_EmulatingSS:
PUBLIC _EmulatingSS
	mov		WORD PTR [cs:emuss_oldbp], bp
	mov		WORD PTR [cs:emuss_oldbx], bx
	mov		WORD PTR [cs:emuss_oldds], ds
	mov		bp, sp
	mov		ds, [bp + 2] ; caller CS
	mov     bx, [bp + 0] ; caller IP
	cmp     byte ptr [ds:bx], 0C8h
	ja		above_enter
	je		emulate_enter
above_enter:
	cmp		byte ptr [ds:bx], 0C9h
	je		emulate_leave
below_enter:
emu_exit:
	mov		bx, 1234h
	emuss_oldds = $-2
	mov		ds, bx
	mov     bx, 1234h
	emuss_oldbx = $-2
	mov     bp, 1234h
	emuss_oldbp = $-2
	iret
END