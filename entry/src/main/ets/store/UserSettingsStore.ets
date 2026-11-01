import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { UserSettings } from '../model/AppModels';
import { DatabaseManager, DatabaseTransaction } from '../repository/DatabaseManager';

export function copySettings(value: UserSettings): UserSettings {
  const settings = new UserSettings();
  settings.onboarded = value.onboarded;
  settings.currentBookId = value.currentBookId;
  settings.dailyNewTarget = value.dailyNewTarget;
  settings.autoPronounceConfigured = value.autoPronounceConfigured === undefined ? false : value.autoPronounceConfigured;
  settings.autoPronounce = settings.autoPronounceConfigured ? value.autoPronounce : false;
  settings.reminderEnabled = value.reminderEnabled;
  settings.reminderHour = value.reminderHour;
  settings.reminderMinute = value.reminderMinute;
  settings.themeMode = value.themeMode;
  settings.learningMode = value.learningMode;
  settings.foundation = value.foundation;
  settings.examDate = value.examDate;
  settings.spellingRecall = value.spellingRecall === undefined ? false : value.spellingRecall;
  settings.hapticsEnabled = value.hapticsEnabled === undefined ? true : value.hapticsEnabled;
  return settings;
}

export class UserSettingsStore {
  private store: preferences.Preferences | undefined = undefined;
  private database: DatabaseManager | undefined = undefined;
  private current: UserSettings = new UserSettings();

  async initialize(context: common.Context, database?: DatabaseManager): Promise<void> {
    this.database = database;
    this.store = await preferences.getPreferences(context, { name: 'ciying_settings' });
    let raw = await this.store.get('settings', '');
    let migrated = false;
    if (database) {
      const rows = await database.getStore().querySql("SELECT value FROM app_meta WHERE key='user_settings'");
      try {
        if (rows.goToFirstRow()) { raw = rows.getString(0); migrated = true; }
      } finally { rows.close(); }
    }
    let needsPronunciationMigration: boolean = false;
    if (typeof raw === 'string' && raw.length > 0) {
      try {
        const parsed = JSON.parse(raw) as UserSettings;
        this.current = copySettings(parsed);
        this.validate(this.current);
        needsPronunciationMigration = parsed.autoPronounceConfigured === undefined;
      } catch (_) {
        // Recover settings only. The RDB and learning history are never deleted.
        this.current = new UserSettings();
      }
    }
    if (needsPronunciationMigration || (database !== undefined && !migrated)) {
      // Persist the silent default once; later explicit choices survive upgrades.
      await this.save(this.current);
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
    if (this.database) {
      // The same RDB transaction can commit settings together with a restored learning backup.
      await this.database.transaction(async (store: DatabaseTransaction) => {
        await store.executeSql("INSERT OR REPLACE INTO app_meta(key,value) VALUES('user_settings',?)",
          [JSON.stringify(next)]);
      });
    } else {
      await this.store.put('settings', JSON.stringify(next));
      await this.store.flush();
    }
    this.current = next;
  }

  /** Called only after a restore transaction has durably committed these settings. */
  acceptCommitted(value: UserSettings): void {
    const next = copySettings(value);
    this.validate(next);
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
      typeof settings.autoPronounceConfigured !== 'boolean' ||
      typeof settings.reminderEnabled !== 'boolean' || typeof settings.foundation !== 'string' ||
      typeof settings.examDate !== 'string' || typeof settings.spellingRecall !== 'boolean' ||
      typeof settings.hapticsEnabled !== 'boolean') {
      throw new Error('学习偏好格式不正确');
    }
    settings.dailyNewTarget = Math.floor(settings.dailyNewTarget);
    settings.reminderHour = Math.floor(settings.reminderHour);
    settings.reminderMinute = Math.floor(settings.reminderMinute);
  }
}
