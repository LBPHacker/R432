use core::arch::global_asm;

global_asm!(
    r#"
        .section .text.start

        .globl _start
        .globl main
        .globl end_stack
        .globl start_bss
        .globl end_bss

    _start:
        lla sp, end_stack

        lla t0, start_bss
        lla t1, end_bss
    2:
        beq t0, t1, 3f
        sw zero, 0(t0)
        addi t0, t0, 4
        j 2b

    3:
        call main

        1:
        ebreak
        j 1b
    "#
);
