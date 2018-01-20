; fibonacci.s Print out the fibonacci sequence
;
; This program makes extensive use of a simple stack structure, allowing for
; recursion. Recursing into fib gets pretty slow pretty quickly.

IP:	start
arg: 0		; the argument for any given function. this is automatically
		; saved on call and restored on return, such that arg always
		; represents the argument to the function we are currently in

; returns the nth fibonnacci number
fib_result: 0
fib:
	; is arg > 1?
	-IIi fibcmp: 0 1 arg
	>IiI recmask: 0 fibcmp 31
	!Uu nrecmask: 0 recmask
	&UuU jmprec: "=uUU" recmask "=uUU"
	&UuU njmprec: "_UUU" nrecmask "_UUU"
	|uuu maybejmprec jmprec njmprec
maybejmprec:
	=uU IP fib_recurse
	; arg <= 1
	=uu fib_result arg ; result is equal to arg
	=uU IP ret
fib_recurse:
	; arg > 1
	; find fib n-1
	-uuU call_arg arg 1
	+uuU call_next IP 0x10
	=uU IP call
	; push result
	=uu fib1dst stack_ptr
	+uuU stack_ptr stack_ptr 4
	=uu fib1dst: 0 fib_result
	; find fib n-2
	-uuU call_arg arg 2
	+uuU call_next IP 0x10
	=uU IP call
	; pop result of fib n-1
	-uuU fib1 stack_ptr 4
	-uuU stack_ptr stack_ptr 4
	; result is fib n-1 + fib n-2
	+uuu fib_result fib1: 0 fib_result
	; return
	=uU IP ret

; print all the fibonacci numbers
start:
	; call fib with fibn
	=uU call_arg fibn: 0
	=uU call_dst fib
	+uuU call_next IP 0x10
	=uU IP call
	; call printn with fib_result
	=uu call_arg fib_result
	=uU call_dst printn
	+uuU call_next IP 0x10
	=uU IP call
	; increment fibn
	+uuU fibn fibn 1
	; loop
	=uU IP start

; prints a number to the console, followed by a space
printn_zerospace: "\0 "
printn:
	; push zero and space to the stack
	=uu print_zerospacedst stack_ptr
	+uuU stack_ptr stack_ptr 2
	=ss print_zerospacedst: 0 printn_zerospace
printn_digitloop:
	; calculate character for rightmost digit
	%uuU digit arg 10
	+UuU digit: 0 digit "0"
	; push it to the stack
	=uu print_ndst stack_ptr
	+uuU stack_ptr stack_ptr 1
	=cu print_ndst: 0 digit
	; divide by 10 to drop rightmost digit from arg
	/uuU arg arg 10
	; is it zero yet?
	-IIi printn_cmp1: 0 0 arg
	>IiI printn_mask1: 0 printn_cmp1 31
	!Uu printn_nmask1: 0 printn_mask1
	&UuU printn_doloop: "=uUU" printn_mask1 "=uUU"
	&UuU printn_noloop: "_UUU" printn_nmask1 "_UUU"
	|uuu maybe_printn_loop printn_doloop printn_noloop
maybe_printn_loop:
	=uU IP printn_digitloop
printn_printloop:
	; print out stack until we get to "\0"
	; pop stack to printn_cmpsrc and printn_printsrc
	-uuU printn_cmpsrc stack_ptr 1
	-uuU printn_printsrc stack_ptr 1
	-uuU stack_ptr stack_ptr 1
	; check if the character is zero
	-IIc printn_cmp2: 0 0 printn_cmpsrc: 0
	>IiI printn_mask2: 0 printn_cmp2 31
	!Uu printn_nmask2: 0 printn_mask2
	&UuU printn_doret: "=uUU" printn_nmask2 "=uUU"
	&UuU printn_noret: "_UUU" printn_mask2 "_UUU"
	|uuu maybe_printn_ret printn_doret printn_noret
maybe_printn_ret:
	=uU IP ret
	; copy the character to the screen
	=cc printn_cursor: 0xF000 printn_printsrc: 0
	; increment cursor
	+uuU printn_cursor printn_cursor 1
	; ensure printn_cursor is in range
	&uuU printn_cursor printn_cursor 0xFFF
	%uuU printn_cursor printn_cursor 2000		; 80x25 = 2000
	|uuU printn_cursor printn_cursor 0xF000
	=uU IP printn_printloop

call:
	; push arg and return
	=uu call_argdst stack_ptr
	+uuU call_nextdst stack_ptr 4
	+uuU stack_ptr stack_ptr 8
	=uu call_argdst: 0 arg
	=uU call_nextdst: 0 call_next: 0
	; set new arg
	=uU arg call_arg: 0
	; jump to call_dst
	=uU IP call_dst: 0

ret:
	; pop arg to arg, pop return to IP
	-uuU ret_next stack_ptr 4
	-uuU argsrc stack_ptr 8
	-uuU stack_ptr stack_ptr 8
	=uu arg argsrc: 0
	=uu IP ret_next: 0

stack_ptr: stack
stack: 0
