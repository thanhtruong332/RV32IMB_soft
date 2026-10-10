# Reproducibility evidence — RV32IMB_soft

This directory is the compact reviewer-facing evidence package for release `v1.2.2`.
The Git commit is the commit referenced by the annotated release tag; resolve it with
`git rev-parse v1.2.2^{commit}`.

| Requested item | Location / status |
| --- | --- |
| RTL commit hash | Annotated tag `v1.2.2` |
| Firmware hash | `firmware/build_manifest.json` and `SHA256SUMS.txt` |
| Vivado/XSim version | `metadata.json` and the 36 raw XSim logs |
| Tcl scripts | Project/test scripts at `../scripts/` |
| XDC | Not applicable to this behavioral Experiment G project |
| Compiler version / flags | `firmware/build_manifest.json` and `raw_counters/run_manifest.json` |
| Linker script | `../firmware/src/linker.ld` |
| ELF / map | `firmware/` contains 12 exact pairs |
| Raw counters | `raw_counters/raw_results.csv`, `summary.csv`, and `raw_counters/logs/` |
| SAIF/VCD and physical reports | Not generated for Experiment G; those artifacts are in the three hardware SoC repositories |
| Seed scripts | Not applicable to deterministic behavioral simulation |
| Expected NIST vectors | `expected/nist_sp_800_38a_vectors.csv`; every raw log also records observed/expected blocks |

`raw_results.csv` is filtered to `RV32IMB` and its log paths are normalized to this
repository. Measurement values and the stored SHA-256 hashes of the original logs are
unchanged. Verify every packaged file with:

```text
python reproducibility/verify_sha256.py
```
