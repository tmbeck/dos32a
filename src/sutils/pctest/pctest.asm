;
; Copyright (C) 1996-2002 Supernar Systems, Ltd. All rights reserved.
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

		.486p
		.MODEL flat
		LOCALS
		JUMPS

TIMER	= 10000		; timer setup value
MEMORY	= 300*1024	; 150KB + 150KB = 300KB to overcome 256KB cache limit
VMEMORY	= 64*1024	; 64KB video memory
PATTERN	= 01010101h

EXT_UNKNOWN	= -1
EXT_DOS32A	= 0
EXT_PMODEW	= 1
EXT_PMODEWNEW	= 2
EXT_DOS4G	= 3
EXT_DOS4GW	= 4
EXT_CAUSEWAY	= 5
EXT_WINDOWS	= 6
EXT_EOS		= 7

PUBLIC	setvideomode_, gotoxy_
PUBLIC	get_cpu_type_, get_cpu_id_
PUBLIC	get_fpu_type_, get_fpu_info_
PUBLIC	get_sys_type_, get_extender_type_, get_dpmi_flags_
PUBLIC	get_himem_size_, get_lomem_size_, get_total_size_
PUBLIC	get_pmodew_ver_
PUBLIC	get_cpl_, get_iopl_

PUBLIC	test_cpu_
PUBLIC	test_fpu_
PUBLIC	test_int_
PUBLIC	test_irq_
PUBLIC	test_risc_
PUBLIC	test_priv_
PUBLIC	test_low_movsw_, test_low_movsd_
PUBLIC	test_high_movsw_, test_high_movsd_
PUBLIC	test_vid_movsw_, test_vid_movsd_
PUBLIC	test_low_stosw_, test_low_stosd_
PUBLIC	test_high_stosw_, test_high_stosd_
PUBLIC	test_vid_stosw_, test_vid_stosd_

PUBLIC	calibrate_tsc_		; v9.12.1: rdtsc-based timer init/calibration
PUBLIC	has_tsc_, tsc_freq_hz_

;extrn	Debug_		: near
include	stddef.inc

.DATA
; v9.12.1 -- TSC-based timing additions.
; calibrate_tsc_ probes CPUID for the TSC feature flag, and if present,
; measures CPU clock speed against PIT channel 2 to compute the cycles-
; per-PIT-tick scaling factor. The 12 memory benchmarks (test_low/high/vid_*)
; then use TIMER_START / TIMER_STOP macros which return PIT-equivalent units
; either way, so main.c's existing PIT-Hz math (timer_time = 1193181)
; works unchanged.
;
; test_int_ and test_irq_ stay on direct PIT use; their PIT setup spans a
; mode-switch round-trip (PM->RM->PM via int 80h) and the RM handler reads
; the PIT directly. Converting those would require a separate cross-mode
; clock sync; the relative numbers there are already meaningful as-is.

has_tsc		db 0	; nonzero if rdtsc available + calibrated
cycles_per_tick	dd 0	; rdtsc cycles per PIT tick (= cpu_clock_hz / 1193181)
tsc_freq_hz	dd 0	; measured CPU clock frequency in Hz (informational)
tsc_start_lo	dd 0	; rdtsc snapshot - low 32 bits
tsc_start_hi	dd 0	; rdtsc snapshot - high 32 bits

.CODE

;=============================================================================
; TIMER_START / TIMER_STOP macros.
;
; Replaces the inline-PIT-program/inline-PIT-read pattern used by the 12
; memory benchmarks. With TSC: snapshots rdtsc into tsc_start_*, on stop
; computes (delta_cycles / cycles_per_tick) and returns it in EAX. Without
; TSC: falls through to the legacy PIT channel-2 program/read. Either
; way EAX is loaded with a PIT-equivalent tick count on return from STOP.
;
; Clobbers: EAX, EDX. Preserves: ECX, ESI, EDI, EBX. Callers don't need
; to save state around these — same contract as the inline-PIT code.

TIMER_START MACRO
	LOCAL @@pit, @@done
	cmp	byte ptr [has_tsc],0
	jz	@@pit
	rdtsc
	mov	[tsc_start_lo],eax
	mov	[tsc_start_hi],edx
	jmp	@@done
@@pit:	mov	al,0B6h
	out	43h,al
	in	al,61h
	or	al,01h
	out	61h,al
	xor	al,al
	out	42h,al
	out	42h,al
@@done:
ENDM

TIMER_STOP MACRO
	LOCAL @@pit, @@tsc_done, @@done
	cmp	byte ptr [has_tsc],0
	jz	@@pit
	rdtsc
	sub	eax,[tsc_start_lo]
	sbb	edx,[tsc_start_hi]
	; If elapsed cycles overflow 32 bits the test ran for > ~3s — saturate.
	test	edx,edx
	jz	@@tsc_done
	mov	eax,0FFFFFFFFh
@@tsc_done:
	; Convert cycles -> PIT-equivalent ticks: EAX = EAX / cycles_per_tick.
	xor	edx,edx
	div	dword ptr [cycles_per_tick]
	jmp	@@done
@@pit:	mov	al,80h
	out	43h,al
	in	al,42h
	mov	ah,al
	in	al,42h
	xchg	ah,al
	push	eax
	mov	al,0B0h
	out	43h,al
	in	al,61h
	and	al,0FDh
	out	61h,al
	xor	al,al
	out	42h,al
	out	42h,al
	pop	eax
	neg	ax
	movzx	eax,ax
