import { wantAgent } from '@kit.AbilityKit';
import { liveViewManager } from '@kit.LiveViewKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

// Enable only after Huawei approves the app's TIMER scenario and its signed Profile contains the entitlement.
// TIMER is restricted to tool apps. An educational app must obtain approval for its actual focus-timer use case.
const TIMER_ENTITLEMENT_APPROVED: boolean = false;

export class StudyLiveState {
  startedAt: number = 0;
  durationMs: number = 180000;
  completed: number = 0;
  total: number = 0;
  paused: boolean = false;
}

/** Real Live View lifecycle, disabled until its app entitlement is approved. Core learning stays offline. */
export class LiveStudyService {
  private static instance: LiveStudyService = new LiveStudyService();
  private id: number = 0;
  private sequence: number = 0;
  private active: boolean = false;
  private lastState: StudyLiveState = new StudyLiveState();
  private operations: Promise<void> = Promise.resolve();

  static getInstance(): LiveStudyService { return LiveStudyService.instance; }

  private async available(): Promise<boolean> {
    if (!TIMER_ENTITLEMENT_APPROVED || !canIUse('SystemCapability.LiveView.LiveViewService')) { return false; }
    return liveViewManager.isLiveViewEnabled();
  }

  private enqueue(operation: () => Promise<boolean>): Promise<boolean> {
    const result = this.operations.then(operation, operation);
    this.operations = result.then(() => {}, () => {});
    return result;
  }

  private async build(state: StudyLiveState, ended: boolean): Promise<liveViewManager.LiveView> {
    const duration = Math.max(15000, Math.min(28800000, state.durationMs));
    const remaining = Math.max(0, duration - Math.max(0, Date.now() - state.startedAt));
    const total = Math.max(0, Math.floor(state.total));
    const completed = Math.max(0, Math.min(total, Math.floor(state.completed)));
    const clickAction = await wantAgent.getWantAgent({
      wants: [{ bundleName: 'com.lovexjy.lexiglow', abilityName: 'EntryAbility', parameters: { route: 'quick' } }],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 2601,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    });
    return {
      id: this.id,
      event: 'TIMER',
      sequence: ++this.sequence,
      isMute: true,
      lifeCycleMode: liveViewManager.LifeCycleMode.AUTO_STOP_WHEN_APP_TERMINATE,
      timer: { time: remaining, isCountdown: true, isPaused: state.paused || ended },
      liveViewData: {
        primary: {
          title: ended ? '这束微光已点亮' : '词萤 · 3 分钟专注',
          content: [{ text: `${completed}/${total} 词 · ` }, { text: ended ? '学习已结束' : '${placeholder.timer}' }],
          keepTime: 0,
          clickAction: clickAction,
          aliveTime: Math.min(28800, Math.ceil(duration / 1000) + 30)
        },
        capsule: {
          type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER,
          status: ended ? -1 : 1,
          content: `${completed}/${total} 词`,
          backgroundColor: '#FF6E6130',
          time: remaining,
          isCountdown: true,
          isPaused: state.paused || ended
        }
      }
    };
  }

  start(state: StudyLiveState): Promise<boolean> {
    return this.enqueue(async (): Promise<boolean> => {
      if (this.active || state.startedAt <= 0 || !await this.available()) { return false; }
      this.id = Math.floor(Date.now() % 2147483647);
      this.sequence = 0;
      const result = await liveViewManager.startLiveView(await this.build(state, false));
      this.active = result.resultCode === 0;
      if (this.active) { this.lastState = state; }
      return this.active;
    }).catch((): boolean => {
      hilog.warn(0x0000, 'Ciying', 'Live study timer could not start');
      return false;
    });
  }

  update(state: StudyLiveState): Promise<boolean> {
    return this.enqueue(async (): Promise<boolean> => {
      if (!this.active || !await this.available()) { return false; }
      const result = await liveViewManager.updateLiveView(await this.build(state, false));
      if (result.resultCode === 0) { this.lastState = state; }
      return result.resultCode === 0;
    }).catch((): boolean => { return false; });
  }

  stop(): Promise<boolean> {
    return this.enqueue(async (): Promise<boolean> => {
      if (!this.active) { return false; }
      try {
        const result = await liveViewManager.stopLiveView(await this.build(this.lastState, true));
        return result.resultCode === 0;
      } finally {
        this.active = false;
      }
    }).catch((): boolean => { return false; });
  }
}
