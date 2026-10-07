import { describe, it, expect } from '@ohos/hypium';
import { WordProgress, ReviewResult } from '../main/ets/model/AppModels';
import { adjustedNewTarget, baseIntervalMinutes, scheduleReview } from '../main/ets/service/ReviewScheduler';
import { dateKey, shiftedDate } from '../main/ets/utils/TimeUtils';

export default function localUnitTest() {
  describe('CiyingReviewScheduler', () => {
    it('firstAnswerIntervalsAreDifferent', 0, () => {
      const now = 1000000;
      const progress = new WordProgress();
      expect(scheduleReview(progress, ReviewResult.FORGET, now).nextReviewAt - now).assertEqual(600000);
      expect(scheduleReview(progress, ReviewResult.FUZZY, now).nextReviewAt - now).assertEqual(360000);
      expect(scheduleReview(progress, ReviewResult.KNOW, now).nextReviewAt - now).assertEqual(86400000);
    });
    it('forgettingReducesStrengthAndPreservesFlags', 0, () => {
      const progress = new WordProgress();
      progress.wordId = 42;
      progress.level = 5;
      progress.strength = 80;
      progress.favorite = true;
      progress.isNewWord = true;
      progress.reviewCount = 8;
      const next = scheduleReview(progress, ReviewResult.FORGET, 1000000);
      expect(next.level).assertEqual(4);
      expect(next.strength).assertEqual(60);
      expect(next.nextReviewAt - next.lastReviewAt).assertEqual(43200000);
      expect(next.reviewCount).assertEqual(9);
      expect(next.wrongCount).assertEqual(1);
      expect(next.favorite).assertTrue();
      expect(next.isNewWord).assertTrue();
      expect(progress.strength).assertEqual(80);
    });
    it('strengthAndIntervalAreBounded', 0, () => {
      const progress = new WordProgress();
      progress.level = 12;
      progress.strength = 98;
      expect(scheduleReview(progress, ReviewResult.KNOW, 0).strength).assertEqual(100);
      expect(baseIntervalMinutes(12)).assertEqual(86400);
      progress.level = 0;
      progress.strength = 5;
      expect(scheduleReview(progress, ReviewResult.FORGET, 0).strength).assertEqual(0);
      expect(scheduleReview(progress, ReviewResult.FORGET, 0).level).assertEqual(0);
    });
    it('backlogReducesAndPausesNewWords', 0, () => {
      expect(adjustedNewTarget(20, 60)).assertEqual(20);
      expect(adjustedNewTarget(20, 61)).assertEqual(6);
      expect(adjustedNewTarget(20, 100)).assertEqual(0);
    });
    it('calendarDatesRollover', 0, () => {
      const timestamp = new Date(2026, 9, 31, 23, 59, 59).getTime();
      expect(dateKey(timestamp)).assertEqual('2026-10-31');
      expect(shiftedDate(timestamp, 1)).assertEqual('2026-11-01');
    });
  });
}
