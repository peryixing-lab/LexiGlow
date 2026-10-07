import { DailyPlan } from '../model/AppModels';

/** The product plan includes both new-word learning and due review tasks. */
export function dailyPlanProgress(plan: DailyPlan): number {
  const total = plan.newTarget + plan.reviewTarget;
  return total > 0 ? Math.max(0, Math.min(100, (plan.newDone + plan.reviewDone) / total * 100)) : 100;
}

export function isDailyPlanComplete(plan: DailyPlan): boolean {
  return plan.newDone >= plan.newTarget && plan.reviewDone >= plan.reviewTarget;
}
