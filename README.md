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
- `scripts/create_project.tcl`: creates a portable Vivado project.
- `scripts/run_smoke.tcl`: runs the 16 B ECB self-checking smoke test.

## Recreate and test

Requirements: Vivado 2024.2 with device support for `xc7z020clg484-2`.

```powershell
vivado -mode batch -source scripts/create_project.tcl
vivado -mode batch -source scripts/run_smoke.tcl
```

A passing smoke run prints `RESULT=PASS`. To run another condition, set the `sim_1` top to the corresponding module in `sim/`.

Architecture, memory-model and compiler metadata are listed in [`docs/REPRODUCIBILITY.md`](docs/REPRODUCIBILITY.md).

To rebuild firmware, install a `riscv-none-elf` GCC toolchain and PyCryptodome, then either add the toolchain to `PATH` or set `RISCV_TOOLCHAIN` to its `bin` directory:

```powershell
python firmware/src/build_payload_scaling.py
```

## License

See `LICENSE_STATUS.md`.
