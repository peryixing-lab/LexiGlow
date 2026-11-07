export const TODAY_PLAN_DEEP_LINK: string = 'lexiglow://study/plan';
export const MISTAKES_DEEP_LINK: string = 'lexiglow://study/mistakes';
export const SENTENCES_DEEP_LINK: string = 'lexiglow://study/sentences';

export class LaunchUriTarget {
  route: string = '';
  wordId: number = 0;
  articleId: number = 0;
  spelling: string = '';
}

export function parseLaunchUri(uri: string): LaunchUriTarget {
  const target = new LaunchUriTarget();
  if (!uri || /[\s\u0000-\u001f]/.test(uri)) { return target; }
  if (uri === TODAY_PLAN_DEEP_LINK) { target.route = 'todayPlan'; return target; }
  if (uri === MISTAKES_DEEP_LINK) { target.route = 'mistakes'; return target; }
  if (uri === SENTENCES_DEEP_LINK) { target.route = 'sentences'; return target; }
  const wordIdMatch = /^lexiglow:\/\/word\?id=([1-9]\d{0,9})$/.exec(uri);
  if (wordIdMatch) {
    target.route = 'word';
    target.wordId = Number(wordIdMatch[1]);
    return target;
  }
  const wordSpellingMatch = /^lexiglow:\/\/word\?spelling=([A-Za-z0-9%'’-]{1,128})$/.exec(uri);
  if (wordSpellingMatch) {
    let decoded = wordSpellingMatch[1];
    try {
      decoded = decodeURIComponent(decoded);
    } catch (_) {
      return target;
    }
    const normalized = decoded.trim().toLowerCase().replace(/’/g, "'");
    if (/^[a-z][a-z'-]{0,63}$/.test(normalized)) {
      target.route = 'lookupWord';
      target.spelling = normalized;
    }
    return target;
  }
  const articleMatch = /^lexiglow:\/\/article\?id=(-?[1-9]\d{0,9})$/.exec(uri);
  if (articleMatch) {
    target.route = 'article';
    target.articleId = Number(articleMatch[1]);
    return target;
  }
  return target;
}

/** External links can open supported destinations; existing internal Wants keep their route parameters. */
export function resolveLaunchRoute(uri: string, parameterRoute: string): string {
  if (uri.length > 0) {
    return parseLaunchUri(uri).route;
  }
  return parameterRoute;
}
