from __future__ import annotations

import hashlib
import json
import re
import os
import shutil
import subprocess
from pathlib import Path

from Crypto.Cipher import AES


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "build"
TOOLROOT = Path(os.environ["RISCV_TOOLCHAIN"]) if os.environ.get("RISCV_TOOLCHAIN") else None

def tool(name: str) -> Path:
    exe = f"{name}.exe" if os.name == "nt" else name
    if TOOLROOT:
        candidate = TOOLROOT / exe
        if candidate.exists():
            return candidate
    found = shutil.which(name) or shutil.which(exe)
    if not found:
        raise FileNotFoundError(f"{name} was not found; set RISCV_TOOLCHAIN to the toolchain bin directory")
    return Path(found)

GCC = tool("riscv-none-elf-gcc")
OBJCOPY = tool("riscv-none-elf-objcopy")
OBJDUMP = tool("riscv-none-elf-objdump")
SIZE = tool("riscv-none-elf-size")
NM = tool("riscv-none-elf-nm")

MODES = {"ECB": 1, "CBC": 2, "CFB128": 3, "CTR": 4}
PAYLOADS = {"16B": 1, "256B": 16, "4KiB": 256}
FLAGS = [
    "-O2", "-march=rv32i", "-mabi=ilp32", "-mcmodel=medlow",
    "-msmall-data-limit=0", "-ffreestanding", "-fno-builtin",
    "-fno-pic", "-fno-pie", "-fno-stack-protector",
    "-ffunction-sections", "-fdata-sections", "-Wall", "-Wextra",
]

KEY = bytes.fromhex("2b7e151628aed2a6abf7158809cf4f3c")
IV = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
COUNTER = bytes.fromhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")
SEED = bytes.fromhex(
    "6bc1bee22e409f96e93d7e117393172a"
    "ae2d8a571e03ac9c9eb76fac45af8e51"
    "30c81c46a35ce411e5fbc1191a0a52ef"
    "f69f2445df4f9b17ad2b417be66c3710"
)


def run(args: list[str]) -> str:
    proc = subprocess.run(args, check=True, text=True, capture_output=True)
    return proc.stdout


def payload(blocks: int) -> bytes:
    out = bytearray()
    for block in range(blocks):
        base = SEED[(block & 3) * 16 : ((block & 3) + 1) * 16]
        mask = (block >> 2) & 0xFF
        out.extend(byte ^ mask for byte in base)
    return bytes(out)


def expected(mode: str, data: bytes) -> bytes:
    if mode == "ECB":
        return AES.new(KEY, AES.MODE_ECB).encrypt(data)
    if mode == "CBC":
        return AES.new(KEY, AES.MODE_CBC, iv=IV).encrypt(data)
    if mode == "CFB128":
        return AES.new(KEY, AES.MODE_CFB, iv=IV, segment_size=128).encrypt(data)
    if mode == "CTR":
        return AES.new(KEY, AES.MODE_CTR, nonce=b"", initial_value=int.from_bytes(COUNTER, "big")).encrypt(data)
    raise ValueError(mode)


def fnv1a(data: bytes) -> int:
    value = 2166136261
    for byte in data:
        value ^= byte
        value = (value * 16777619) & 0xFFFFFFFF
    return value


def binary_to_mem(binary: Path, mem: Path) -> None:
    data = binary.read_bytes()
    if len(data) % 4:
        data += bytes(4 - len(data) % 4)
    words = [data[i : i + 4][::-1].hex() for i in range(0, len(data), 4)]
    mem.write_text("\n".join(words) + "\n", encoding="ascii")


def section_sizes(elf: Path) -> dict[str, int]:
    text = run([str(SIZE), "-A", str(elf)])
    sizes = {}
    for line in text.splitlines():
        match = re.match(r"^(\.\S+)\s+(\d+)\s+", line.strip())
        if match:
            sizes[match.group(1)] = int(match.group(2))
    return {
        "text": sizes.get(".text", 0),
        "rodata": sizes.get(".rodata", 0),
        "data": sizes.get(".data", 0),
        "bss": sizes.get(".bss", 0),
        "total_load_image": sum(sizes.get(x, 0) for x in (".text", ".rodata", ".data")),
        "total_memory": sum(sizes.get(x, 0) for x in (".text", ".rodata", ".data", ".bss")),
    }


def symbols(elf: Path) -> dict[str, int]:
    result = {}
    for line in run([str(NM), "-n", str(elf)]).splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] in {"exp_g_output", "exp_g_errors", "_end"}:
            result[fields[2]] = int(fields[0], 16)
    return result


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "compiler": run([str(GCC), "--version"]).splitlines()[0],
        "flags": FLAGS,
        "clock_hz": 40_000_000,
        "memory_model": "64 KiB unified zero-wait-state simulation RAM; each AES logical byte stored in one u32",
        "payloads": {},
    }
    for payload_name, blocks in PAYLOADS.items():
        data = payload(blocks)
        manifest["payloads"][payload_name] = {"payload_bytes": len(data), "blocks": blocks, "firmware": {}}
        for mode, mode_id in MODES.items():
            exp = expected(mode, data)
            checksum = fnv1a(exp)
            stem = f"expG_{payload_name}_{mode}"
            elf = OUT / f"{stem}.elf"
            binary = OUT / f"{stem}.bin"
            mem = OUT / f"{stem}.mem"
            expected_bin = OUT / f"{stem}.expected.bin"
            map_file = OUT / f"{stem}.map"
            dis = OUT / f"{stem}.disassembly.txt"
            cmd = [
                str(GCC), *FLAGS, f"-DEXP_G_MODE={mode_id}", f"-DEXP_G_BLOCKS={blocks}",
                f"-DEXP_G_EXPECTED_FNV=0x{checksum:08x}u", "-nostdlib",
                str(ROOT / "startup.S"), str(ROOT / "aes128_scaling.c"),
                f"-Wl,-T,{ROOT / 'linker.ld'}", "-Wl,--gc-sections", f"-Wl,-Map,{map_file}",
                "-o", str(elf),
            ]
            run(cmd)
            run([str(OBJCOPY), "-O", "binary", str(elf), str(binary)])
            binary_to_mem(binary, mem)
            expected_bin.write_bytes(exp)
            dis.write_text(run([str(OBJDUMP), "-d", "-S", str(elf)]), encoding="utf-8")
            sec = section_sizes(elf)
            syms = symbols(elf)
            if syms["_end"] >= 0xE000:
                raise RuntimeError(f"{stem}: program overlaps stack: _end=0x{syms['_end']:x}")
            manifest["payloads"][payload_name]["firmware"][mode] = {
                "mode_id": mode_id,
                "elf": str(elf),
                "mem": str(mem),
                "expected_bin": str(expected_bin),
                "expected_fnv1a": f"0x{checksum:08X}",
                "sha256_mem": hashlib.sha256(mem.read_bytes()).hexdigest().upper(),
                "sha256_expected": hashlib.sha256(exp).hexdigest().upper(),
                "sections": sec,
                "symbols": syms,
            }
    (OUT / "build_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"built={len(PAYLOADS) * len(MODES)}")
    print(OUT / "build_manifest.json")


if __name__ == "__main__":
    main()
