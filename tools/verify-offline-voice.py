#!/usr/bin/env python3
"""Verify a Core Speech Kit HAP contains no retired bundled voice or native runtime."""

import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_HAP = ROOT / "entry/build/default/outputs/default/entry-default-signed.hap"
RETIRED_LIBRARIES = {"liboffline_tts.so", "libonnxruntime.so", "libflite.so"}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def verify(hap: Path) -> None:
    with zipfile.ZipFile(hap) as archive:
        names = archive.namelist()
        require(len(names) == len(set(names)), "HAP contains duplicate ZIP entry names")
        retired = [name for name in names if name.startswith("resources/rawfile/speech/")
                   or name.lower().endswith(".onnx") or Path(name).name in RETIRED_LIBRARIES]
        require(not retired, f"Retired voice resources remain: {retired}")
        print("PASS no bundled voice model, offline_tts, ONNX Runtime or Flite library")

        entry = archive.getinfo("module.json")
        require(0 < entry.file_size <= 1024 * 1024, "Invalid module configuration size")
        with archive.open(entry) as stream:
            module = json.load(stream).get("module")
        require(isinstance(module, dict), "Missing module configuration")
        permissions = module.get("requestPermissions", [])
        require(isinstance(permissions, list), "Invalid requestPermissions")
        require(all(isinstance(permission, dict) and isinstance(permission.get("name"), str)
                    for permission in permissions), "Malformed permission declaration")
        require(not any(permission["name"] == "ohos.permission.INTERNET" for permission in permissions),
                "HAP requests INTERNET permission")
        print("PASS application has no INTERNET permission; explicit voice download belongs to Core Speech Kit")

        license_path = "resources/rawfile/licenses/ECDICT-MIT.txt"
        expected = (ROOT / "entry/src/main" / license_path).read_bytes()
        require(hashlib.sha256(archive.read(license_path)).digest() == hashlib.sha256(expected).digest(),
                "ECDICT attribution differs from source")
        print("PASS bundled dictionary license is preserved")
    print(f"Core Speech package verified: {hap} ({hap.stat().st_size:,} bytes)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hap", nargs="?", type=Path, default=DEFAULT_HAP, help="signed HAP path")
    args = parser.parse_args()
    try:
        verify(args.hap.resolve())
    except (OSError, KeyError, ValueError, zipfile.BadZipFile, RuntimeError) as error:
        print(f"FAIL Core Speech package: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
