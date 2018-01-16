; ten-print, noneleatic style
IP:		start
A:		0
slashes:	"\\/  "

; use the musl libc method
random_seed: 0xf6258085a4fbbdc9L
random_magic: 6364136223846793005L
random_out: 0L
random_nextIP: 0
random:
	*zzz random_seed random_seed random_magic
	+zzU random_seed random_seed 1
	>zzU random_out random_seed 33
	; go to next location
	=uuU IP random_nextIP 0

; print a character, depending on the random number
printch_nextIP: 0
printch:
	; copy the character to the screen
	=ccU printch_cursor: 0xF000 printch_which: 0 0
	; increment cursor
	+uuU printch_cursor printch_cursor 1
	; ensure printch_cursor is in range
	&uuU printch_cursor printch_cursor 0xFFF
	%uuU printch_cursor printch_cursor 2000
	|uuU printch_cursor printch_cursor 0xF000
	; go to next location
	=uuU IP printch_nextIP 0

start:
	; get a new random number
	=uUU random_nextIP after_random 0
	=uUU IP random 0
after_random:
	; get the last bit of the random number
	=uuU A random_out 0
	&uuU A A 1
	; set the character selector
	=uUU printch_which slashes 0
	+uuu printch_which printch_which A
	; now print the character
	=uUU printch_nextIP after_printch 0
	=uUU IP printch 0
after_printch:
	; go back to start
	=uUU IP start 0
