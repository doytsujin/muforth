; 6809 chat -- Mac-6809 communication stuff
; (c) 1992-94, David Frech

; 6 jan 92 -- back to "old style" of passing sp on reset
; 18 feb 93 -- back to "new style" of sp: don't pass it on
;        reset but do get an sp from host on go.
; 20-aug-93  More big changes; rewrote almost everything
;   now the target returns reply codes and there are only three cmds
;   Calling this revision version 2.0.
; 27-aug-93  Changed to run with 8k ram.  This is version 2.1.
; 08-apr-94  automagically sets stack to top of ram
;	returns "go" response immediately, then executes.
;	added sp!.
;	This is version 2.2.

uartcr	equ	$b000		;* control/status register
uartdr	equ	uartcr+1

via	equ	$b400
via_ier	equ	via+14		;* interrupt enable register

replyRead	equ	1
replyWrite	equ	3
replyGo		equ	5
replySp		equ	7
replyError	equ	255


	setdp	0
	org	$f800		;* rom start

	dcs	"Chat 6809 v2.2, "
	dcs	"Copyright (c) 1992-94 David Frech."
	dcs	"ext sw->irq, via->firq, acia->firq."
	dcs	"0=read(addr,cnt); 2=write(addr,cnt,bytes);"
	dcs	"4=go():sp; 6=sp!(sp)"


reset
	lda	#3
	sta	uartcr		;* master reset of 6850
	lda	#00010101b
	sta	uartcr		;* rcv int dis,rts=0,tx int dis,
				;* 1 stop bit, /16 baud
	lda	#$7f
	sta	via_ier		;* disable all via interrupts

	clra
	tfr	a,dp		;* direct page register is zero
	
	;* setup interrupt vectors in ram at address 0
	;* point them all to chat
	ldx	#0
	ldb	#7
	ldu	#chat
:	stu	,x++
	decb
	bne	:-1

	;* check for top of ram; start at $800 (2k)
	ldx	#$800
	bra	ramTest
ramLoop
	com	,x+	;* fix, advance to next, loop
ramTest
	lda	,x
	coma
	com	,x
	cmpa	,x
	beq	ramLoop
	;* end of ram...
	tfr	x,s	;* set s to end
	;* nmi disabled till now
	
:	swi	;* start chatting
	bne	:-1

;* chat sits in an endless loop: 
;* gets a command byte, dispatches, and returns the
;* resulting data. Simple?

;* because we did an swi to get here, both firq and irq are disabled.
;* this means that the acia CANNOT be connected to nmi when we're
;* trying to debug in "chat" mode.

chat
	tfr	s,x		;* current sp to x
	bsr	WriteX		;* send to host
	
chatloop
	bsr	ReadA		;* get cmd byte
	cmpa	#oplast-optable
	blo	cmd_ok
	lda	#replyError
	bsr	WriteA
	bra	chatloop
cmd_ok	
	ldx	#optable
	jmp	[a,x]		;* jmp indirect thru table
	
optable
	dw	read		;* cmd = 0
	dw	write		;* cmd = 2
	dw	go		;* cmd = 4
	dw	spstore		;* cmd = 6
oplast

read	;* read(addr, cnt)
	bsr	ReadX
	bsr	ReadA		;* count
	pshs	a
	lda	#replyRead
	bsr	WriteA
:	lda	,x+
	bsr	WriteA
	dec	,s
	bne	:-1
	leas	1,s
	bra	chatloop
		
write	;* write(addr, cnt, bytes)
	bsr	ReadX
	bsr	ReadA		;* count
	pshs	a
:	bsr	ReadA		;* get next char
	sta	,x+
	dec	,s
	bne	:-1
	leas	1,s
	lda	#replyWrite
	bsr	WriteA
	bra	chatloop
					
go
	lda	#replyGo
	bsr	WriteA
	rti			;* load context from stack, go
				;* "return" thru swi, to chat

spstore
	bsr	ReadX		;* get new sp
	tfr	x,s
	lda	#replySp
	bsr	WriteA
	bra	chatloop
	
;* WriteA -- write register a to serial, clobber b
WriteA
	ldb	uartcr
	andb	#2		;* transmit reg empty
	beq	WriteA		;* loop till ready
	sta	uartdr		;* send data
	rts

;* ReadA -- read serial into register a, clobber b
ReadA
	ldb	uartcr
	andb	#1		;* receive reg full
	beq	ReadA		;* loop till ready
	lda	uartdr		;* get byte
	rts

;* WriteX -- write register x to serial, high byte first
;* clobbers d
WriteX	pshs	x
	lda	,s+		;* high byte at lower addr
	bsr	WriteA
	lda	,s+
	bra	WriteA		;* rts from there

;* ReadX -- read x from serial, high byte first
;* clobbers d
ReadX	pshs	x
	bsr	ReadA
	sta	,s
	bsr	ReadA
	sta	1,s
	puls	x,pc


	
	org	$fff0-(7*4)
_rsrvd	jmp	[0]		;* indirect thru 0
_swi3	jmp	[2]		;* indirect thru 2
_swi2	jmp	[4]
_firq	jmp	[6]
_irq	jmp	[8]
_swi	jmp	[10]
_nmi	jmp	[12]

	org	$fff0
	dw	_rsrvd
	dw	_swi3
	dw	_swi2
	dw	_firq
	dw	_irq
	dw	_swi
	dw	_nmi
	dw	reset

