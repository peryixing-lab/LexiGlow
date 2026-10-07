export function dateKey(timestamp: number = Date.now()): string {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function pad(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

export function dayStart(timestamp: number = Date.now()): number {
  const date = new Date(timestamp);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

/** Calendar arithmetic keeps day boundaries correct across daylight-saving changes. */
export function shiftedDate(timestamp: number, dayOffset: number): string {
  const date = new Date(timestamp);
  date.setDate(date.getDate() + dayOffset);
  return dateKey(date.getTime());
}

export function weekStart(timestamp: number = Date.now()): number {
  const date = new Date(dayStart(timestamp));
  date.setDate(date.getDate() - ((date.getDay() + 6) % 7));
  return date.getTime();
}
