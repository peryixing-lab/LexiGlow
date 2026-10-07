#!/usr/bin/env python3
"""Reproduce the bundled wordbooks from the pinned ECDICT CSV snapshot.

Download ecdict.csv from SOURCE_URL to a temporary directory, then run:
    python3 tools/build_dictionary.py /private/tmp/lexiglow-ecdict.csv

The hash is checked before any output is replaced. This script intentionally
does not download data or modify user learning records.
"""

import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_COMMIT = "bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b"
SOURCE_URL = f"https://raw.githubusercontent.com/skywind3000/ECDICT/{SOURCE_COMMIT}/ecdict.csv"
SOURCE_SHA256 = "1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf"
SOURCE_REPOSITORY = "https://github.com/skywind3000/ECDICT"
SOURCE_LICENSE_URL = f"{SOURCE_REPOSITORY}/blob/{SOURCE_COMMIT}/LICENSE"
SOURCE_COMMIT_DATE = "2025-03-28"
CATALOG_PATH = ROOT / "entry/src/main/resources/rawfile/wordbooks/catalog.json"
OVERRIDES_PATH = ROOT / "tools/data/dictionary_overrides.json"
MANIFEST_PATH = ROOT / "docs/DICTIONARY_SOURCE.json"
BOOKS = (
    ("cet4", "cet4", "四级 · ECDICT 词书"),
    ("cet6", "cet6", "六级 · ECDICT 词书"),
    ("graduate", "ky", "考研 · ECDICT 词书"),
    ("ielts", "ielts", "雅思 · ECDICT 词书"),
    ("toefl", "toefl", "托福 · ECDICT 词书"),
)
CHINESE = re.compile(r"[\u3400-\u9fff]")
HEADWORD = re.compile(r"(?:[a-z]+(?:[-' ][a-z]+)*|[a-z](?:\.[a-z])+\.)\Z")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def frequency_key(row: dict) -> tuple:
    def rank(value: str) -> int:
        return int(value) if value.isdigit() and int(value) > 0 else 10**9
    return rank(row["frq"]), rank(row["bnc"]), row["word"].casefold()


def build_catalog(csv_path: Path) -> dict:
    actual_hash = file_sha256(csv_path)
    if actual_hash != SOURCE_SHA256:
        raise ValueError(f"源文件 SHA-256 不匹配：{actual_hash}")
    overrides = json.loads(OVERRIDES_PATH.read_text(encoding="utf-8"))
    tags = {tag for _, tag, _ in BOOKS}
    raw_counts = Counter()
    filtered = {tag: [] for tag in tags}
    records = {}
    source_rows = 0

    with csv_path.open(encoding="utf-8-sig", newline="") as file:
        for row in csv.DictReader(file):
            source_rows += 1
            selected_tags = tags.intersection(row["tag"].split())
            if not selected_tags:
                continue
            raw_counts.update(selected_tags)
            word = row["word"].strip().casefold()
            # ECDICT stores escaped newline sequences in its CSV fields.
            lines = re.sub(r"\\+n", "\n", row["translation"]).splitlines()
            meaning = next((line.strip() for line in lines if line.strip()), "")
            phonetic = row["phonetic"].strip().strip("/[]")
            entry = overrides.get(word, {
                "word": word,
                "phonetic": f"/{phonetic}/" if phonetic else "",
                "meaning": meaning,
                "example": "",
                "translation": "",
            })
            if not HEADWORD.fullmatch(word) or not CHINESE.search(entry["meaning"]):
                for tag in selected_tags:
                    filtered[tag].append(word)
                continue
            if word in records:
                records[word]["tags"].update(selected_tags)
                continue
            records[word] = {"entry": entry, "tags": selected_tags, "order": frequency_key(row)}

    ordered = sorted(records.values(), key=lambda record: record["order"])
    books = []
    for book_id, tag, name in BOOKS:
        words = [record["entry"] for record in ordered if tag in record["tags"]]
        books.append({
            "id": book_id,
            "name": name,
            "category": "考试词书",
            "description": f"{len(words)} 个词 · ECDICT {tag} 标签；非现行官方大纲认证。",
            "words": words,
        })
    catalog = {"version": 2, "books": books}
    # Compact JSON keeps five overlapping books below 5 MB without cutting words.
    payload = (json.dumps(catalog, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    if len(payload) >= 5_000_000:
        raise ValueError(f"词库超出 5 MB 资源预算：{len(payload)} bytes")
    CATALOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CATALOG_PATH.write_bytes(payload)
    manifest = {
        "dictionaryVersion": 2,
        "sourceRepository": SOURCE_REPOSITORY,
        "sourceCommit": SOURCE_COMMIT,
        "sourceCommitDate": SOURCE_COMMIT_DATE,
        "sourceUrl": SOURCE_URL,
        "sourceSha256": actual_hash,
        "sourceLicense": "MIT",
        "sourceLicenseUrl": SOURCE_LICENSE_URL,
        "sourceLicenseCopyright": "Copyright (c) 2025 Linwei",
        "sourceRows": source_rows,
        "rawTagCounts": dict(sorted(raw_counts.items())),
        "filteredWordsByTag": dict(sorted(filtered.items())),
        "books": {book["id"]: len(book["words"]) for book in books},
        "uniqueWords": len(records),
        "wordsWithOriginalExamples": sum(bool(record["entry"]["example"]) for record in records.values()),
        "catalogBytes": len(payload),
        "catalogSha256": hashlib.sha256(payload).hexdigest(),
        "examSyllabusYear": None,
        "transform": "Lowercase word heads, preserve source exam tags, sort by contemporary frequency then BNC rank, use first nonempty Chinese definition line, apply original editorial overrides, no invented examples.",
    }
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path)
    args = parser.parse_args()
    manifest = build_catalog(args.csv)
    print(json.dumps({key: manifest[key] for key in ("books", "uniqueWords", "wordsWithOriginalExamples", "catalogBytes")}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
