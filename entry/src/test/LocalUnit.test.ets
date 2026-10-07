import { describe, it, expect } from '@ohos/hypium';
import { DailyPlan, WordProgress, ReviewResult } from '../main/ets/model/AppModels';
import { adjustedNewTarget, baseIntervalMinutes, scheduleReview } from '../main/ets/service/ReviewScheduler';
import { dailyPlanProgress, isDailyPlanComplete } from '../main/ets/utils/DailyPlanUtils';
import { strengthAfterResult, strengthName } from '../main/ets/utils/MemoryUtils';
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
    it('firstAnswerUsesDocumentStrengthIncrements', 0, () => {
      const progress = new WordProgress();
      const forgotten = scheduleReview(progress, ReviewResult.FORGET, 1000000);
      const fuzzy = scheduleReview(progress, ReviewResult.FUZZY, 1000000);
      const known = scheduleReview(progress, ReviewResult.KNOW, 1000000);
      expect(forgotten.strength).assertEqual(0);
      expect(strengthName(forgotten.strength)).assertEqual('陌生');
      expect(fuzzy.strength).assertEqual(5);
      expect(strengthName(fuzzy.strength)).assertEqual('陌生');
      expect(known.strength).assertEqual(12);
      expect(strengthName(known.strength)).assertEqual('陌生');
      expect(progress.strength).assertEqual(0);
      expect(progress.reviewCount).assertEqual(0);
    });
    it('repeatedRecallBuildsMastery', 0, () => {
      let progress = new WordProgress();
      for (let count = 1; count <= 5; count++) {
        progress = scheduleReview(progress, ReviewResult.KNOW, 1000000);
        expect(progress.strength).assertEqual(count * 12);
      }
      expect(progress.strength).assertEqual(60);
      expect(strengthName(progress.strength)).assertEqual('熟悉');
      progress = scheduleReview(progress, ReviewResult.KNOW, 1000000);
      expect(progress.strength).assertEqual(72);
      expect(strengthName(progress.strength)).assertEqual('熟悉');
      progress = scheduleReview(progress, ReviewResult.KNOW, 1000000);
      expect(progress.strength).assertEqual(84);
      expect(strengthName(progress.strength)).assertEqual('掌握');
    });
    it('strengthLabelsUseDocumentBoundaries', 0, () => {
      expect(strengthName(0)).assertEqual('陌生');
      expect(strengthName(24)).assertEqual('陌生');
      expect(strengthName(25)).assertEqual('模糊');
      expect(strengthName(49)).assertEqual('模糊');
      expect(strengthName(50)).assertEqual('熟悉');
      expect(strengthName(74)).assertEqual('熟悉');
      expect(strengthName(75)).assertEqual('掌握');
      expect(strengthName(100)).assertEqual('掌握');
    });
    it('allJudgementsUseDocumentStrengthBounds', 0, () => {
      expect(strengthAfterResult(0, ReviewResult.FUZZY)).assertEqual(5);
      expect(strengthAfterResult(24, ReviewResult.FUZZY)).assertEqual(29);
      expect(strengthAfterResult(98, ReviewResult.FUZZY)).assertEqual(100);
      expect(strengthAfterResult(0, ReviewResult.KNOW)).assertEqual(12);
      expect(strengthAfterResult(90, ReviewResult.KNOW)).assertEqual(100);
      expect(strengthAfterResult(20, ReviewResult.FORGET)).assertEqual(0);
      expect(strengthAfterResult(0, ReviewResult.FORGET)).assertEqual(0);
    });
    it('judgementsUpdateLevelAndIntervalAsDocumented', 0, () => {
      const now = 1000000;
      const progress = new WordProgress();
      progress.level = 2;
      const fuzzy = scheduleReview(progress, ReviewResult.FUZZY, now);
      expect(fuzzy.level).assertEqual(2);
      expect(fuzzy.nextReviewAt - now).assertEqual(2592 * 60000);
      const known = scheduleReview(progress, ReviewResult.KNOW, now);
      expect(known.level).assertEqual(3);
      expect(known.nextReviewAt - now).assertEqual(10080 * 60000);
      const forgotten = scheduleReview(progress, ReviewResult.FORGET, now);
      expect(forgotten.level).assertEqual(1);
      expect(forgotten.nextReviewAt - now).assertEqual(720 * 60000);
      progress.level = 1;
      const forgottenToZero = scheduleReview(progress, ReviewResult.FORGET, now);
      expect(forgottenToZero.level).assertEqual(0);
      expect(forgottenToZero.nextReviewAt - now).assertEqual(10 * 60000);
      expect(baseIntervalMinutes(0)).assertEqual(10);
      expect(baseIntervalMinutes(1)).assertEqual(1440);
      expect(baseIntervalMinutes(2)).assertEqual(4320);
      expect(baseIntervalMinutes(3)).assertEqual(10080);
      expect(baseIntervalMinutes(4)).assertEqual(20160);
      expect(baseIntervalMinutes(5)).assertEqual(43200);
      expect(baseIntervalMinutes(6)).assertEqual(86400);
      expect(baseIntervalMinutes(7)).assertEqual(86400);
    });
    it('dailyProgressIncludesNewAndReviewButEachGoalMustBeMet', 0, () => {
      const plan = new DailyPlan();
      plan.newTarget = 20;
      plan.newDone = 10;
      plan.reviewTarget = 2;
      plan.reviewDone = 1;
      expect(dailyPlanProgress(plan)).assertEqual(50);
      expect(isDailyPlanComplete(plan)).assertFalse();
      plan.newDone = 20;
      plan.reviewDone = 0;
      expect(dailyPlanProgress(plan)).assertEqual(20 / 22 * 100);
      expect(isDailyPlanComplete(plan)).assertFalse();
      plan.reviewDone = 2;
      expect(dailyPlanProgress(plan)).assertEqual(100);
      expect(isDailyPlanComplete(plan)).assertTrue();
      plan.newDone = 25;
      plan.reviewDone = 0;
      expect(dailyPlanProgress(plan)).assertEqual(100);
      expect(isDailyPlanComplete(plan)).assertFalse();
      plan.newDone = -1;
      expect(dailyPlanProgress(plan)).assertEqual(0);
      plan.newTarget = 0;
      plan.newDone = 0;
      plan.reviewDone = 0;
      plan.reviewTarget = 0;
      expect(dailyPlanProgress(plan)).assertEqual(100);
      expect(isDailyPlanComplete(plan)).assertTrue();
      plan.reviewTarget = 2;
      expect(dailyPlanProgress(plan)).assertEqual(0);
      expect(isDailyPlanComplete(plan)).assertFalse();
      plan.reviewDone = 2;
      expect(dailyPlanProgress(plan)).assertEqual(100);
      expect(isDailyPlanComplete(plan)).assertTrue();
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
