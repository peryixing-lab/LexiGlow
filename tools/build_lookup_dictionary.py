#!/usr/bin/env python3
"""Build the query-only dictionary from the same pinned, hash-verified ECDICT snapshot.

This does not rewrite the five learning books, their order, or any learning data.
Usage: python3 tools/build_lookup_dictionary.py /path/to/ecdict.csv
"""
import argparse
import csv
import hashlib
import json
import re
from pathlib import Path

from build_dictionary import SOURCE_COMMIT, SOURCE_SHA256, SOURCE_URL

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'entry/src/main/resources/rawfile/dictionary/lookup-v1.json'
MANIFEST = ROOT / 'docs/LOOKUP_DICTIONARY_SOURCE.json'
HEADWORD = re.compile(r"[a-z]+(?:[-' ][a-z]+)*\Z")
CHINESE = re.compile(r'[\u3400-\u9fff]')
TOKEN = re.compile(r"[a-z]+(?:'[a-z]+)*")


def full_meaning(text: str) -> str:
    lines = re.sub(r'\\+n', '\n', text).splitlines()
    result = '\n'.join(dict.fromkeys(line.strip() for line in lines if line.strip()))
    if len(result) > 4000:
        raise ValueError('源词条释义超过备份的 4000 字限制，需人工审阅后明确调整限制')
    return result


def fields(exchange: str):
    for part in exchange.split('/'):
        if ':' not in part:
            continue
        kind, forms = part.split(':', 1)
        for form in forms.split(','):
            form = form.strip().lower()
            if HEADWORD.fullmatch(form):
                yield kind, form


def article_texts():
    source = (ROOT / 'entry/src/main/ets/data/CuratedArticles.ets').read_text()
    # Reading helpers keep the body as the third string argument; decode only escaped ASCII.
    pattern = r"readingArticle\(-\d+,\s*'[^']*',\s*'((?:\\.|[^'\\])*)'"
    bodies = re.findall(pattern, source)
    if len(bodies) < 4:
        raise ValueError('未能提取精选短文正文，停止生成')
    return [body.replace('\\n', '\n').replace("\\'", "'") for body in bodies]


def build(source: Path):
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise ValueError('ECDICT source SHA-256 does not match the project-pinned snapshot')
    catalog = json.loads((ROOT / 'entry/src/main/resources/rawfile/wordbooks/catalog.json').read_text())
    builtin = {word['word'].strip().lower() for book in catalog['books'] for word in book['words']}
    bodies = article_texts()
    article_tokens = {token for body in bodies for token in TOKEN.findall(body.lower())}
    selected = set(builtin) | article_tokens
    # First collect identities; retain only selected definitions on subsequent passes.
    # The full source has 770k rows and should not become an in-memory object graph.
    for row in csv.DictReader(source.open(encoding='utf-8-sig', newline='')):
        head = row['word'].strip().lower()
        if len(head) > 80 or not HEADWORD.fullmatch(head) or not CHINESE.search(row['translation']):
            continue
        ranks = [int(row[key]) for key in ('frq', 'bnc') if row[key].isdigit() and int(row[key]) > 0]
        if (ranks and min(ranks) <= 10000) or row.get('oxford') == '1':
            selected.add(head)
    records = {}
    pending = selected
    for _ in range(3):
        for row in csv.DictReader(source.open(encoding='utf-8-sig', newline='')):
            head = row['word'].strip().lower()
            if head not in pending or not HEADWORD.fullmatch(head) or not CHINESE.search(row['translation']):
                continue
            if head in records:
                previous = records[head]
                previous['translation'] += '\n' + row['translation']
                previous['exchange'] += '/' + row['exchange']
                previous['phonetic'] = previous['phonetic'] or row['phonetic']
            else:
                records[head] = row
        # Include roots referenced by surface forms, even if the lemma has no frequency tag.
        additions = {form for row in records.values() for kind, form in fields(row['exchange']) if kind == '0'}
        pending = additions - selected
        if not pending:
            break
        selected.update(pending)
    entries = []
    for head in sorted(selected & records.keys()):
        row = records[head]
        meaning = full_meaning(row['translation'])
        phonetic = row['phonetic'].strip().strip('/[]')
        entries.append({'word': head, 'phonetic': f'/{phonetic}/' if phonetic else '',
                        'meaning': meaning, 'exchange': row['exchange'].strip().lower()})
    pack = {'version': 1, 'sourceCommit': SOURCE_COMMIT, 'entries': entries}
    raw = (json.dumps(pack, ensure_ascii=False, separators=(',', ':')) + '\n').encode()
    if len(raw) > 10_000_000:
        raise ValueError('查询词典超过 10 MB 资源预算')
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(raw)
    known = {entry['word'] for entry in entries}
    aliases = {}
    for entry in entries:
        for kind, form in fields(entry['exchange']):
            if kind in {'p', 'd', 'i', '3', 'r', 't', 's'}:
                aliases.setdefault(form, set()).add(entry['word'])
            elif kind == '0' and form in known:
                aliases.setdefault(entry['word'], set()).add(form)
    unmatched = sorted(token for token in article_tokens if token not in known and token not in aliases)
    unresolved = [token for token in unmatched if not
                  (token.endswith("'s") and (token[:-2] in known or token[:-2] in aliases))]
    manifest = {
        'lookupVersion': 1, 'sourceRepository': 'https://github.com/skywind3000/ECDICT',
        'sourceCommit': SOURCE_COMMIT, 'sourceUrl': SOURCE_URL, 'sourceSha256': SOURCE_SHA256,
        'sourceLicense': 'MIT', 'sourceLicenseFile': 'entry/src/main/resources/rawfile/licenses/ECDICT-MIT.txt',
        'entries': len(entries), 'catalogHeads': len(builtin), 'articleCount': len(bodies),
        'articleTokenTypes': len(article_tokens), 'articleTokensWithoutExactOrExchangeMatch': unmatched,
        'articleTokensWithoutQueryCandidate': unresolved,
        'resourceBytes': len(raw), 'resourceSha256': hashlib.sha256(raw).hexdigest(),
        'selection': 'All existing learning-book heads, frequency rank <=10000 in either BNC/contemporary field, Oxford flag, curated article tokens and their known lemmas. No book membership is added.',
        'transform': 'Lowercase identities; preserve all nonempty Chinese definition lines and exchange fields; exclude non-Chinese, invalid or overlong heads. Query-only proper names remain explicit unmatched words, not invented definitions.',
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    build(parser.parse_args().source)
