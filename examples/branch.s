; branch.s A simulation of a conditional branch
;
; This code compares C1 to C2. If C1 is greater or equal to C2, the script
; continues to BGTE. Otherwise, it skips over BGTE and goes to BLT. In this
; way, the script behaves as though a conditional branch instruction were
; issued, without having that instruction written into the memory.
IP:	start	; the first 4 bytes always indicates the instruction pointer
C1:	123	; the first comparand
C2:	456	; the second comparand

start:
; subtract C2 from C1, putting the result in CMP
	-Iii CMP: 0 C1 C2
; now shift the sign bit to cover the whole number. this takes advantage of
; the fact that a signed shift right will replace the leftmost bits with the
; sign bit, rather than just zero. after this instruction MASK contains all 1s
; or all 0s.
	>IiI MASK: 0 CMP 31
; use MASK as a mask for 0x20, which is the length of two instructions. after
; this instruction, JMP contains 0x20 or 0.
	&UuU JMP: 0 MASK 0x40
; jump to the appropriate place by adding BGTE, the target when C1 is greater
; than or equal to C2, with JMP, which advances IP four instructions past
; BGTE, to BLT, if C1 is less than C2.
	+uuU IP JMP BGTE
BGTE:
; print out Greater Than 
	=uU 0xF000 "Grea"
	=uU 0xF004 "ter "
	=uU 0xF008 "Than"
; halt the machine
	#
BLT:
; print out Less Than
	=uU 0xF000 "Less"
	=uU 0xF004 " Tha"
	=uU 0xF008 "n   "
; halt the machine
	#
