import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { UserSettings } from '../model/AppModels';

export function copySettings(value: UserSettings): UserSettings {
  const settings = new UserSettings();
  settings.onboarded = value.onboarded;
  settings.currentBookId = value.currentBookId;
  settings.dailyNewTarget = value.dailyNewTarget;
  settings.autoPronounce = value.autoPronounce;
  settings.reminderEnabled = value.reminderEnabled;
  settings.reminderHour = value.reminderHour;
  settings.reminderMinute = value.reminderMinute;
  settings.themeMode = value.themeMode;
  settings.learningMode = value.learningMode;
  settings.foundation = value.foundation;
  settings.examDate = value.examDate;
  return settings;
}

export class UserSettingsStore {
  private store: preferences.Preferences | undefined = undefined;
  private current: UserSettings = new UserSettings();

  async initialize(context: common.Context): Promise<void> {
    this.store = await preferences.getPreferences(context, { name: 'ciying_settings' });
    const raw = await this.store.get('settings', '');
    if (typeof raw === 'string' && raw.length > 0) {
      try {
        const parsed = JSON.parse(raw) as UserSettings;
        this.current = copySettings(parsed);
        this.validate(this.current);
      } catch (_) {
        // Recover settings only. The RDB and learning history are never deleted.
        this.current = new UserSettings();
      }
    }
  }

  getSettings(): UserSettings {
    return copySettings(this.current);
  }

  async save(value: UserSettings): Promise<void> {
    const next = copySettings(value);
    this.validate(next);
    if (!this.store) {
      throw new Error('学习偏好尚未初始化');
    }
    await this.store.put('settings', JSON.stringify(next));
    await this.store.flush();
    this.current = next;
  }

  private validate(settings: UserSettings): void {
    if (typeof settings.currentBookId !== 'string' || settings.currentBookId.length === 0 ||
      !Number.isFinite(settings.dailyNewTarget) || settings.dailyNewTarget < 1 || settings.dailyNewTarget > 100 ||
      !Number.isFinite(settings.reminderHour) || !Number.isFinite(settings.reminderMinute) ||
      settings.reminderHour < 0 || settings.reminderHour > 23 ||
      settings.reminderMinute < 0 || settings.reminderMinute > 59 ||
      ['system', 'light', 'dark'].indexOf(settings.themeMode) < 0 ||
      ['normal', 'exam'].indexOf(settings.learningMode) < 0 ||
      typeof settings.onboarded !== 'boolean' || typeof settings.autoPronounce !== 'boolean' ||
      typeof settings.reminderEnabled !== 'boolean' || typeof settings.foundation !== 'string' ||
      typeof settings.examDate !== 'string') {
      throw new Error('学习偏好格式不正确');
    }
    settings.dailyNewTarget = Math.floor(settings.dailyNewTarget);
    settings.reminderHour = Math.floor(settings.reminderHour);
    settings.reminderMinute = Math.floor(settings.reminderMinute);
  }
}
