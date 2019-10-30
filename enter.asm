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
	cmp     byte ptr [ds:si+3], 0h  ; we don't support nested frame enter
	jne		unhandled
	mov     ax, WORD PTR [cs:emuss_oldbp]
	xchg	ax, [bp + 4] ; replace caller flags by old bp (PUSH BP)

	add     sp, 4                 ; for PUSH BP
	mov     WORD PTR [cs:emuss_oldbp], sp  ; MOV BP, SP part of ENTER

	sub		sp, word ptr [si + 1] ; SUB SP,#imm16 part of ENTER
	add     si, 4
elcommon:
	sub		sp, 6
elcommon_:
	mov     bp, sp
	mov     [bp + 0], si          ; original IP
	mov     [bp + 2], ds          ; original CS
	mov     [bp + 4], ax          ; original flags
	jmp		emu_exit

emulate_leave:
	inc		si					  ; skip LEAVE opcode
	mov		ax, [bp + 4] 		  ; get original flags
	mov		sp, WORD PTR [cs:emuss_oldbp] ; MOV SP, BP part of LEAVE
	pop		WORD PTR [cs:emuss_oldbp]	  ; POP BP part of LEAVE
	jmp		elcommon

emulate_push16:
	mov		ax, word ptr [si + 1]
	inc		si
pushcommon:
	add		si,	2
	xchg	ax, [bp + 4] ; replace caller flags by old bp (PUSH BP)
	sub		sp, 2
	jmp		elcommon_

_EmulatingSS:
PUBLIC _EmulatingSS
	mov		WORD PTR [cs:emuss_oldbp], bp
	mov		WORD PTR [cs:emuss_oldsi], si
	mov		WORD PTR [cs:emuss_oldds], ds
	mov		WORD PTR [cs:emuss_oldax], ax
	mov		bp, sp
	mov		ds, [bp + 2] ; caller CS
	mov     si, [bp + 0] ; caller IP
	mov		al, [ds:si]
	cmp     al, 0C8h
	ja		above_enter
	je		emulate_enter
above_enter:
	cmp		al, 0C9h
	je		emulate_leave
	jmp		emu_exit

below_enter:
	cmp		al, 068h
	je		emulate_push16
	jb		below_push16
	cmp     al, 06Ah
	jne		between_6A_and_C8
	mov		al, [ds:si+1]
	cbw
	jmp		pushcommon
between_6A_and_C8:
below_push16:
emu_exit:
	mov		si, 1234h
	emuss_oldds = $-2
	mov		ds, si
	mov     si, 1234h
	emuss_oldsi = $-2
	mov     bp, 1234h
	emuss_oldbp = $-2
	mov     ax, 1234h
	emuss_oldax = $-2
	iret
END