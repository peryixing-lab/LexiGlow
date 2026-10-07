import { ReviewResult } from '../model/AppModels';

/** Fixed strength increments from the product plan; labels reflect accumulated recall. */
export function strengthAfterResult(previousStrength: number, result: ReviewResult): number {
  if (result === ReviewResult.FORGET) {
    return Math.max(0, previousStrength - 20);
  }
  if (result === ReviewResult.FUZZY) {
    return Math.min(100, previousStrength + 5);
  }
  if (result === ReviewResult.KNOW) {
    return Math.min(100, previousStrength + 12);
  }
  throw new Error('无效的记忆判断');
}

export function strengthName(strength: number): string {
  return strength >= 75 ? '掌握' : strength >= 50 ? '熟悉' : strength >= 25 ? '模糊' : '陌生';
}
