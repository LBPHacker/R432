MEMORY {
	memory (rwx) : org = memory_base, len = memory_size
}
SECTIONS {
	.image : {
		start_text = .;
		. = ALIGN(4);
		KEEP(*(.text.start))
		*(.text* .gnu.linkonce.t.*)
		. = ALIGN(4);
		end_text = .;
		start_rodata = .;
		. = ALIGN(4);
		*(.rodata* .gnu.linkonce.r.*)
		. = ALIGN(4);
		end_rodata = .;
		start_data = .;
		. = ALIGN(4);
		*(.data* .sdata*)
		. = ALIGN(4);
		end_data = .;
		start_bss = .;
		. = ALIGN(4);
		*(.bss* .sbss*)
		*(COMMON)
		. = ALIGN(4);
		end_bss = .;
	} > memory
	start_heap = ALIGN(4);
	end_heap = memory_base + memory_size - stack_size;
	.stack (memory_base + memory_size - stack_size) : {
		start_stack = .;
		. = ALIGN(4);
		. = . + stack_size;
		. = ALIGN(4);
		end_stack = .;
	} > memory
	/DISCARD/ : {
		*(.eh_frame)
		*(.eh_frame_hdr)
	}
}
