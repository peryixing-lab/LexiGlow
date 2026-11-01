/** First/last letters remain visible; tiles represent every middle letter, including duplicates. */
export function spellingHint(word: string): string {
  return `${word.charAt(0)} ${Array.from(word.slice(1, -1)).map(() => '_').join(' ')} ${word.slice(-1)}`;
}

export function spellingMatches(word: string, answer: string): boolean {
  const value = answer.trim().toLowerCase();
  return value === word.toLowerCase() || value === word.slice(1, -1).toLowerCase();
}

/** Dictation requires the complete spelling; a middle-letter answer is never enough. */
export function dictationMatches(word: string, answer: string): boolean {
  return answer.trim().toLowerCase() === word.toLowerCase();
}

export function shuffledLetters(word: string): string[] {
  const letters = Array.from(word.slice(1, -1));
  for (let i = letters.length - 1; i > 0; i--) {
    const other = Math.floor(Math.random() * (i + 1));
    const value = letters[i];
    letters[i] = letters[other];
    letters[other] = value;
  }
  return letters;
}
