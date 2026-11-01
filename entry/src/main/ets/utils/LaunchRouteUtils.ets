export const TODAY_PLAN_DEEP_LINK: string = 'lexiglow://study/plan';

/** External links can open the plan only; existing internal Wants keep their route parameters. */
export function resolveLaunchRoute(uri: string, parameterRoute: string): string {
  if (uri.length > 0) {
    return uri === TODAY_PLAN_DEEP_LINK ? 'todayPlan' : '';
  }
  return parameterRoute;
}
