import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { notificationManager } from '@kit.NotificationKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UserSettings } from '../model/AppModels';

/**
 * 代理提醒，严格按官方文档《代理提醒(ArkTS)》实现：
 * 1. 申请权限 ohos.permission.PUBLISH_AGENT_REMINDER（module.json5 已声明）
 * 2. 运行时请求通知授权（notificationManager.requestEnableNotification）
 * 3. publishReminder / cancelReminder / getAllValidReminders
 * 每日提醒 = 官方周期日历实例，以排除日期跳过已完成任务的当天。
 */

export class ReminderStatus {
  notificationEnabled: boolean = false;
  dailyReminderId: number = -1;
  dailySkippedToday: boolean = false;
}

export class ReminderError extends Error {
  code: number;

  constructor(operation: string, cause: BusinessError) {
    const code = typeof cause.code === 'number' ? cause.code : 0;
    let reason = '系统操作失败，请稍后重试';
    if (code === 201) {
      reason = '代理提醒权限校验未通过，请确认已声明 PUBLISH_AGENT_REMINDER 权限';
    } else if (code === 401) {
      reason = '提醒参数无效';
    } else if (code === 1700001 || code === 1600004) {
      reason = '通知尚未开启，请在系统设置中允许词萤通知';
    } else if (code === 1700002) {
      reason = '系统未允许登记提醒，可能是提醒数量已达上限，或当前设备的代理提醒能力校验未通过';
    } else if (code === 1700003) {
      reason = '提醒已不存在';
    } else if (code === 1700004) {
      reason = '应用包名未被系统识别，请重新安装';
    } else if (code === 1600003) {
      reason = '无法连接系统通知服务，请稍后重试';
    } else if (code === 1600013) {
      reason = '通知授权窗口已打开，请先完成授权';
    } else if (code === 801) {
      reason = '当前设备不支持代理提醒';
    }
    super(operation + '：' + reason + (code !== 0 ? '（错误码 ' + code + '）' : ''));
    this.code = code;
  }
}

class DailyReminderState {
  info: reminderAgentManager.ReminderInfo;
  excludes: Date[] = [];

  constructor(info: reminderAgentManager.ReminderInfo) {
    this.info = info;
  }
}

export class ReminderService {
  private static readonly DOMAIN: number = 0x0001;
  private static readonly DAILY_CONTENT: string = '今天的任务还没完成哦，赶紧来学习吧';
  private static operationQueue: Promise<void> = Promise.resolve();

  private static exclusive<T>(operation: () => Promise<T>): Promise<T> {
    const result = ReminderService.operationQueue.then(operation);
    ReminderService.operationQueue = result.then(() => {}, () => {});
    return result;
  }

  private static readonly DAILY_NOTIFICATION_ID: number = 1024;
  private static readonly TEST_NOTIFICATION_ID: number = 1025;
  private static readonly TEST_GROUP_ID: string = 'lexiglow_test';
  private static readonly TEST_TITLE: string = '词萤 · 提醒测试';
  /** daysOfWeek 取值 1–7 对应周一至周日，全部选中表示每天提醒。 */
  private static readonly EVERY_DAY: number[] = [1, 2, 3, 4, 5, 6, 7];

  /** 官方步骤 2：请求通知授权。仅在用户主动开启提醒时调用。 */
  private static async ensureNotificationEnabled(context: common.UIAbilityContext): Promise<void> {
    let enabled = false;
    try {
      enabled = await notificationManager.isNotificationEnabled();
    } catch (error) {
      throw new ReminderError('无法查询通知授权', error as BusinessError);
    }
    if (enabled) {
      return;
    }
    try {
      await notificationManager.requestEnableNotification(context);
    } catch (error) {
      throw new ReminderError('通知授权未能完成', error as BusinessError);
    }
    try {
      enabled = await notificationManager.isNotificationEnabled();
    } catch (error) {
      throw new ReminderError('无法查询通知授权', error as BusinessError);
    }
    if (!enabled) {
      throw new ReminderError('通知未开启', { code: 1700001, name: 'BusinessError', message: 'Notification disabled' });
    }
  }

