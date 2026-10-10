# Reproducibility metadata

| Item | Value |
| --- | --- |
| RTL origin | Custom RTL snapshot supplied by the project owner |
| Repository | https://github.com/thanhtruong332/RV32IMB_soft |
| Release | `v1.2.2` (use `git rev-parse v1.2.2^{commit}` for the immutable commit) |
| License | No open-source license is declared; see `LICENSE_STATUS.md` |
| ISA | RV32I 2.1 with integrated M operations and a B subset |
| Pipeline | Five stages: IF, ID, EX, MEM and WB |
| Branch resolution | EX stage; a taken branch or jump flushes the two younger slots |
| Forwarding | EX/MEM and MEM/WB forwarding paths |
| Hazard detection | Load-use detector stalls the dependent instruction |
| Multiplier/divider | MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM and REMU |
| Bit manipulation | CLZ, CTZ and CPOP subset |
| Register file | 32 x 32-bit; synchronous write and asynchronous read, with same-cycle write bypass |
| Experiment memory model | Unified 64 KiB zero-wait-state simulation memory |
| Workload | Pure-software AES-128 ECB, CBC, CFB-128 and CTR; no AES accelerator |
| Payloads | 16 B, 256 B and 4 KiB |
| Compiler target | `-O2 -march=rv32i -mabi=ilp32` |
| Additional compiler flags | `-mcmodel=medlow -msmall-data-limit=0 -ffreestanding -fno-builtin -fno-pic -fno-pie -fno-stack-protector -ffunction-sections -fdata-sections` |
| Experiment G ISA usage | The common binary targets RV32I; therefore measured M-count and B-count are both zero |
| Clock / simulator | 40 MHz; Vivado/XSim 2024.2 |

The twelve committed memory images correspond to four AES modes and three
payloads. The matching self-checking testbenches report cycle and instruction
counters and compare every ciphertext block with its expected value.

## Curated evidence package

The [`reproducibility/`](../reproducibility/) directory contains the measured artifacts, tool metadata and SHA-256 inventory associated with this release. Run `python reproducibility/verify_sha256.py` from any directory to verify it.
