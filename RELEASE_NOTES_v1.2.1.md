# v1.2.1

Packaging fix only. No RTL logic, firmware, testbench check or measured result changed relative to v1.2.0.

- Added `.gitattributes` (`* -text`) so every file is checked out byte-for-byte on all platforms.
- Regenerated `reproducibility/SHA256SUMS.txt` from the committed file contents; the v1.2.0 list had been computed on Windows CRLF working copies and failed on fresh clones.
- Includes the source clean-up made after v1.2.0: comment and whitespace changes in RTL, plus extra summary `$display` lines in the testbenches.
