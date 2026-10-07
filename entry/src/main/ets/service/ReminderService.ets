import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';

export class ReminderService {
  private static async cancel(id: number): Promise<void> {
    try {
      await reminderAgentManager.cancelReminder(id);
    } catch (error) {
      if ((error as BusinessError).code !== 1700003) {
        throw new Error('提醒未能关闭，请稍后重试');
      }
      // The system may already have removed a reminder. Clear its stale local ID.
    }
  }

  /** Only invoked after the user explicitly enables reminders in settings. */
  static async configure(context: common.UIAbilityContext, enabled: boolean, hour: number,
    minute: number): Promise<void> {
    const store = await preferences.getPreferences(context, { name: 'lexiglow_reminders' });
    const previousId = await store.get('reminderId', -1) as number;
    if (!enabled) {
      if (previousId >= 0) {
        await ReminderService.cancel(previousId);
      }
      await store.put('reminderId', -1);
      await store.flush();
      return;
    }
    if (!Number.isInteger(hour) || hour < 0 || hour > 23 || !Number.isInteger(minute) || minute < 0 || minute > 59) {
      throw new Error('请选择有效的提醒时间');
    }
    if (!await notificationManager.isNotificationEnabled()) {
      await notificationManager.requestEnableNotification(context);
    }
    if (!await notificationManager.isNotificationEnabled()) {
      throw new Error('通知尚未开启，可在系统设置中允许词萤通知');
    }
    const next = new Date();
    next.setHours(hour, minute, 0, 0);
    if (next.getTime() <= Date.now()) {
      next.setDate(next.getDate() + 1);
    }
    const request: reminderAgentManager.ReminderRequestCalendar = {
      reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_CALENDAR,
      dateTime: { year: next.getFullYear(), month: next.getMonth() + 1, day: next.getDate(), hour: hour, minute: minute },
      daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
      title: '词萤 · 每天一点光',
      content: '有空的时候，来点亮几个单词吧。',
      expiredContent: '今天重新亮起来，从一小步开始。',
      notificationId: 1024,
      groupId: 'lexiglow_daily',
      ringDuration: 0,
      snoozeTimes: 0,
      tapDismissed: true,
      actionButton: [{ title: '关闭', type: reminderAgentManager.ActionButtonType.ACTION_BUTTON_TYPE_CLOSE }],
      wantAgent: { pkgName: context.applicationInfo.name, abilityName: 'EntryAbility', parameters: { route: 'today' } }
    };
    let id: number;
    try {
      id = await reminderAgentManager.publishReminder(request);
    } catch (_error) {
      throw new Error('系统暂不支持代理提醒或应用尚未获准使用此能力，提醒未开启');
    }
    if (previousId >= 0 && previousId !== id) {
      try {
        await ReminderService.cancel(previousId);
      } catch (_error) {
        // Do not retain two active schedules if replacing the previous schedule fails.
        await ReminderService.cancel(id);
        throw new Error('原提醒未能更新，请稍后重试');
      }
    }
    await store.put('reminderId', id);
    await store.flush();
  }
}
