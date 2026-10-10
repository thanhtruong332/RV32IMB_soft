# v1.2.2

Removes three redundant `& 0xffu` masks from `firmware/src/aes128_scaling.c` (`copy_words`, `plaintext_byte`, `sub_bytes`). Every value reaching these lines is already in 0..255, so all intermediate values and ciphertexts are unchanged, but GCC no longer emits `lbu`: the 12 firmware images now use only `lw`/`sw` for memory access.

All 12 firmware images, ELF/map files, testbench `OUTPUT_INDEX` values, the 36 raw XSim logs and the counter tables were regenerated with Vivado 2024.2. All runs pass the NIST SP 800-38A check. 16 B results are unchanged; 256 B and 4 KiB runs retire 16 fewer instructions per block on every core, and pipeline stall counts are unchanged.