@@done:
ENDM


;=============================================================================
; calibrate_tsc_(void)
;
; Called once from main.c at startup. Probes CPUID for TSC support, and if
; present, measures CPU clock speed against PIT channel 2 over a known
; PIT window and stores cycles_per_tick + tsc_freq_hz. Sets has_tsc=1 on
; success. Costs ~55ms (one PIT 16-bit countdown cycle).
;
	Align 4
calibrate_tsc_:
	pushfd
	pushad
	push	ds es fs gs
	cli
	cld
	; --- CPUID-feature probe ---
	pushfd
	pop	eax
	mov	ecx,eax
	xor	eax,00200000h			; toggle EFLAGS.ID
	push	eax
	popfd
	pushfd
	pop	eax
	xor	eax,ecx				; ID bit changed?
	jz	@@no_cpuid
	.586p
	mov	eax,1
	cpuid
	test	edx,10h				; CPUID.1.EDX bit 4 = TSC
	.486p
	jz	@@no_tsc

	; --- Calibrate: time the PIT counting down from 65535 to 0 ---
	mov	al,0B6h				; chan 2, mode 3, 16-bit
	out	43h,al
	in	al,61h				; gate ON
	or	al,01h
	out	61h,al
	; Load counter = 0 -> counts down from 65535. Snapshot rdtsc immediately.
	xor	al,al
	out	42h,al
	out	42h,al
	.586p
	rdtsc
	.486p
	mov	[tsc_start_lo],eax
	mov	[tsc_start_hi],edx

	; Wait for the PIT to count down most of one cycle. We poll the current
	; count (latched via 0x80) and break when it has wrapped near to 0.
	; To avoid jitter from the small window after 0, we wait until the
	; count is < 0x1000 (well past mid-cycle but before wrap).
