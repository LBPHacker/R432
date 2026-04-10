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
		*(.rodata* .gnu.linkonce.r.*)
		__EndRodata = .;
		__StartData = .;
		*(.data* .sdata*)
		__EndData = .;
		__StartBss = .;
		*(.bss* .sbss*)
		*(COMMON)
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
