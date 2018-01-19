; ten-print, noneleatic style
;
; This program implements a version of ten print, i.e.:
;
; 10 PRINT CHR$(205.5+RND(1)); : GOTO 10
;
; I probably could have done it with less code, but this illustrates how one
; might implement functions or subroutines using neasm/nevm. None of these
; functions are reentrant, because for simplicity's sake I didn't create a
; stack.
IP:		start	; the instruction pointer
slashes:	"\\/  " ; the source text, plus two spaces to help the
			; debugger know this is text.

; A random number generator, using the linear congruential method,
; musl libc variant.
random_seed: 1L
random_magic: 6364136223846793005L
random_out: 0L
random:
	*zzz random_seed random_seed random_magic
	+zzU random_seed random_seed 1
	>zzU random_out random_seed 33	; note that we assume little endian
					; here
	; go to next location
	=uU IP random_nextIP: 0

; print a character pointed to by printch_which
printch:
	; copy the character to the screen
	=cc printch_cursor: 0xF000 printch_which: 0
	; increment cursor
	+uuU printch_cursor printch_cursor 1
	; ensure printch_cursor is in range
	&uuU printch_cursor printch_cursor 0xFFF
	%uuU printch_cursor printch_cursor 2000		; 80x25 = 2000
	|uuU printch_cursor printch_cursor 0xF000
	; go to next location
	=uU IP printch_nextIP: 0

start:
	; get a new random number
	=uU random_nextIP choose_char
	=uU IP random
choose_char:
	; get the last bit of the random number
	&UuU random_bit: 0 random_out 1
	; set the character selector
	=uU printch_which slashes
	+uuu printch_which printch_which random_bit
	; now print the character, looping to start
	=uU printch_nextIP start
	=uU IP printch
