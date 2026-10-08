MEMORY {
	memory (rwx) : org = __MemoryBase, len = __MemorySize
}
SECTIONS {
	.image : {
		__StartText = .;
		. = ALIGN(4);
		KEEP(*(.start))
		*(.text* .gnu.linkonce.t.*)
		. = ALIGN(4);
		__EndText = .;
		__StartRodata = .;
		. = ALIGN(4);
		*(.rodata* .gnu.linkonce.r.*)
		. = ALIGN(4);
		__EndRodata = .;
		__StartData = .;
		. = ALIGN(4);
		*(.data* .sdata*)
		. = ALIGN(4);
		__EndData = .;
		__StartBss = .;
		. = ALIGN(4);
		*(.bss* .sbss*)
		*(COMMON)
		. = ALIGN(4);
		__EndBss = .;
	} > memory
	.stack (__MemoryBase + __MemorySize - __StackSize) : {
		__StartStack = .;
		. = ALIGN(4);
		. = . + __StackSize;
		. = ALIGN(4);
		__EndStack = .;
	} > memory
}
