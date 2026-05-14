;
; Copyright (C) 1996-2006 by Narech K. All rights reserved.
;
; Redistribution  and  use  in source and  binary  forms, with or without
; modification,  are permitted provided that the following conditions are
; met:
;
; 1.  Redistributions  of  source code  must  retain  the above copyright
; notice, this list of conditions and the following disclaimer.
;
; 2.  Redistributions  in binary form  must reproduce the above copyright
; notice,  this  list of conditions and  the  following disclaimer in the
; documentation and/or other materials provided with the distribution.
;
; 3. The end-user documentation included with the redistribution, if any,
; must include the following acknowledgment:
;
; "This product uses DOS/32 Advanced DOS Extender technology."
;
; Alternately,  this acknowledgment may appear in the software itself, if
; and wherever such third-party acknowledgments normally appear.
;
; 4.  Products derived from this software  may not be called "DOS/32A" or
; "DOS/32 Advanced".
;
; THIS  SOFTWARE AND DOCUMENTATION IS PROVIDED  "AS IS" AND ANY EXPRESSED
; OR  IMPLIED  WARRANTIES,  INCLUDING, BUT  NOT  LIMITED  TO, THE IMPLIED
; WARRANTIES  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
; DISCLAIMED.  IN  NO  EVENT SHALL THE  AUTHORS  OR  COPYRIGHT HOLDERS BE
; LIABLE  FOR  ANY DIRECT, INDIRECT,  INCIDENTAL,  SPECIAL, EXEMPLARY, OR
; CONSEQUENTIAL  DAMAGES  (INCLUDING, BUT NOT  LIMITED TO, PROCUREMENT OF
; SUBSTITUTE  GOODS  OR  SERVICES;  LOSS OF  USE,  DATA,  OR  PROFITS; OR
; BUSINESS  INTERRUPTION) HOWEVER CAUSED AND  ON ANY THEORY OF LIABILITY,
; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
; OTHERWISE)  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
; ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;
;

PushState


.386p
;=============================================================================
; v9.12.2: jump-table dispatch on AL. INT 33h handlers all require AH=0,
; so we test AH first and fall through if nonzero. The table is then
; indexed by AL. EBP is the scratch register.
;
_int33:	cld
	push	ds es
	pushad

	test	ah,ah			; INT 33h handlers all require AH=0
	jnz	@__go33
	movzx	ebp,al
	jmp	word ptr cs:int33h_jt[ebp*2]


@__go33:popad
	pop	es ds
	db	66h
	jmp	cs:_int33_ip




;=============================================================================
; Define Graphics Cursor
; In:	BX = column of cursor hotspot in bitmap
;	CX = row of cursor hotspot in bitmap
;	ES:EDX = mask bitmap
;
@__0009h:
	push	es
	pop	ds
	sub	esp,32h
	mov	ebp,esp
	mov	esi,edx
	mov	es,cs:_sel_zero
	movzx	edi,cs:_seg_mus
	mov	wptr [ebp+1Ch],ax
	mov	wptr [ebp+18h],cx
	mov	wptr [ebp+10h],bx
	mov	wptr [ebp+22h],di
	mov	wptr [ebp+14h],0
	shl	edi,4
	mov	ecx,10h
	rep	movs dptr es:[edi],[esi]
	call	int33h
	add	esp,32h
	jmp	@__ok



;=============================================================================
; Define Interrupt Subroutine
; In:	CX = call mask
;	ES:EDX = far pointer to routine
;
@__000Ch:
	call	_mus_int_def
	jmp	@__ok


;=============================================================================
; Exchange Defined Interrupt Subroutine
; In:	CX = call mask
;	ES:EDX = far pointer to routine
; Out:	CX = call mask
;	ES:EDX = far pointer to routine
;
@__0014h:
	mov	si,wptr cs:_mus_sel
	mov	edi,dptr cs:_mus_off
	call	_mus_int_def
	mov	[esp+14h],edi
	mov	[esp+20h],si
	jmp	@__ok


;=============================================================================
; Define Interrupt Subroutine
; In:	CX = call mask
;	ES:EDX = far pointer to routine
;
@__0018h:
	call	_mus_int_def
	mov	[esp+1Ch],eax
	jmp	@__ok


;=============================================================================
; Return Defined Interrupt Subroutine
; In:	CX = call mask
; Out:	BX:EDX = far pointer to routine
;
@__0019h:
	mov	ax,wptr cs:_mus_sel
	mov	edx,dptr cs:_mus_off
	mov	[esp+14h],edx
	mov	[esp+10h],ax
	jmp	@__ok



