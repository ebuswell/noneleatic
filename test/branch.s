; branch.s A simulation of a conditional branch
IP:	start
C1:	123
C2:	456
R:	0
; start by subtracting the numbers
start:
	-iii R C1 C2
; now shift the sign bit to the whole number
	>iiI R R 32
; set R for two or zero instructions
	&uuU R R 0x20
; now jump to the appropriate place
	+uuU IP R BGTE
BGTE:	=iIU R 0
	#UUU
BLT:	=iIU R 1
	#UUU
