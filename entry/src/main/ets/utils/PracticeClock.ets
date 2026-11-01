/** An elapsed-time clock: hidden pages and background time never consume a round. */
export class PracticeClock {
  private elapsed: number = 0;
  private runningAt: number = -1;

  reset(): void { this.elapsed = 0; this.runningAt = -1; }
  resume(now: number = Date.now()): void {
    if (this.runningAt < 0) { this.runningAt = now; }
  }
  pause(now: number = Date.now()): void {
    if (this.runningAt < 0) { return; }
    this.elapsed += Math.max(0, now - this.runningAt);
    this.runningAt = -1;
  }
  duration(now: number = Date.now()): number {
    return this.elapsed + (this.runningAt < 0 ? 0 : Math.max(0, now - this.runningAt));
  }
  remaining(seconds: number, now: number = Date.now()): number {
    return Math.max(0, seconds - Math.floor(this.duration(now) / 1000));
  }
}
