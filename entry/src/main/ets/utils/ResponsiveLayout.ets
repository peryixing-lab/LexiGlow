/** Layout dimensions are viewport vp, never physical display pixels. */
export const PAGE_MAX_WIDTH: number = 1600;

/** Large-device primary navigation moves to the title row when it has enough room. */
export function usesTopNavigation(windowWidth: number, deviceType: string): boolean {
  return windowWidth >= 840 && (deviceType === 'tablet' || deviceType === '2in1');
}

export function primaryNavigationRailWidth(windowWidth: number, deviceType: string): number {
  return windowWidth >= 840 && !usesTopNavigation(windowWidth, deviceType) ? 104 : 0;
}

export function pageHorizontalPadding(width: number): number {
  return width >= 1200 ? 32 : width > 0 && width < 360 ? 16 : 24;
}

export function responsiveColumnCount(contentWidth: number, minimumCardWidth: number,
  maximumColumns: number, gap: number): number {
  return Math.max(1, Math.min(maximumColumns, Math.floor((contentWidth + gap) / (minimumCardWidth + gap))));
}

export function responsiveCardWidth(contentWidth: number, columns: number, gap: number): number {
  return Math.max(0, (contentWidth - (columns - 1) * gap) / columns);
}

/** Both word lists preserve readable cards as their windows shrink. */
export function wordListColumnCount(contentWidth: number, gap: number): number {
  return responsiveColumnCount(contentWidth, 320, 3, gap);
}
