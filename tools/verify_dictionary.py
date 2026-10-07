#!/usr/bin/env python3
"""Validate the bundled seed dictionaries without third-party dependencies.

Usage: python3 tools/verify_dictionary.py [path/to/catalog.json]
The optional path also makes this useful before replacing the bundled content.
"""

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CATALOG = ROOT / "entry/src/main/resources/rawfile/wordbooks/catalog.json"
EXPECTED_BOOKS = {"cet4": 3800, "cet6": 5300, "graduate": 4700, "ielts": 4900, "toefl": 6800}
WORD_FIELDS = {"word", "phonetic", "meaning", "example", "translation"}
BOOK_FIELDS = {"id", "name", "category", "description", "words"}
CHINESE = re.compile(r"[\u3400-\u9fff]")
HEADWORD = re.compile(r"(?:[a-z]+(?:[-' ][a-z]+)*|[a-z](?:\.[a-z])+\.)\Z")


def example_contains_headword(word: str, example: str) -> bool:
    """Accept ordinary English inflections while rejecting unrelated filler."""
    forms = {word, word + "s", word + "es", word + "ed", word + "ing"}
    if word.endswith("e"):
        forms.update({word + "d", word[:-1] + "ing"})
    if word.endswith("y"):
        forms.update({word[:-1] + "ies", word[:-1] + "ied"})
    if word:
        forms.update({word + word[-1] + "ed", word + word[-1] + "ing"})
    irregular = {
        "be": {"am", "is", "are", "was", "were", "been", "being"},
        "go": {"went", "gone"}, "do": {"does", "did", "done"},
        "have": {"has", "had"}, "make": {"made"}, "take": {"took", "taken"},
        "write": {"wrote", "written"}, "give": {"gave", "given"},
        "find": {"found"}, "think": {"thought"}, "know": {"knew", "known"},
        "see": {"saw", "seen"}, "come": {"came"}, "run": {"ran"},
        "learn": {"learnt"}, "teach": {"taught"}, "child": {"children"},
        "person": {"people"}, "analysis": {"analyses"},
        "criterion": {"criteria"}, "phenomenon": {"phenomena"},
        "nucleus": {"nuclei"}, "stratum": {"strata"},
    }
    forms.update(irregular.get(word, set()))
    pattern = "|".join(re.escape(form) for form in sorted(forms, key=len, reverse=True))
    return bool(re.search(r"\b(?:" + pattern + r")\b", example.casefold()))