  /** 官方接口：publishReminder。返回提醒 ID，供 cancelReminder 使用。 */
  private static async publishReminderRequest(operation: string,
    reminder: reminderAgentManager.ReminderRequest): Promise<number> {
    try {
      const reminderId = await reminderAgentManager.publishReminder(reminder);
      hilog.info(ReminderService.DOMAIN, 'LexiGlowReminder', 'published id=%{public}d type=%{public}d',
        reminderId, reminder.reminderType);
      return reminderId;
    } catch (error) {
      const err = error as BusinessError;
      hilog.warn(ReminderService.DOMAIN, 'LexiGlowReminder', '%{public}s code=%{public}d', operation, err.code);
      throw new ReminderError(operation, err);
    }
  }

  /** 官方接口：cancelReminder。提醒本身不存在（1700003）时视为已取消。 */
  private static async cancelReminderQuietly(reminderId: number): Promise<void> {
    if (reminderId < 0) {
      return;
    }
    try {
      await reminderAgentManager.cancelReminder(reminderId);
      hilog.info(ReminderService.DOMAIN, 'LexiGlowReminder', 'canceled id=%{public}d', reminderId);
    } catch (error) {
      const err = error as BusinessError;
      if (err.code !== 1700003) {
        throw new ReminderError('提醒未能取消', err);
      }
    }
  }

  /** 官方接口：getAllValidReminders，查询当前应用的所有有效提醒。 */
  private static async validReminders(): Promise<Array<reminderAgentManager.ReminderInfo>> {
    try {
      return await reminderAgentManager.getAllValidReminders();
    } catch (error) {
      throw new ReminderError('无法查询系统提醒', error as BusinessError);
    }
  }

  /** 只清除已送达的每日通知，保留系统登记的循环；label 必须与系统返回记录一致。 */
  private static async removeDeliveredDaily(): Promise<void> {
    try {
      const active = await notificationManager.getActiveNotifications();
      for (const notification of active) {
        if (notification.id === ReminderService.DAILY_NOTIFICATION_ID) {
          try {
            await notificationManager.cancel(ReminderService.DAILY_NOTIFICATION_ID, notification.label);
          } catch (error) {
            if ((error as BusinessError).code !== 1600007) {
              throw error as Error;
            }
          }
        }
      }
    } catch (error) {
      throw new ReminderError('每日提醒通知未能清除', error as BusinessError);
    }
  }

  private static async readId(store: preferences.Preferences, key: string): Promise<number> {
    return await store.get(key, -1) as number;
  }

  private static async saveId(store: preferences.Preferences, key: string, reminderId: number): Promise<void> {
    await store.put(key, reminderId);
    await store.flush();
  }

  private static isDaily(info: reminderAgentManager.ReminderInfo): boolean {
    return info.reminderReq.notificationId === ReminderService.DAILY_NOTIFICATION_ID &&
      info.reminderReq.groupId !== ReminderService.TEST_GROUP_ID &&
      (info.reminderReq.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR ||
        info.reminderReq.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM);
  }

  private static validateProgress(hour: number, minute: number, todayNewCount: number, dailyTarget: number): void {
    if (!Number.isInteger(hour) || hour < 0 || hour > 23 || !Number.isInteger(minute) || minute < 0 || minute > 59) {
      throw new Error('请选择有效的提醒时间');
    }
    if (!Number.isInteger(todayNewCount) || todayNewCount < 0 || !Number.isInteger(dailyTarget) || dailyTarget < 1 || dailyTarget > 100) {
      throw new Error('学习进度或每日目标无效');
    }
  }

  private static localDay(date: Date): Date {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
  }

  private static sameDay(left: Date, right: Date): boolean {
    return left.getFullYear() === right.getFullYear() && left.getMonth() === right.getMonth() &&
      left.getDate() === right.getDate();
  }

