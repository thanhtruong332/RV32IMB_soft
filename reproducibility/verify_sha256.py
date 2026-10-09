#!/usr/bin/env python3
"""Verify every file listed in reproducibility/SHA256SUMS.txt."""
from pathlib import Path
import hashlib
import sys

repo = Path(__file__).resolve().parents[1]
sums = repo / "reproducibility" / "SHA256SUMS.txt"
errors = 0
for line in sums.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    expected, rel = line.split("  ", 1)
    path = repo / Path(rel)
    if not path.is_file():
        print(f"MISSING  {rel}")
        errors += 1
        continue
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual.lower() != expected.lower():
        print(f"FAILED   {rel}")
        errors += 1
if errors:
    raise SystemExit(f"SHA-256 verification failed for {errors} file(s)")
print("SHA-256 verification PASS")
