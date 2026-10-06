OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x0000E000
}

SECTIONS
{
    . = ORIGIN(RAM);
    .text : ALIGN(4)
    {
        KEEP(*(.init))
        *(.text .text.*)
    } > RAM

    .rodata : ALIGN(4)
    {
        *(.rodata .rodata.*)
    } > RAM

    .data : ALIGN(4)
    {
        *(.data .data.*)
    } > RAM

    .bss (NOLOAD) : ALIGN(4)
    {
        __bss_start = .;
        *(.bss .bss.* COMMON)
        __bss_end = .;
    } > RAM

    . = ALIGN(16);
    _end = .;
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}

ASSERT(_end < 0x0000D000, "Experiment G image overlaps the reserved stack area")

