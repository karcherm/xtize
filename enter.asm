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
END