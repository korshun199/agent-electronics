#!/usr/bin/env python3
"""Validate the packaged Intel HEX syntax, record checksums, and target range."""

from pathlib import Path
import sys


def main():
    default_image = Path(__file__).resolve().parents[1] / "firmware" / "HAKRCF405V2_MashaOperatorHID.hex"
    image_path = Path(sys.argv[1]).resolve() if len(sys.argv) == 2 else default_image
    if len(sys.argv) > 2:
        print("Usage: verify_firmware.py [path/to/image.hex]", file=sys.stderr)
        return 2
    flash_start = 0x08000000
    flash_end = flash_start + 1024 * 1024
    base_address = 0
    addresses = set()
    eof_seen = False

    try:
        lines = image_path.read_text(encoding="ascii").splitlines()
    except OSError as error:
        print(f"ERROR: cannot read {image_path}: {error}", file=sys.stderr)
        return 2

    try:
        for line_number, line in enumerate(lines, 1):
            if not line.startswith(":"):
                raise ValueError(f"line {line_number}: missing ':'")
            record = bytes.fromhex(line[1:])
            if len(record) < 5 or len(record) != record[0] + 5:
                raise ValueError(f"line {line_number}: invalid record length")
            if sum(record) & 0xFF:
                raise ValueError(f"line {line_number}: checksum mismatch")

            count = record[0]
            offset = int.from_bytes(record[1:3], "big")
            kind = record[3]
            data = record[4 : 4 + count]

            if eof_seen:
                raise ValueError(f"line {line_number}: data after EOF")
            if kind == 0:
                start = base_address + offset
                for address in range(start, start + count):
                    if not flash_start <= address < flash_end:
                        raise ValueError(f"line {line_number}: address outside STM32F405 flash")
                    if address in addresses:
                        raise ValueError(f"line {line_number}: duplicate data address 0x{address:08X}")
                    addresses.add(address)
            elif kind == 1:
                if count != 0:
                    raise ValueError(f"line {line_number}: malformed EOF record")
                eof_seen = True
            elif kind == 2:
                if count != 2:
                    raise ValueError(f"line {line_number}: malformed segment address")
                base_address = int.from_bytes(data, "big") << 4
            elif kind == 4:
                if count != 2:
                    raise ValueError(f"line {line_number}: malformed linear address")
                base_address = int.from_bytes(data, "big") << 16
            elif kind in (3, 5):
                continue
            else:
                raise ValueError(f"line {line_number}: unsupported record type {kind}")
    except (ValueError, IndexError) as error:
        print(f"ERROR: invalid Intel HEX: {error}", file=sys.stderr)
        return 1

    if not eof_seen or not addresses:
        print("ERROR: missing EOF or image data", file=sys.stderr)
        return 1

    print(f"Intel HEX OK: {len(addresses)} data bytes, address range 0x{min(addresses):08X}..0x{max(addresses):08X}")
    print("Flash writes were not performed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
