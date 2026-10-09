# RV32IMB_soft

Pure-software AES-128 profiling package for the `RV32IMB` core. The AES hardware accelerator is not instantiated or used.

## Workload

- AES-128 ECB, CBC, CFB-128 and CTR.
- Payloads: 16 B, 256 B and 4 KiB.
- Compiler target: `-O2 -march=rv32i -mabi=ilp32`.
- Simulation clock: 40 MHz.
- Unified 64 KiB zero-wait-state memory model.

## Contents

- `rtl/`: CPU RTL used by Experiment G.
- `firmware/src/`: AES source, startup code, linker script and portable build script.
- `firmware/images/`: the 12 memory images used by the testbenches.
- `sim/`: self-checking Vivado/XSim testbenches for every mode and payload.
- [`TEST_MATRIX.md`](TEST_MATRIX.md): exact mapping of all 12 testbenches to firmware images.
- `scripts/create_project.tcl`: creates a portable Vivado project.
- `scripts/run_test.tcl`: runs any selected self-checking condition.
- `scripts/run_all_tests.ps1`: runs all 12 conditions.

## Recreate and test

Requirements: Vivado 2024.2 with device support for `xc7z020clg484-2`.

```powershell
vivado -mode batch -source scripts/create_project.tcl
vivado -mode batch -source scripts/run_test.tcl -tclargs CFB_256B
powershell -ExecutionPolicy Bypass -File scripts/run_all_tests.ps1 -Vivado vivado
```

A passing condition prints `RESULT=PASS`. Valid condition names are listed in [`TEST_MATRIX.md`](TEST_MATRIX.md).

Architecture, memory-model and compiler metadata are listed in [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md).

To rebuild firmware, install a `riscv-none-elf` GCC toolchain and PyCryptodome, then either add the toolchain to `PATH` or set `RISCV_TOOLCHAIN` to its `bin` directory:

```powershell
python firmware/src/build_payload_scaling.py
```

## Evidence package

The reviewer-facing [`reproducibility/`](reproducibility/) directory records tool versions, raw evidence and SHA-256 hashes for release `v1.2.0`.

## License

See `LICENSE_STATUS.md`.
