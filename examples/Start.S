.globl Start
.globl Main
.globl __EndStack
.section .start
Start:
	lla sp, __EndStack
	j Main
