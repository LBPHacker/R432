use core::arch::global_asm;

global_asm!(
    r#"
        .section .start

        .globl _start
        .globl main
        .globl end_stack

    _start:
        lla sp, end_stack
        call main

        1:
        ebreak
        j 1b
    "#
);