@@wait:	mov	al,80h				; latch chan 2
	out	43h,al
	in	al,42h				; LSB
	mov	ah,al
	in	al,42h				; MSB
	xchg	ah,al
	cmp	ax,01000h
	ja	@@wait

	; --- Snapshot rdtsc again; AX = remaining PIT count ---
	push	eax				; save PIT count
	.586p
	rdtsc
	.486p
	; Cycle delta
	sub	eax,[tsc_start_lo]
	sbb	edx,[tsc_start_hi]
	; Discard high 32 bits; calibration window is 55ms; even at 70 GHz
	; that's only 3.85e9 cycles, well within 32 bits.
	pop	ecx				; ECX = current PIT count
	; Ticks elapsed = 65535 - remaining_count (approximately, ignoring the
	; small overhead before the first rdtsc snapshot — well under 1 tick).
	mov	ebx,65535
	movzx	ecx,cx
	sub	ebx,ecx				; EBX = PIT ticks elapsed
	xor	edx,edx
	div	ebx				; EAX = cycles per PIT tick
	mov	[cycles_per_tick],eax

	; tsc_freq_hz = cycles_per_tick * 1193181 (informational)
	mov	ebx,1193181
	mul	ebx				; EDX:EAX = freq in Hz
	mov	[tsc_freq_hz],eax
	; (tsc_freq_hz overflows 32 bits above ~3.6 GHz; informational only,
	; the cycles_per_tick value is what's actually used by TIMER_STOP.)

	mov	byte ptr [has_tsc],1

	; Disable PIT gate so we leave it in a clean state.
	in	al,61h
	and	al,0FDh
	out	61h,al
	xor	al,al
	out	42h,al
	out	42h,al
	jmp	@@done

@@no_tsc:
@@no_cpuid:
	; Leave has_tsc=0; macros fall through to PIT path.
@@done:	sti
	pop	gs fs es ds
	popad
	popfd
	ret


;=============================================================================
; has_tsc_(void) - return 1 if rdtsc-based timing is in use, else 0
;
	Align 4
has_tsc_:
	movzx	eax,byte ptr [has_tsc]
	ret


;=============================================================================
; tsc_freq_hz_(void) - return CPU frequency in Hz (0 if TSC not in use)
;
	Align 4
tsc_freq_hz_:
	mov	eax,[tsc_freq_hz]
	ret


.CODE
;�����������������������������������������������������������������������������

;=============================================================================
	Align 4
get_cpl_:
	push	ds es fs gs
	pushad
	mov	ax,cs
	lar	ax,ax
	shr	ax,13
	and	eax,03h
	mov	[esp+1Ch],eax
	popad
	pop	gs fs es ds
	ret


;=============================================================================
	Align 4
get_iopl_:
	push	ds es fs gs
	pushad
	pushfd
	pop	eax
	shr	eax,10
	and	eax,03h
	mov	[esp+1Ch],eax
	popad
	pop	gs fs es ds
	ret


;=============================================================================
	Align 4
get_dpmi_flags_:
	push	ds es fs gs
	pushad
	mov	ax,0400h
	int	31h
	movzx	eax,bx
	mov	[esp+1Ch],eax
	popad
	pop	gs fs es ds
	ret


;=============================================================================
	Align 4
get_total_size_:
	pushad
	xor	eax,eax
	mov	al,30h
	out	70h,al
	in	al,71h
	mov	ah,al
	mov	al,31h
	out	70h,al
	in	al,71h
	xchg	al,ah
	shl	eax,10
	mov	[esp+1Ch],eax
	popad
	ret


;=============================================================================
	Align 4
get_himem_size_:
	push	ds es
	pushad
	sub	esp,48
	mov	edi,esp
	push	ss
	pop	es
	mov	ax,0500h
	int	31h
	mov	eax,[esp]
	add	esp,48
	mov	[esp+1Ch],eax
	popad
	pop	es ds
	ret



;=============================================================================
	Align 4
get_lomem_size_:
	pushad
	mov	ax,0100h
	mov	bx,-1
	int	31h
	movzx	eax,bx
	shl	eax,4
	mov	[esp+1Ch],eax
	popad
	ret



;=============================================================================
	Align 4
get_extender_type_:
	push	ds es
	pushad

	mov	ax,1600h	; check for Enhanced Windows
	int	2Fh
	test	al,al
	jz	@@1
	cmp	al,80h
	jz	@@1
	jmp	@@windows

@@1:	push	es		; save ES: selector
	push	ds		; check for DOS/4G
	push	cs
	pop	ds
	mov	esi,offs @s1
	mov	ax,0A00h
	int	31h
	pop	ds
	pop	edx		; restore ES: selector in DX
	jc	@@unknown	; if carry set, unknown DOS Extender

	mov	ax,es		; check if the same ES selector was returned
	cmp	ax,dx
	mov	es,dx
	jz	@@pmodew	; if yes, it is PMODE/W or EOS Extenders

	push	ds		; check for DOS/32 Advanced
	push	cs
	pop	ds
	mov	esi,offs @s2
	mov	ax,0A00h
	int	31h
	pop	ds
	jnc	@@dos32a

	mov	ax,cs		; check for CAUSEWAY
	lar	ax,ax
	shr	ax,13
	and	ax,3
	cmp	ax,3
	jz	@@causeway	; if DPL = 3 it is CauseWay Extender


	xor	ebx,ebx
	xor	ecx,ecx
	xor	esi,esi
	xor	edi,edi
	mov	ax,0306h	; get Raw Mode Switch Addr
	int	31h
	jc	@@dos4gw	; DOS/4GW does not support this call
	mov	ax,bx
	or	ax,cx
	jz	@@dos4gw
	mov	eax,esi
	or	eax,edi
	jz	@@dos4gw
	lar	ax,si		; check returned selector
	jnz	@@dos4gw

	jmp	@@dos4g

@@done:	mov	[esp+1Ch],eax
	popad
	pop	es ds
	ret

@@unknown:
	mov	eax,EXT_UNKNOWN
	jmp	@@done
@@dos32a:
	mov	eax,EXT_DOS32A
	jmp	@@done
@@pmodew:
	mov	ax,cs		; check for EOS first
	lar	ax,ax
	shr	ax,13
	and	ax,3
	cmp	ax,3
	jz	@@eos		; if DPL = 3 it is EOS
	mov	ax,0EEFFh
	int	31h
	jnc	@@pmodew_new
	mov	eax,EXT_PMODEW
	jmp	@@done
@@pmodew_new:
	mov	eax,EXT_PMODEWNEW
	jmp	@@done
@@dos4g:
	mov	eax,EXT_DOS4G
	jmp	@@done
@@dos4gw:
	mov	eax,EXT_DOS4GW
	jmp	@@done
@@causeway:
	mov	eax,EXT_CAUSEWAY
	jmp	@@done
@@windows:
	mov	eax,EXT_WINDOWS
	jmp	@@done
@@eos:	mov	eax,EXT_EOS
	jmp	@@done

@s1	db 'RATIONAL DOS/4G',0
@s2	db 'SUNSYS DOS/32A',0

get_pmodew_ver_:
	pushad
	mov	ax,0EEFFh
	int	31h
	movzx	eax,dx
	jnc	@@1
	mov	eax,-1
@@1:	mov	[esp+1Ch],eax
	popad
	ret


;=============================================================================
	Align 4
get_fpu_info_:
	pushad
	call	get_extender_type_
	cmp	eax,EXT_CAUSEWAY; if running under CauseWay
	jz	@@exit		; do not check for FPU
	cmp	eax,EXT_EOS	; if running under EOS
	jz	@@exit		; do not check for FPU
	cmp	eax,EXT_UNKNOWN
	jnz	@@1
	mov	eax,0E00h
	int	31h
	jc	@@exit
	cmp	ax,0E00h
	jz	@@exit

@@1:	mov	eax,0E00h	; try DPMI check FPU installation
	int	31h
	jc	@@l0		; if not supported, jump
	cmp	ax,0E00h
	jz	@@l0		; if simply cleared CF, jump
	mov	edx,eax
	and	edx,03h		; HOST: bit0=MPr, bit1=EMr
	shr	eax,2
	and	eax,03h		; CLIENT: bit0=MPr, bit1=EMr
	or	eax,edx
	jmp	@@done

@@l0:	mov	eax,cr0		; try native instruction
	mov	edx,eax
	shr	eax,1
	and	eax,03h
	and	edx,10h
	shr	edx,4
	or	eax,edx

@@done:	mov	[esp+1Ch],eax
	popad
	ret

@@exit:	mov	eax,1		;  don't check for FPU type
	jmp	@@done

;=============================================================================
; Get CPU Vendor specific ID string
;
	Align 4
get_cpu_id_:
	pushfd
	pushad
	cli
	cld
	mov	cpuid_name[0],0		; reset string
	pushfd
	pop	eax
	mov	ecx,eax
	xor	eax,00200000h
	push	eax
	popfd
	pushfd
	pop     eax
	xor     eax,ecx
	jne	@@1
	jmp	@@done
.586p
@@1:	xor	eax,eax			; set up for CPUID instruction
	cpuid
	mov	dword ptr cpuid_name[0],ebx
	mov     dword ptr cpuid_name[4],edx
	mov     dword ptr cpuid_name[8],ecx
.486p
@@done:	sti
	popad
	popfd
	mov	eax,offset cpuid_name
	ret



;=============================================================================
; Get CPU type:	80386, 80486, PENTIUM, ...
;
	Align 4
get_cpu_type_:
	pushad
	push	ds es fs gs
	mov	ax,0400h		; DPMI get CPU
	int	31h
	pop	gs fs es ds
	movzx	eax,cl
	mov	[esp+1Ch],eax
	cmp	cl,3
	ja	@@1
	popad
	ret
@@1:	pushfd
	cli
	pushfd
	pop     eax
	mov     edx,eax
	xor	eax,00200000h
	push    eax
	popfd
	pushfd
	pop     eax
	xor     eax,edx
	jne	@@l4
	jmp	@@x
@@l4:	xor	eax,eax
.586p
	cpuid
	mov	dword ptr [esp+1Ch+4],5	; CPU is 586
	cmp	eax,1			; check CPUID level
	jb	@@x			; if level 1 not supported, exit
	mov	eax,1
	cpuid
.486p
	and     eax,0F00H
	shr	ax,8
	movzx	eax,al
	mov	[esp+1Ch+4],eax
@@x:	sti
	popfd
	popad
	ret



;=============================================================================
; Get FPU type:	8087, 80287, 80387, PENTIUM, ...
;
	Align 4
get_fpu_type_:
	pushad
	call	get_cpu_type_
	mov	edx,eax
	xor	eax,eax
	push	eax
	fninit
	fnstcw	word ptr [esp+2]
	mov	ax,word ptr [esp+2]
	cmp	ah,03h
	jnz	@@done				; no FPU present
	mov	word ptr [esp],1
	and	word ptr [esp+2],0FF7Fh
	wait
	fldcw	word ptr [esp+2]
	fdisi
	fstcw	word ptr [esp+2]
	wait
	test	word ptr [esp+2],0080h
	jnz	@@done				; 8087 is present
	mov	word ptr [esp],2
	fninit
	wait
	fld1
	wait
	fldz
	wait
	fdivp	st(1),st
	wait
	fld	st(0)
	wait
	fchs
	wait
	fcompp
	wait
	fnstsw	ax
	wait
	fnclex
	wait
	sahf
	jz	@@done
	mov	word ptr [esp],3		; 387
	cmp	edx,4
	jb	@@done
	mov	eax,edx
	mov	byte ptr [esp],al		; 487+ (build-in)
@@done:	pop	eax
	and	eax,7
	jz	@@exit
	fldz
	fldz
	fldz
	fldz
	fldz
	fldz
	fldz
	fldz
	finit
@@exit:	mov	[esp+1Ch],eax
	popad
	ret



;=============================================================================
; Get SYSTEM type:	raw, XMS, VCPI, DPMI
;
	Align 4
get_sys_type_:
	pushad
	call	get_extender_type_
	test	eax,eax
	jnz	@@1
	push	ds es
	mov	esi,offs @s2
	push	cs
	pop	ds
	mov	ax,0A00h
	int	31h
	jc	@@err
	movzx	eax,bh
	pop	es ds
	jmp	@@done

@@1:	cmp	eax,EXT_PMODEWNEW
	jnz	@@err
	mov	ax,0EEFFh
	int	31h
	jc	@@err
	movzx	eax,ch
	jmp	@@done

@@err:	mov	eax,-1
@@done:	mov	[esp+1Ch],eax
	popad
	ret





;=============================================================================
; Measure CPU speed by issuing 1000 slow 32-bit DIV instructions
;
; Returns:	EAX = number of PIT ticks * 2
;
	Align 4
test_cpu_:
	call	get_cpu_type_
	cmp	eax,5
	jae	test_cpu586_
	pushfd
	pushad
	cli
	cld
	call	disable_irqs
	xor	eax,eax
	xor	edx,edx
	mov	ebx,1

	Align	4
	TIMER_START

	rept	1000
	div	ebx
	endm

	TIMER_STOP
	mov	[esp+1Ch],eax
	call	enable_irqs
	sti
	popad
	popfd
	ret

.586p
test_cpu586_:
	pushfd
	pushad
	cli
	mov	ax,ds
	mov	cpu586_cs,ax


	mov	ax,0204h
	mov	bl,08h
	int	31h
	push	ecx edx

	mov	ax,0205h
	mov	bl,08h
	mov	cx,cs
	mov	edx,offs __586int
	int	31h

	mov	al,36h		; reset PIT frequency
	out	43h,al
	xor	al,al
	out	40h,al
	xor	al,al
	out	40h,al
	mov	__586ack,10
	mov	ecx,7FFFFFFh
	sti
	rdtsc
	mov	esi,eax
	mov	edi,edx

@@1:	cmp	bptr __586ack,0
	loopnz	@@1

	rdtsc
	cli
	sub	eax,esi
	sbb	edx,edi

	mov	ebp,esp
	push	edx eax
	fild	qword ptr [ebp-8]
	fld	qword ptr __586dat2
	fld	qword ptr __586dat1
	fld1
	fdivrp	st(1)
	fmulp	st(1)
	fdivp	st(1)
	fistp	qword ptr [ebp-8]
	pop	eax edx

	pop	edx ecx
	pushad
	mov	ax,0205h
	mov	bl,08h
	int	31h
	popad
	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret

__586int:
	push	ds
	push	eax
	mov	ds,cs:cpu586_cs
	dec	bptr __586ack
	mov	al,20h
	out	20h,al
	pop	eax
	pop	ds
	iretd
.486p



;=============================================================================
; Measure CPU speed by issuing 1000 32-bit RISC instructions (ADD)
;
; Returns:	EAX = number of ticks * 2
;
	Align 4
test_risc_:
	pushfd
	pushad
	cli
	cld
	call	disable_irqs
	xor	eax,eax
	mov	edx,1

	Align	4
	TIMER_START

	rept	1000
	add	eax,edx
	endm

	TIMER_STOP
	mov	[esp+1Ch],eax
	call	enable_irqs
	sti
	popad
	popfd
	ret


;=============================================================================
; Measure Privelege instructions speed
;
; Returns:	EAX = number of ticks * 2
;
	Align 4
test_priv_:
	pushfd
	pushad
	cli
	cld
	call	disable_irqs
	xor	eax,eax

	Align	4
	TIMER_START

	rept	1000
	cli
	endm

	TIMER_STOP
	mov	[esp+1Ch],eax
	call	enable_irqs
	sti
	popad
	popfd
	ret





;=============================================================================
; Measure FPU speed by issuing 1000 simple operations (FADD)
;
; Returns:	EAX = number of ticks * 2
;
	Align 4
test_fpu_:
	pushfd
	pushad
	call	get_fpu_type_
	test	eax,eax
	jz	@@err			; if no FPU, exit
	cli
	cld
	call	disable_irqs
	xor	eax,eax
	finit				; initialize FPU
	fldpi				; load +0 into ST(0)
	fld1				; load +1 into ST(0)

	Align	4
	TIMER_START

	rept	1000
	fadd	st(0),st(1)
	endm

	TIMER_STOP
	mov	[esp+1Ch],eax
	finit				; reinitialize FPU
	call	enable_irqs
@@done:	sti
	popad
	popfd
	ret
@@err:	mov	eax,-1
	mov	[esp+1Ch],eax
	jmp	@@done









;=============================================================================
; Measure Mode switch rate by issuing an INT instruction from Protected Mode
;  to Real Mode and then back to Protected Mode
;
; Returns:	low word(EAX)  = number of ticks * 2 for  Protected to Real
;		high word(EAX) = number of ticks * 2 for  Real to Protected
;
	Align 4
test_int_:
	pushfd
	pushad
	cli
	cld
	call	disable_irqs

	mov	bl,80h		; get real mode INT 80h
	mov	ax,0200h
	int	31h
	push	ecx edx

	mov	ax,int_mem_seg
	test	ax,ax
	jnz	@@x1

	mov	bx,4		; allocate real mode memory (64 bytes)
	mov	ax,0100h
	int	31h
	mov	int_mem_seg,ax
	mov	int_mem_sel,dx
;	push	dx		; preserve selector on stack

	push	es
	mov	es,dx		; copy real mode handler to DOS memory
	xor	edi,edi			; ES:EDI = destination
	mov	esi,offs int80_RM	; DS:ESI = source
	mov	ecx,64			; ECX = size
	rep	movsb
	pop	es

@@x1:	mov	bl,80h
	mov	cx,ax		; CX = segment returned by INT 31h AX=0100h
	xor	dx,dx		; DX = offset is zero
	mov	ax,0201h
	int	31h

	Align 4
	mov	al,0B6h
	out	43h,al
	in	al,61h
	or	al,01h
	out	61h,al
	xor	al,al
	out	42h,al
	out	42h,al

	int	80h		; OUT: EBX = switch Protected/Real

	mov	al,80h
	out	43h,al
	in	al,42h
	mov	ah,al
	in	al,42h
	xchg	ah,al

	push	eax
	mov	al,0B0h
	out	43h,al
	in	al,61h
	and	al,0FDh
	out	61h,al
	xor	al,al
	out	42h,al
	out	42h,al
	pop	eax

	neg	ax		; EAX = switch Real/Protected
	neg	bx		; EBX = switch Protected/Real
	shl	eax,16
	and	ebx,0FFFFh
	or	eax,ebx		; EAX = [ high=RMPM | low=PMRM ]
	mov	ebp,eax

;	pop	dx		; free real mode DOS memory
;	mov	ax,0101h
;	int	31h

	pop	edx ecx		; restore original Real Mode INT 80h
	mov	bl,80h
	mov	ax,0201h
	int	31h
	call	enable_irqs

	mov	[esp+1Ch],ebp
	sti
	popad
	popfd
	ret

;--------------------------------
	Align 4
int80_RM:			; Real Mode Interrupt Handler (INT 80h)
	mov	al,80h
	out	43h,al
	in	al,42h
	mov	ah,al
	in	al,42h
	xchg	ah,al
	mov	bx,ax		;**NOTE: mov ebx,eax
	mov	al,0B6h
	out	43h,al
	in	al,61h
	or	al,01h
	out	61h,al
	xor	al,al
	out	42h,al
	out	42h,al
	iret




;=============================================================================
; Measure Mode switch rate by trapping IRQ 0 (INT 08h - timer) in Real Mode
;  and then waiting for hardware interrupt
;
; Returns:	low word(EAX)  = number of ticks * 2 for  Protected to Real
;		high word(EAX) = number of ticks * 2 for  Real to Protected
;
	Align 4
test_irq_:
	pushfd
	pushad
	cli
	cld

	mov	ax,irq_mem_seg
	test	ax,ax
	jnz	@@x1

	mov	bx,4		; allocate real mode memory (64 bytes)
	mov	ax,0100h
	int	31h
	mov	irq_mem_seg,ax
	mov	irq_mem_sel,dx

	push	es
	mov	es,dx		; copy real mode handler to DOS memory
	xor	edi,edi			; ES:EDI = destination
	mov	esi,offs int08_RM	; DS:ESI = source
	mov	ecx,64			; ECX = size
	rep	movsb
	sub	edi,4
	mov	eax,-1
	stosd
	pop	es

@@x1:	mov	bl,08h		; get real mode IRQ 0 (INT 08h)
	mov	ax,0200h
	int	31h
	push	ecx edx		;*

	mov	bl,08h
	mov	ax,0204h
	int	31h
	push	ecx edx		;**

	mov	bl,08h		; install Real Mode IRQ 0 (INT 08h)
	mov	cx,irq_mem_seg
	xor	dx,dx
	mov	ax,0201h
	int	31h

	push	ds
	mov	ds,irq_mem_sel
	mov	eax,-1
	mov	edx,-1
	mov	edi,60
	mov	ds:[edi],eax
;	mov	ecx,3FFFFFh

	mov	al,36h		; reset PIT frequency
	out	43h,al
	xor	al,al
	out	40h,al
	mov	al,80h
	out	40h,al

	mov	al,0B6h
	out	43h,al
	in	al,61h
	or	al,01h
	out	61h,al
	xor	al,al
	out	42h,al
	out	42h,al		; the PIT is started and running
	sti			; enable interrupts

; note: IRQ PM->RM (down) switch speed measurement is unreliable because we
; do not know the time elapsed between "sti" above and occurance of a hardware
; interrupt (and we cannot trigger a hardware interrupt on our own)

	Align	4
@@loop:	mov	bx,ds:[edi]	; BX = (PM to RM) + HLT switch time
	cmp	bx,dx
	jz	@@loop
	pop	ds
	cli			; disable interrupts

	mov	al,80h
	out	43h,al
	in	al,42h
	mov	ah,al
	in	al,42h
	xchg	ah,al
	push	eax
	mov	al,0B0h
	out	43h,al
	in	al,61h
	and	al,0FDh
	out	61h,al
	xor	al,al
	out	42h,al
	out	42h,al

	mov	al,36h
	out	43h,al
	xor	al,al
	out	40h,al
	out	40h,al
	pop	eax

	neg	ax		; EAX = switch Real/Protected
	neg	bx		; EBX = switch Protected/Real
	shl	eax,16
	mov	ax,bx		; EAX = [ high=RMPM | low=PMRM ]
	mov	ebp,eax

	pop	edx ecx		; restore original Prot. Mode IRQ 0
	mov	bl,08h
	mov	ax,0205h
	int	31h

	pop	edx ecx		; restore original Real Mode IRQ 0
	mov	bl,08h
	mov	ax,0201h
	int	31h

;	mov	dx,irq_mem_sel	; free real mode DOS memory
;	mov	ax,0101h
;	int	31h

	mov	[esp+1Ch],ebp	; EAX = [ high=RM2PM | low=PM2RM ]
	sti
	popad
	popfd
	ret


;--------------------------------
	Align 4
int08_RM:			; Real Mode Interrupt Handler (INT 08h)
	push	eax
	mov	al,80h
	out	43h,al
	in	al,42h
	mov	ah,al
	in	al,42h
	xchg	ah,al
	db 2Eh, 0A3h, 3Ch, 00h	; real mode:	mov cs:[60],ax
	mov	al,0B6h
	out	43h,al
	in	al,61h
	or	al,01h
	out	61h,al
	xor	al,al
	out	42h,al
	out	42h,al
	mov	al,20h
	out	20h,al		; acknowledge interrupt receiving
	pop	eax
	iret

	Align	4
int08_PM:
	push	eax
	mov	al,20h
	out	20h,al
	pop	eax
	iretd








;=============================================================================
	Align 4
test_low_movsw_:
	pushfd
	pushad
	call	alloc_low
	mov	ebx,eax			; ebx = selector
	mov	eax,-1
	jc	@@done

	cli
	cld
	push	ds es
	mov	ecx,MEMORY/2		; ECX = size of memory block
	xor	esi,esi			; ESI = source base
	lea	edi,[esi+ecx]		; EDI = destination base
	shr	ecx,1			; adjust ECX for operand size
	mov	ds,bx
	mov	es,bx

	Align 4
	TIMER_START

	rep	movsw

	TIMER_STOP

	pop	es ds
	call	dealloc_low

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret


;=============================================================================
	Align 4
test_low_movsd_:
	pushfd
	pushad
	call	alloc_low
	mov	ebx,eax			; ebx = selector
	mov	eax,-1
	jc	@@done

	cli
	cld
	push	ds es
	mov	ecx,MEMORY/2		; ECX = size of memory block
	xor	esi,esi			; ESI = source base
	lea	edi,[esi+ecx]		; EDI = destination base
	shr	ecx,2			; adjust ECX for operand size
	mov	ds,bx
	mov	es,bx

	Align 4
	TIMER_START

	rep	movsd

	TIMER_STOP

	pop	es ds
	call	dealloc_low

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret



;=============================================================================
	Align 4
test_low_stosw_:
	pushfd
	pushad
	call	alloc_low
	mov	ebx,eax			; ebx = selector
	mov	eax,-1
	jc	@@done

	cli
	cld
	push	es
	mov	ecx,MEMORY		; ECX = size of memory block
	xor	edi,edi			; EDI = destination base
	shr	ecx,1			; adjust ECX for operand size
	mov	es,bx
	mov	eax,PATTERN

	Align 4
	TIMER_START

	rep	stosw

	TIMER_STOP

	pop	es
	call	dealloc_low

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret


;=============================================================================
	Align 4
test_low_stosd_:
	pushfd
	pushad
	call	alloc_low
	mov	ebx,eax			; ebx = selector
	mov	eax,-1
	jc	@@done

	cli
	cld
	push	es
	mov	ecx,MEMORY		; ECX = size of memory block
	xor	edi,edi			; EDI = destination base
	shr	ecx,2			; adjust ECX for operand size
	mov	es,bx
	mov	eax,PATTERN

	Align 4
	TIMER_START

	rep	stosd

	TIMER_STOP

	pop	es
	call	dealloc_low

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret















;=============================================================================
	Align 4
test_high_movsw_:
	pushfd
	pushad
	call	alloc_hi
	mov	ebx,eax			; ebx = selector
	mov	eax,-1
	jc	@@done

	cli
	cld
	push	ds es
	mov	ecx,MEMORY/2		; ECX = size of memory block
	xor	esi,esi			; ESI = source base
	lea	edi,[esi+ecx]		; EDI = destination base
	shr	ecx,1			; adjust ECX for operand size

	mov	ds,bx
	mov	es,bx

	Align 4
	TIMER_START

	rep	movsw

	TIMER_STOP

	pop	es ds
	call	dealloc_hi

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret


;=============================================================================
	Align 4
test_high_movsd_:
	pushfd
	pushad
	call	alloc_hi
	mov	ebx,eax			; ebx = selector
	mov	eax,-1
	jc	@@done

	cli
	cld
	push	ds es
	mov	ecx,MEMORY/2		; ECX = size of memory block
	xor	esi,esi			; ESI = source base
	lea	edi,[esi+ecx]		; EDI = destination base
	shr	ecx,2			; adjust ECX for operand size
	mov	ds,bx
	mov	es,bx

	Align 4
	TIMER_START

	rep	movsd

	TIMER_STOP

	pop	es ds
	call	dealloc_hi

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret


;=============================================================================
	Align 4
test_high_stosw_:
	pushfd
	pushad
	call	alloc_hi
	mov	ebx,eax			; ebx = selector
	mov	eax,-1
	jc	@@done

	cli
	cld
	push	es
	mov	ecx,MEMORY		; ECX = size of memory block
	xor	edi,edi			; EDI = destination base
	shr	ecx,1			; adjust ECX for operand size
	mov	es,bx
	mov	eax,PATTERN

	Align 4
	TIMER_START

	rep	stosw

	TIMER_STOP

	pop	es
	call	dealloc_hi

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret


;=============================================================================
	Align 4
test_high_stosd_:
	pushfd
	pushad
	call	alloc_hi
	mov	ebx,eax			; ebx = selector
	mov	eax,-1
	jc	@@done

	cli
	cld
	push	es
	mov	ecx,MEMORY		; ECX = size of memory block
	xor	edi,edi			; EDI = destination base
	shr	ecx,2			; adjust ECX for operand size
	mov	es,bx
	mov	eax,PATTERN

	Align 4
	TIMER_START

	rep	stosd

	TIMER_STOP

	pop	es
	call	dealloc_hi

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret









;=============================================================================
	Align 4
test_vid_movsw_:
	pushfd
	pushad
	call	alloc_hi
	mov	ebx,eax			; ebx = selector
	mov	eax,-1
	jc	@@done
	call	alloc_vid

	cli
	cld
	push	ds es
	mov	ecx,VMEMORY		; ECX = size of memory block
	xor	esi,esi			; ESI = source base
	xor	edi,edi			; EDI = destination base
	shr	ecx,1			; adjust ECX for operand size
	mov	ds,bx
	mov	es,ax

	Align 4
	TIMER_START

	rep	movsw

	TIMER_STOP

	pop	es ds
	call	dealloc_vid
	call	dealloc_hi

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret


;=============================================================================
	Align 4
test_vid_movsd_:
	pushfd
	pushad
	call	alloc_hi
	mov	ebx,eax			; ebx = selector
	mov	eax,-1
	jc	@@done
	call	alloc_vid

	cli
	cld
	push	ds es
	mov	ecx,VMEMORY		; ECX = size of memory block
	xor	esi,esi			; ESI = source base
	xor	edi,edi			; EDI = destination base
	shr	ecx,2			; adjust ECX for operand size
	mov	ds,bx
	mov	es,ax

	Align 4
	TIMER_START

	rep	movsd

	TIMER_STOP

	pop	es ds
	call	dealloc_vid
	call	dealloc_hi

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret


;=============================================================================
	Align 4
test_vid_stosw_:
	pushfd
	pushad
	call	alloc_vid

	cli
	cld
	push	es
	mov	ecx,VMEMORY		; ECX = size of memory block
	xor	edi,edi			; EDI = destination base
	shr	ecx,1			; adjust ECX for operand size
	mov	es,ax
	mov	eax,PATTERN

	Align 4
	TIMER_START

	rep	stosw

	TIMER_STOP

	pop	es
	call	dealloc_vid

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret


;=============================================================================
	Align 4
test_vid_stosd_:
	pushfd
	pushad
	call	alloc_vid

	cli
	cld
	push	es
	mov	ecx,VMEMORY		; ECX = size of memory block
	xor	edi,edi			; EDI = destination base
	shr	ecx,2			; adjust ECX for operand size
	mov	es,ax
	mov	eax,PATTERN

	Align 4
	TIMER_START

	rep	stosd

	TIMER_STOP

	pop	es
	call	dealloc_vid

@@done:	mov	[esp+1Ch],eax
	sti
	popad
	popfd
	ret









;=============================================================================
	Align 4
disable_irqs:
	push	eax
	in	al,21h
	mov	ah,al
	in	al,0A1h
	mov	pic_mask,ax		; get and save pic mask
	mov	al,0FFh
	out	21h,al			; disable all IRQs except IRQ1 (kbrd)
	mov	al,0FFh
	out	0A1h,al
	pop	eax
	cli
	ret
	Align 4
enable_irqs:
	push	eax
	mov	ax,pic_mask
	out	0A1h,al
	mov	al,ah
	out	21h,al
	pop	eax
	sti
	ret

	Align 4
alloc_low:
	pushad
	mov	ax,0100h
	mov	bx,MEMORY/16
	int	31h
	mov	eax,-1
	mov	mem_dx,0
	jc	@@done
	mov	mem_dx,dx

	mov	bx,dx
	mov	ax,0006h		; get selector base
	int	31h

	push	ecx edx
	mov	bx,ds
	mov	ax,000Ah		; allocate alias selector
	int	31h
	mov	ebx,eax

	pop	edx ecx
	mov	ax,0007h		; set selector base
	int	31h

	mov	ecx,MEMORY
	mov	edx,ecx
	shr	ecx,16
	mov	ax,0008h		; set selector limit
	int	31h

	xor	eax,eax
	mov	ax,bx
	mov	mem_sel,ax
@@done:	mov	[esp+1Ch],eax		; return selector
	popad
	ret

	Align 4
alloc_hi:
	pushad
	mov	ecx,MEMORY
	mov	ebx,ecx
	shr	ebx,16
	mov	ax,0501h		; allocate memory
	int	31h
	mov	eax,-1
	mov	mem_si,0
	mov	mem_di,0
	jc	@@done
	mov	mem_si,si
	mov	mem_di,di
	mov	edx,ecx
	mov	ecx,ebx

	push	ecx edx
	mov	bx,ds
	mov	ax,000Ah		; allocate alias selector
	int	31h
	mov	ebx,eax
	mov	mem_sel,ax
	pop	edx ecx

	push	ecx edx
	mov	ax,0007h		; set selector base
	int	31h

	mov	ecx,MEMORY
	mov	edx,ecx
	shr	ecx,16
	mov	ax,0008h		; set selector limit
	int	31h

	mov	esi,ecx
	mov	edi,edx
	pop	ecx ebx
	mov	ax,0600h		; lock pages
	int	31h

	xor	eax,eax
	mov	ax,mem_sel
@@done:	mov	[esp+1Ch],eax		; return selector
	popad
	ret

	Align 4
alloc_vid:
	pushad
	mov	bx,ds
	mov	ax,000Ah		; allocate alias selector
	int	31h
	mov	ebx,eax

	mov	ecx,0A0000h
	mov	edx,ecx
	shr	ecx,16
	mov	ax,0007h		; set selector base
	int	31h

	mov	ecx,VMEMORY
	mov	edx,ecx
	shr	ecx,16
	mov	ax,0008h		; set selector limit
	int	31h

	xor	eax,eax
	mov	ax,bx
	mov	mem_vid,ax
	mov	[esp+1Ch],eax		; return selector
	popad
	ret



	Align 4
dealloc_low:
	pushad
	mov	dx,mem_dx
	test	dx,dx
	jz	@@done
	mov	ax,0101h
	int	31h
	mov	bx,mem_sel
	mov	ax,0001h
	int	31h
@@done:	popad
	ret

	Align 4
dealloc_hi:
	pushad
	mov	si,mem_si
	mov	di,mem_di
	mov	ax,si
	or	ax,di
	jz	@@done
	mov	ax,0502h
	int	31h
	mov	bx,mem_sel
	mov	ax,0001h
	int	31h
@@done:	popad
	ret

	Align 4
dealloc_vid:
	pushad
	mov	bx,mem_vid
	mov	ax,0001h
	int	31h
@@done:	popad
	ret






;=============================================================================
	Align 4
setvideomode_:
	pushad
	xor	ah,ah
	int	10h
	popad
	ret

	Align 4
gotoxy_:
	pushad
	mov	dh,al
	xchg	dh,dl
	mov	ax,0200h
	xor	bx,bx
	int	10h
	popad
	ret





.DATA
;�����������������������������������������������������������������������������
__586ack	db 0,0
__586dat1	dq 18.2064971
__586dat2	dq 10.0000000
cpu586_cs	dw 0
mem_si		dw 0
mem_di		dw 0
mem_dx		dw 0
mem_sel		dw 0
mem_seg		dw 0
mem_vid		dw 0
pic_mask	dw 0
cpuid_name	db 20 dup(0)

int_mem_sel	dw 0
int_mem_seg	dw 0
irq_mem_sel	dw 0
irq_mem_seg	dw 0


end