;-----------------------------------------------------------------------------
_mus_int_def:
	sub	esp,32h
	mov	ebp,esp
	mov	[ebp+1Ch],ax
	mov	[ebp+18h],cx
	mov	ds,cs:_sel_ds
	xor	eax,eax
	mov	_mus_off,edx
	mov	_mus_sel,es
	mov	ax,es
	or	eax,edx
	jz	@@1
	mov	ax,_seg_ds
	mov	dx,offs _mus_int_rm
@@1:	mov	wptr [ebp+14h],dx
	mov	wptr [ebp+22h],ax
	cli
	call	int33h
	movzx	eax,wptr [ebp+1Ch]
	add	esp,32h
	sti
	ret

_mus_int_rm:
	cmp	cs:_mus_data,0
	mov	cs:_mus_data,1
	jnz	@@1
	jmp	dword ptr cs:_mus_backoff
@@1:	retf

_mus_int_pm:
	cld
	pushad
	push	ds es fs gs
	xor	eax,eax

	mov	ax,ds
	mov	ds,cs:_sel_ds
	mov	ds:_mus_esp,esp
	mov	ds:_mus_ss,ss
	mov	ds,ax

	mov	ax,ss
	lar	eax,eax
	shr	eax,23
	jc	@@1
	movzx	esp,sp

@@1:	mov	ax,cs:_seg_ds
	mov	wptr es:[edi+2Ch],ax
	mov	wptr es:[edi+2Ah],offs @@done

	movzx	eax,wptr es:[edi+1Ch]
	movzx	ecx,wptr es:[edi+18h]
	movzx	edx,wptr es:[edi+14h]
	movzx	ebx,wptr es:[edi+10h]
	movzx	esi,wptr es:[edi+04h]
	movzx	edi,wptr es:[edi+00h]
	pushfd
	call	fword ptr cs:_mus_off

	lss	esp,fword ptr cs:_mus_esp

	pop	gs fs es ds
	popad
	iretd
@@done:	mov	cs:_mus_data,0
	retf



;=============================================================================
; Save Driver State
; In:	BX = size of buffer
;	ES:EDX = buffer for driver state
;
@__0016h:
	sub	esp,32h
	mov	ebp,esp
	mov	edi,edx
	mov	[ebp+1Ch],ax
	mov	ax,cs:_seg_buf
	mov	wptr [ebp+22h],ax
	mov	wptr [ebp+14h],0
	call	int33h
	mov	ds,cs:_sel_ds
	mov	esi,_lobufbase
	mov	ecx,_mus_size
	rep	movs bptr es:[edi],[esi]
	add	esp,32h
	jmp	@__ok


;=============================================================================
; Restore Driver State
; In:	BX = size of buffer
;	ES:EDX = buffer containing saved state
;
@__0017h:
	push	es
	pop	ds
	sub	esp,32h
	mov	ebp,esp
	mov	esi,edx
	mov	[ebp+1Ch],ax
	mov	ax,cs:_seg_buf
	mov	wptr [ebp+22h],ax
	mov	wptr [ebp+14h],0
	mov	es,cs:_sel_ds
	mov	edi,cs:_lobufbase
	mov	ecx,cs:_mus_size
	rep	movs bptr es:[edi],[esi]
	call	int33h
	add	esp,32h
	jmp	@__ok


;=============================================================================
; Enable Mouse Driver
; In:	-
;
@__0020h:
	sub	esp,32h
	mov	ebp,esp
	mov	[ebp+1Ch],ax
	call	int33h
	add	esp,32h
	mov	wptr [esp+1Ch],-1
	jmp	@__ok


;=============================================================================
; INT 33h jump table -- 256 entries indexed by AL (only when AH=0). v9.12.2.
;
		evendata
int33h_jt	label word
	dw 9     DUP (offset @__go33)		; 00..08
	dw	offset @__0009h			; 09
	dw 2     DUP (offset @__go33)		; 0A..0B
	dw	offset @__000Ch			; 0C
	dw 7     DUP (offset @__go33)		; 0D..13
	dw	offset @__0014h			; 14
	dw	offset @__go33			; 15
	dw	offset @__0016h			; 16
	dw	offset @__0017h			; 17
	dw	offset @__0018h			; 18
	dw	offset @__0019h			; 19
	dw 6     DUP (offset @__go33)		; 1A..1F
	dw	offset @__0020h			; 20
	dw 223   DUP (offset @__go33)		; 21..FF


PopState
