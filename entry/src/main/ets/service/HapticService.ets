import { vibrator } from '@kit.SensorServiceKit';

/** Optional feedback: unsupported hardware never prevents a learning action. */
export class HapticService {
  static pulse(enabled: boolean, duration: number = 15): void {
    if (!enabled) { return; }
    try {
      vibrator.startVibration({ type: 'time', duration: duration }, { usage: 'touch' }).catch(() => {});
    } catch {}
  }

  static complete(enabled: boolean): void {
    if (!enabled) { return; }
    HapticService.pulse(true, 20);
    setTimeout(() => { HapticService.pulse(true, 15); }, 110);
  }
}