def validate_catalog(catalog: object) -> dict:
    """Raise ValueError for unusable or inconsistent vocabulary content."""
    errors = []
    if not isinstance(catalog, dict) or set(catalog) != {"version", "books"}:
        raise ValueError("根对象必须只包含 version 和 books")
    if type(catalog["version"]) is not int or catalog["version"] < 1:
        errors.append("version 必须是正整数")
    if not isinstance(catalog["books"], list):
        raise ValueError("books 必须是数组")

    book_ids = []
    counts = {}
    canonical = {}
    examples = Counter()
    pronunciation_count = 0
    example_count = 0
    membership_count = 0

    for book_index, book in enumerate(catalog["books"]):
        location = f"books[{book_index}]"
        if not isinstance(book, dict) or set(book) != BOOK_FIELDS:
            errors.append(f"{location}: 字段必须为 {sorted(BOOK_FIELDS)}")
            continue
        book_id = book["id"]
        if not isinstance(book_id, str):
            errors.append(f"{location}: id 必须为字符串")
            continue
        book_ids.append(book_id)
        for field in ("id", "name", "category", "description"):
            value = book[field]
            if not isinstance(value, str) or not value.strip() or value != value.strip():
                errors.append(f"{location}.{field}: 必须是没有首尾空格的非空字符串")
        words = book["words"]
        if not isinstance(words, list):
            errors.append(f"{location}.words: 必须为数组")
            continue
        counts[book_id] = len(words)
        if len(words) < EXPECTED_BOOKS.get(book_id, 1):
            errors.append(f"{book_id}: 至少需要 {EXPECTED_BOOKS.get(book_id, 1)} 个词条")
        if len(words) >= 50_000:
            errors.append(f"{book_id}: 单本词书需要小于 50,000 个词条")
        if isinstance(book["description"], str) and f"{len(words)} 个" not in book["description"]:
            errors.append(f"{book_id}: description 必须如实标注 {len(words)} 个词")

        seen = set()
        for word_index, entry in enumerate(words):
            location = f"{book_id}.words[{word_index}]"
            if not isinstance(entry, dict) or set(entry) != WORD_FIELDS:
                errors.append(f"{location}: 字段必须为 {sorted(WORD_FIELDS)}")
                continue
            if any(not isinstance(value, str) for value in entry.values()):
                errors.append(f"{location}: 词条字段必须全为字符串")
                continue
            if any(value != value.strip() for value in entry.values()):
                errors.append(f"{location}: 字段不得包含首尾空白")
            if any(not entry[field] for field in ("word", "meaning")):
                errors.append(f"{location}: word 与 meaning 必须有内容")
            if bool(entry["example"]) != bool(entry["translation"]):
                errors.append(f"{location}: 例句与译文需要同时填写或同时留空")
            word = entry["word"]
            if not HEADWORD.fullmatch(word):
                errors.append(f"{location}: word 必须是规范小写英文词头")
            if word in seen:
                errors.append(f"{location}: 同一本词书出现重复词头 {word}")
            seen.add(word)
            if word in canonical and canonical[word] != entry:
                errors.append(f"{location}: 跨词书同一词头 {word} 的释义、音标或例句不一致")
            if word not in canonical:
                canonical[word] = entry
                if entry["example"]:
                    examples[entry["example"].casefold()] += 1
                    example_count += 1
                pronunciation_count += bool(entry["phonetic"])
            membership_count += 1

            if not CHINESE.search(entry["meaning"]):
                errors.append(f"{location}: meaning 需要中文核心释义")
            if entry["translation"] and not CHINESE.search(entry["translation"]):
                errors.append(f"{location}: translation 需要中文译文")
            if entry["example"] and (len(entry["example"]) < 12 or len(entry["example"]) > 240):
                errors.append(f"{location}: example 应为 12 至 240 字符的短句")
            if entry["translation"] and (len(entry["translation"]) < 4 or len(entry["translation"]) > 160):
                errors.append(f"{location}: translation 应为 4 至 160 字符的短译文")
            if entry["example"] and not example_contains_headword(word, entry["example"]):
                errors.append(f"{location}: 例句应包含该词或其常见屈折形式")
            if entry["example"] and entry["example"][-1:] not in {".", "?", "!"}:
                errors.append(f"{location}: 英文例句需要句末标点")
            if entry["translation"] and entry["translation"][-1:] not in {"。", "？", "！"}:
                errors.append(f"{location}: 中文译文需要句末标点")
            if entry["phonetic"] and not (
                entry["phonetic"].startswith("/") and entry["phonetic"].endswith("/")
            ):
                errors.append(f"{location}: 非空 phonetic 需要使用 /.../ 形式")

    if set(book_ids) != set(EXPECTED_BOOKS):
        errors.append(f"词书 ID 必须为 {sorted(EXPECTED_BOOKS)}")
    if len(book_ids) != len(set(book_ids)):
        errors.append("词书 ID 不得重复")
    repeated_examples = [example for example, count in examples.items() if count > 1]
    if repeated_examples:
        errors.append("不同词头不得用完全相同的例句填充")
    if errors:
        raise ValueError("\n".join(errors))
    return {
        "version": catalog["version"],
        "books": counts,
        "memberships": membership_count,
        "uniqueWords": len(canonical),
        "wordsWithPhonetic": pronunciation_count,
        "wordsWithOriginalExamples": example_count,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("catalog", nargs="?", type=Path, default=DEFAULT_CATALOG)
    args = parser.parse_args()
    try:
        if args.catalog.stat().st_size >= 5_000_000:
            raise ValueError("词库 JSON 需要小于 5 MB")
        catalog = json.loads(args.catalog.read_text(encoding="utf-8"))
        summary = validate_catalog(catalog)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as error:
        print(f"词库校验失败：{error}", file=sys.stderr)
        return 1
    print("词库结构与内容完整性校验通过")
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