  /** 永远使用未来时刻，过了今日提醒时间时从明天开始，不补发已过期任务。 */
  private static nextTime(hour: number, minute: number, now: Date): reminderAgentManager.LocalDateTime {
    const next = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, minute, 0, 0);
    if (next.getTime() <= now.getTime()) {
      next.setDate(next.getDate() + 1);
    }
    return { year: next.getFullYear(), month: next.getMonth() + 1, day: next.getDate(),
      hour: hour, minute: minute, second: 0 };
  }

  private static calendar(context: common.UIAbilityContext, hour: number, minute: number,
    now: Date): reminderAgentManager.ReminderRequestCalendar {
    return {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: ReminderService.nextTime(hour, minute, now),
      daysOfWeek: ReminderService.EVERY_DAY,
      actionButton: [{ title: '关闭', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }],
      wantAgent: { pkgName: context.abilityInfo.bundleName, abilityName: 'EntryAbility', parameters: { 'route': 'today' } },
      ringDuration: 0,
      snoozeTimes: 0,
      timeInterval: 0,
      title: '词萤 · 每天一点光',
      content: ReminderService.DAILY_CONTENT,
      expiredContent: ReminderService.DAILY_CONTENT,
      notificationId: ReminderService.DAILY_NOTIFICATION_ID,
      groupId: 'lexiglow_daily',
      slotType: notificationManager.SlotType.SERVICE_INFORMATION
    };
  }

  private static matchesCalendar(info: reminderAgentManager.ReminderInfo, hour: number, minute: number): boolean {
    if (info.reminderReq.reminderType !== reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR) {
      return false;
    }
    const calendar = info.reminderReq as reminderAgentManager.ReminderRequestCalendar;
    return calendar.dateTime.hour === hour && calendar.dateTime.minute === minute &&
      calendar.content === ReminderService.DAILY_CONTENT && calendar.expiredContent === ReminderService.DAILY_CONTENT &&
      calendar.daysOfWeek !== undefined && calendar.daysOfWeek.length === 7 &&
      ReminderService.EVERY_DAY.every((day: number) => calendar.daysOfWeek!.indexOf(day) >= 0);
  }

  private static async excludeDates(reminderId: number): Promise<Date[]> {
    try {
      return await reminderAgentManager.getExcludeDates(reminderId);
    } catch (error) {
      throw new ReminderError('无法查询当天提醒状态', error as BusinessError);
    }
  }

  private static async restoreExcludes(reminderId: number, dates: Date[]): Promise<void> {
    try {
      await reminderAgentManager.deleteExcludeDates(reminderId);
      for (const date of dates) {
        await reminderAgentManager.addExcludeDate(reminderId, date);
      }
    } catch (error) {
      throw new ReminderError('当天提醒状态未能同步', error as BusinessError);
    }
  }

  /** 只保留今天的排除日期，未来每天仍提醒；已过时间也不在恢复目标时补发。 */
  private static async syncExcludes(reminderId: number, existing: Date[], skipToday: boolean, now: Date): Promise<void> {
    if ((skipToday && existing.length === 1 && ReminderService.sameDay(existing[0], now)) ||
      (!skipToday && existing.length === 0)) {
      return;
    }
    try {
      if (existing.length > 0) {
        await reminderAgentManager.deleteExcludeDates(reminderId);
      }
      if (skipToday) {
        await reminderAgentManager.addExcludeDate(reminderId, ReminderService.localDay(now));
      }
    } catch (error) {
      throw new ReminderError('当天提醒状态未能同步', error as BusinessError);
    }
  }

  private static async snapshotDaily(store: preferences.Preferences): Promise<DailyReminderState | undefined> {
    const storedId = await ReminderService.readId(store, 'reminderId');
    const valid = (await ReminderService.validReminders()).filter(ReminderService.isDaily);
    const info = valid.find((item: reminderAgentManager.ReminderInfo) => item.reminderId === storedId) || valid[0];
    if (!info) {
      return undefined;
    }
    const state = new DailyReminderState(info);
    if (info.reminderReq.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR) {
      state.excludes = await ReminderService.excludeDates(info.reminderId);
    }
    return state;
  }

  private static async cancelLiveDaily(reminderId: number): Promise<void> {
    const live = (await ReminderService.validReminders()).find((item: reminderAgentManager.ReminderInfo) =>
      item.reminderId === reminderId && ReminderService.isDaily(item));
    if (live) {
      await ReminderService.cancelReminderQuietly(live.reminderId);
    }
  }

  private static async restoreDaily(store: preferences.Preferences, previous: DailyReminderState | undefined): Promise<void> {
    if (!previous) {
      await ReminderService.saveId(store, 'reminderId', -1);
      return;
    }
    const live = (await ReminderService.validReminders()).find((item: reminderAgentManager.ReminderInfo) =>
      item.reminderId === previous.info.reminderId && ReminderService.isDaily(item));
    let restoredId = previous.info.reminderId;
    if (!live) {
      let request = previous.info.reminderReq;
      if (request.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR) {
        const calendar = request as reminderAgentManager.ReminderRequestCalendar;
        const copy = JSON.parse(JSON.stringify(calendar)) as reminderAgentManager.ReminderRequestCalendar;
        copy.dateTime = ReminderService.nextTime(calendar.dateTime.hour, calendar.dateTime.minute, new Date());
        request = copy;
      }
      restoredId = await ReminderService.publishReminderRequest('原提醒未能恢复', request);
    }
    if (previous.info.reminderReq.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR) {
      await ReminderService.restoreExcludes(restoredId, previous.excludes);
    }
    await ReminderService.saveId(store, 'reminderId', restoredId);
  }

  private static async rollback(store: preferences.Preferences, previous: DailyReminderState | undefined,
    createdId: number, error: BusinessError): Promise<never> {
    try {
      if (createdId >= 0) {
        await ReminderService.cancelLiveDaily(createdId);
      }
      await ReminderService.restoreDaily(store, previous);
    } catch (restoreError) {
      throw new ReminderError('提醒更新失败；恢复原提醒也失败：' + (restoreError as Error).message, error);
    }
    throw new ReminderError('提醒更新失败，已恢复原提醒', error);
  }

  private static async updateDaily(context: common.UIAbilityContext, enabled: boolean, hour: number, minute: number,
    todayNewCount: number, dailyTarget: number, allowAuthorization: boolean, progressDate: Date): Promise<void> {
    if (!enabled && !allowAuthorization) {
      // 关闭操作只由显式 configure 执行，避免旧刷新快照在开启过程中取消新登记。
      return;
    }
    if (enabled) {
      ReminderService.validateProgress(hour, minute, todayNewCount, dailyTarget);
      if (allowAuthorization) {
        await ReminderService.ensureNotificationEnabled(context);
      } else {
        let notificationEnabled: boolean;
        try {
          notificationEnabled = await notificationManager.isNotificationEnabled();
        } catch (error) {
          throw new ReminderError('无法查询通知授权', error as BusinessError);
        }
        if (!notificationEnabled) {
          return;
        }
      }
    }
    const store = await preferences.getPreferences(context, { name: 'lexiglow_reminders' });
    const previous = await ReminderService.snapshotDaily(store);
    if (!enabled) {
      try {
        const valid = (await ReminderService.validReminders()).filter(ReminderService.isDaily);
        for (const info of valid) {
          await ReminderService.cancelLiveDaily(info.reminderId);
        }
        await ReminderService.removeDeliveredDaily();
        await ReminderService.saveId(store, 'reminderId', -1);
      } catch (error) {
        await ReminderService.rollback(store, previous, -1, error as BusinessError);
      }
      return;
    }
    const now = new Date();
    // 授权或前一项系统操作可能跨过午夜，昨日的完成量不能排除新一天。
    const currentNewCount = ReminderService.sameDay(progressDate, now) ? todayNewCount : 0;
    const complete = currentNewCount >= dailyTarget;
    const todayTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour, minute, 0, 0);
    const timePassed = todayTime.getTime() <= now.getTime();
    if (previous && ReminderService.matchesCalendar(previous.info, hour, minute)) {
      // 到点后保留系统已经登记的未完成提醒，避免刷新抢在投递前排除今天。
      // 当天因完成任务已经排除时，过时提高目标也不补发。
      const skipToday = complete || (timePassed && previous.excludes.some((date: Date) =>
        ReminderService.sameDay(date, now)));
      try {
        await ReminderService.syncExcludes(previous.info.reminderId, previous.excludes, skipToday, now);
        if (complete) {
          await ReminderService.removeDeliveredDaily();
        }
        if (await ReminderService.readId(store, 'reminderId') !== previous.info.reminderId) {
          await ReminderService.saveId(store, 'reminderId', previous.info.reminderId);
        }
        hilog.info(ReminderService.DOMAIN, 'LexiGlowReminder',
          'progress synced id=%{public}d newCount=%{public}d target=%{public}d skipToday=%{public}s migrated=false',
          previous.info.reminderId, currentNewCount, dailyTarget, String(skipToday));
      } catch (error) {
        await ReminderService.rollback(store, previous, -1, error as BusinessError);
      }
      return;
    }
    let createdId = -1;
    try {
      createdId = await ReminderService.publishReminderRequest('每日提醒未能发布', ReminderService.calendar(context, hour, minute, now));
      const skipToday = complete || timePassed;
      await ReminderService.syncExcludes(createdId, [], skipToday, now);
      await ReminderService.saveId(store, 'reminderId', createdId);
      // 原生发布创建独立实例；确认新登记已持久化后，显式取消仍属于每日提醒的旧 ID。
      if (previous && previous.info.reminderId !== createdId) {
        await ReminderService.cancelLiveDaily(previous.info.reminderId);
      }
      if (complete) {
        await ReminderService.removeDeliveredDaily();
      }
      hilog.info(ReminderService.DOMAIN, 'LexiGlowReminder',
        'progress synced id=%{public}d newCount=%{public}d target=%{public}d skipToday=%{public}s migrated=%{public}s',
        createdId, currentNewCount, dailyTarget, String(skipToday),
        String(previous !== undefined && previous.info.reminderReq.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_ALARM));
    } catch (error) {
      if (createdId < 0) {
        throw error as Error;
      }
      await ReminderService.rollback(store, previous, createdId, error as BusinessError);
    }
  }

  /** 用户主动设置时才允许弹出通知授权，注册任务条件为“今日新词未达到自定义目标”。 */
  static async configure(context: common.UIAbilityContext, enabled: boolean, hour: number, minute: number,
    todayNewCount: number = 0, dailyTarget: number = 20): Promise<void> {
    const progressDate = new Date();
    return ReminderService.exclusive(() => ReminderService.updateDaily(context, enabled, hour, minute,
      todayNewCount, dailyTarget, true, progressDate));
  }

  /** 学习保存、目标变化、启动或恢复前台后的被动同步；不弹权限窗。 */
  static async syncDailyProgress(context: common.UIAbilityContext, settings: UserSettings, todayNewCount: number): Promise<void> {
    // 复制参数，避免排队期间可变 UI 设置被后续操作覆盖。
    const enabled = settings.reminderEnabled;
    const hour = settings.reminderHour;
    const minute = settings.reminderMinute;
    const target = settings.dailyNewTarget;
    const progressDate = new Date();
    return ReminderService.exclusive(() => ReminderService.updateDaily(context, enabled, hour, minute,
      todayNewCount, target, false, progressDate));
  }

  /** 历史测试入口已移除。只依据系统有效记录的测试标识识别，不信任可能已复用的本地 ID。 */
  private static isLegacyTest(reminder: reminderAgentManager.ReminderInfo): boolean {
    const request = reminder.reminderReq;
    return request.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER &&
      request.notificationId !== ReminderService.DAILY_NOTIFICATION_ID && request.groupId !== 'lexiglow_daily' &&
      (request.notificationId === ReminderService.TEST_NOTIFICATION_ID || request.groupId === ReminderService.TEST_GROUP_ID);
  }

  /** 升级启动时清理历史测试，既不请求通知授权，也不重新登记或取消每日提醒。可重复调用。 */
  static async cleanupLegacyTests(context: common.UIAbilityContext): Promise<void> {
    return ReminderService.exclusive(() => ReminderService.cleanupLegacyTestsInternal(context));
  }

  private static async cleanupLegacyTestsInternal(context: common.UIAbilityContext): Promise<void> {
    const valid = await ReminderService.validReminders();
    for (const candidate of valid) {
      if (!ReminderService.isLegacyTest(candidate)) {
        continue;
      }
      // 逐条重新查询，避免上一轮已删除的测试 ID 被系统重新分配后误取消其他记录。
      const current = (await ReminderService.validReminders()).find((item: reminderAgentManager.ReminderInfo) =>
        item.reminderId === candidate.reminderId && ReminderService.isLegacyTest(item));
      if (current !== undefined) {
        await ReminderService.cancelReminderQuietly(current.reminderId);
      }
    }
    let active: Array<notificationManager.NotificationRequest>;
    try {
      active = await notificationManager.getActiveNotifications();
    } catch (error) {
      throw new ReminderError('无法查询历史测试通知', error as BusinessError);
    }
    for (const notification of active) {
      const testTitle = notification.content.normal?.title === ReminderService.TEST_TITLE;
      if (notification.id !== ReminderService.TEST_NOTIFICATION_ID ||
        (!testTitle && notification.groupName !== ReminderService.TEST_GROUP_ID)) {
        continue;
      }
      try {
        await notificationManager.cancel(ReminderService.TEST_NOTIFICATION_ID, notification.label);
      } catch (error) {
        const err = error as BusinessError;
        if (err.code !== 1600007) {
          throw new ReminderError('历史测试通知未能清除', err);
        }
      }
    }
    const store = await preferences.getPreferences(context, { name: 'lexiglow_reminders' });
    await ReminderService.saveId(store, 'testReminderId', -1);
    hilog.info(ReminderService.DOMAIN, 'LexiGlowReminder', 'legacy test cleanup completed');
  }

  /** 读取通知授权与提醒登记状态，仅调用查询接口。 */
  static async status(context: common.UIAbilityContext): Promise<ReminderStatus> {
    return ReminderService.exclusive(() => ReminderService.statusInternal(context));
  }

  private static async statusInternal(context: common.UIAbilityContext): Promise<ReminderStatus> {
    const store = await preferences.getPreferences(context, { name: 'lexiglow_reminders' });
    const dailyId = await ReminderService.readId(store, 'reminderId');
    const valid = await ReminderService.validReminders();
    const status = new ReminderStatus();
    try {
      status.notificationEnabled = await notificationManager.isNotificationEnabled();
    } catch (error) {
      throw new ReminderError('无法查询通知授权', error as BusinessError);
    }
    const daily = valid.find((item: reminderAgentManager.ReminderInfo) =>
      item.reminderId === dailyId && ReminderService.isDaily(item)) || valid.find(ReminderService.isDaily);
    status.dailyReminderId = daily ? daily.reminderId : -1;
    if (daily && daily.reminderReq.reminderType === reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR) {
      const now = new Date();
      status.dailySkippedToday = (await ReminderService.excludeDates(daily.reminderId)).some((date: Date) =>
        ReminderService.sameDay(date, now));
    }
    hilog.info(ReminderService.DOMAIN, 'LexiGlowReminder',
      'status daily=%{public}d notifications=%{public}s count=%{public}d skippedToday=%{public}s',
      status.dailyReminderId, String(status.notificationEnabled), valid.length, String(status.dailySkippedToday));
    return status;
  }
}
