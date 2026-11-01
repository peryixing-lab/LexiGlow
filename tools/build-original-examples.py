#!/usr/bin/env python3
"""Package the project's authored bilingual sentences for offline cloze practice.

No corpus or network request is used. Multiple headwords may share one authored
sentence; every generated entry contains its exact headword as an English token.
The TSV remains the editable, reviewable source of the original content.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tools/data/original_examples.tsv'
CATALOG = ROOT / 'entry/src/main/resources/rawfile/wordbooks/catalog.json'
OUTPUT = ROOT / 'entry/src/main/resources/rawfile/examples/original-examples-v1.json'


def main() -> None:
    catalog = json.loads(CATALOG.read_text())
    headwords = {word['word'].lower() for book in catalog['books'] for word in book['words']}
    examples: dict[str, dict[str, str]] = {}
    sentence_count = 0
    for number, row in enumerate(SOURCE.read_text().splitlines(), 1):
        if not row.strip() or row.startswith('#'):
            continue
        fields = row.split('\t')
        if len(fields) != 2:
            raise ValueError(f'Line {number}: expected one English sentence and one Chinese translation')
        english, chinese = fields
        if not re.search(r'[\u3400-\u9fff]', chinese) or not english.endswith(('.', '!', '?')):
            raise ValueError(f'Line {number}: missing complete bilingual content')
        sentence_count += 1
        tokens = {token.lower() for token in re.findall(r"[A-Za-z][A-Za-z'-]*", english)}
        for headword in tokens & headwords:
            if re.fullmatch(r'[a-z]{3,30}', headword):
                examples.setdefault(headword, {
                    'headword': headword, 'example': english, 'translation': chinese
                })
    if len(examples) < 1000:
        raise ValueError(f'Only {len(examples)} dictionary headwords covered; 1,000 required')
    pack = {
        'version': 1,
        'license': 'GPL-3.0-only',
        'licenseFile': 'licenses/LexiGlow-GPL-3.0.txt',
        'provenance': 'Original learning material authored for LexiGlow; no third-party sentence corpus used.',
        'source': 'tools/data/original_examples.tsv',
        'sentenceCount': sentence_count,
        'headwordCount': len(examples),
        'examples': [examples[word] for word in sorted(examples)],
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(pack, ensure_ascii=False, indent=2) + '\n')
    print(f'{sentence_count} original bilingual sentences cover {len(examples)} dictionary headwords.')


if __name__ == '__main__':
    main()
