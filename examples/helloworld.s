; helloworld.s The old standard "hello, world" program.
;
; This copies the contents of txt, "hello, world", to the screen, which is
; located at 0xF000. It stops copying when it reaches a null character, i.e.
; "\0".
;
; This file illustrates how altering an instruction may be done.
IP:	start			; the instruction pointer
txt:	"hello, world\0"	; the text to copy

start:
; first, test if the character pointed to by ptr is zero
	-IIi CMP: 0 0 ptr: txt		; subtract pointer from zero
	>IiI NMASK: 0 CMP 31		; shift sign bit
	!Uu MASK: 0 NMASK		; negate
	&UuU HALT: "#UUU" MASK "#UUU"	; mask the halt instruction
	&UuU NOOP: "_UUU" NMASK "_UUU"	; do the opposite with the noop
					; instruction
	|uuu end HALT NOOP		; set end to be noop or halt,
					; accordingly
end:	_
; next, copy character to screen
	=cc out: 0xF000 from: txt	; copy character
; finally, increment all the pointers and start again
	+uuU ptr ptr 1			; increment pointers
	+uuU out out 1
	+uuU from from 1
	=uU IP start			; loop to start
