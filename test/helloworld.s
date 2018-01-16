; helloworld.s The old standard "hello, world" program.h
IP:	start
R:	0
txt:	"hello, world\0"

; copy whatever's in text to the first line of the screen
start:
	-iIi R 0 ptr: txt		; subtract pointer from zero
	>iiI R R 31			; shift sign bit
	!uuU R R			; negate
	&uuU R R 0x50			; jump to end if pointer is zero
	+uuu IP IP R
	=ccU out: 0xF000 from: txt	; copy character
	+uuU ptr ptr 1			; increment pointers
	+uuU out out 1
	+uuU from from 1
	=uUU IP start			; loop to start
end:
	=uUU IP end			; loop endlessly
