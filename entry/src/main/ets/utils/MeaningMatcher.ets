/** Match complete dictionary senses locally; a fragment of a sense is never an answer. */
function stripAnnotations(value: string): string {
  // Short text inserted inside a word completes that word: 求(婚), 不动(产), 洞察(力).
  let cleaned = value.replace(/([\u3400-\u9FFF])\(([\u3400-\u9FFF]{1,2})\)/g, '$1$2')
    .replace(/([\u3400-\u9FFF])（([\u3400-\u9FFF]{1,2})）/g, '$1$2');
  // Labels can contain separators, so remove them before splitting senses.
  cleaned = cleaned.replace(/\([^()]*\)|（[^（）]*）|\[[^\[\]]*\]|【[^【】]*】|<[^<>]*>/g, '');
  return cleaned;
}

function senseParts(value: string): string[] {
  // Keep optional causative wording as a full sense rather than a substring rule.
  const causative = value.replace(/\(使\)|（使）/g, '使');
  const stripped = stripAnnotations(value);
  const sources: string[] = causative !== value ? [stripped, stripAnnotations(causative)] : [stripped];
  const parts: string[] = [];
  for (const source of sources) {
    // A word can have several parts of speech even without a semicolon between them.
    const separated = source.replace(/\b(?:n|v|vt|vi|a|adj|adv|prep|pron|conj|interj|int|aux|num|det|art|abbr)\s*\./gi, ';')
      .replace(/(?:名词|动词|形容词|副词|介词|代词|连词|数词|感叹词)\s*[:：]/g, ';');
    for (const part of separated.split(/[,，;；、\n\r\/|]+/)) {
      const cleaned = part.trim().replace(/^(?:[0-9]+[.．)）:：]|[①-⑳]|[一二三四五六七八九十]+[、.．])\s*/g, '')
        .replace(/\s+/g, '').replace(/^[：:。.!！?？“”‘’"'\-]+|[：:。.!！?？“”‘’"'\-]+$/g, '');
      if (/[\u3400-\u9FFF]/.test(cleaned) && parts.indexOf(cleaned) < 0) {
        parts.push(cleaned);
      }
    }
  }
  return parts;
}

function comparisonKey(value: string): string {
  // Ellipses are dictionary object placeholders, not a request to match arbitrary text.
  return value.replace(/\.{2,}|…+|⋯+/g, '')
    .replace(/[\s.．。!！?？:：“”‘’"'\-()（）\[\]【】]/g, '');
}

function appendAdjectiveAliases(segment: string, keys: string[]): void {
  for (const sense of senseParts(segment)) {
    const key = comparisonKey(sense);
    if (key.length > 1 && key.endsWith('的')) {
      const alias = key.slice(0, key.length - 1);
      if (keys.indexOf(alias) < 0) {
        keys.push(alias);
      }
    }
  }
}

function appendDictionaryAliases(meaning: string, keys: string[]): void {
  const source = stripAnnotations(meaning).replace(/形容词\s*[:：]/g, 'adj.')
    .replace(/(?:名词|动词|副词|介词|代词|连词|数词|感叹词)\s*[:：]/g, 'n.');
  const partsOfSpeech = /\b(n|v|vt|vi|a|adj|adv|prep|pron|conj|interj|int|aux|num|det|art|abbr)\s*\./gi;
  let previousType = '';
  let segmentStart = 0;
  let match = partsOfSpeech.exec(source);
  while (match) {
    if (previousType === 'a' || previousType === 'adj') {
      appendAdjectiveAliases(source.slice(segmentStart, match.index), keys);
    }
    previousType = match[1].toLowerCase();
    segmentStart = partsOfSpeech.lastIndex;
    match = partsOfSpeech.exec(source);
  }
  if (previousType === 'a' || previousType === 'adj') {
    appendAdjectiveAliases(source.slice(segmentStart), keys);
  }
}

/** Chinese senses suitable for showing after the user has submitted an answer. */
export function meaningAnswers(meaning: string): string[] {
  return senseParts(meaning);
}

/** One complete, normalized Chinese sense is enough, including one of several entered senses. */
export function matchesMeaning(answer: string, meaning: string): boolean {
  if (answer.trim().length === 0) {
    return false;
  }
  const expected: string[] = meaningAnswers(meaning).map((value: string) => comparisonKey(value));
  // Only dictionary adjectives get this alias: 好的 → 好, while the noun 目的 stays 目的.
  appendDictionaryAliases(meaning, expected);
  for (const candidate of senseParts(answer)) {
    const key = comparisonKey(candidate);
    if (key.length > 0 && expected.indexOf(key) >= 0) {
      return true;
    }
  }
  return false;
}
