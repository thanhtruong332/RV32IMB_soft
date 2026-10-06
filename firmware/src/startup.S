    .section .init, "ax", @progbits
    .globl _start
    .type _start, @function
_start:
    lui  sp, %hi(_stack_top)
    addi sp, sp, %lo(_stack_top)
    jal  ra, main
1:
    jal  zero, 1b
    .size _start, .-_start

