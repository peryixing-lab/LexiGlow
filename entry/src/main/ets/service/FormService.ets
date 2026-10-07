import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { formBindingData, formInfo, formProvider } from '@kit.FormKit';
import { AppSnapshot } from '../model/AppModels';

export class DailyFormData {
  word: string = '每天一点光';
  wordId: number = 0;
  meaning: string = '打开词萤，点亮第一个单词';
  progress: string = '开始学习';
  newDone: number = 0;
  newTarget: number = 20;
  dueCount: number = 0;
  estimatedMinutes: number = 3;
  streak: number = 0;
  date: string = '';
}

export class FormService {
  private static readonly NAME: string = 'lexiglow_forms';

  private static store(context: common.Context): preferences.Preferences {
    // A widget provider can run in a separate process. Reload its tiny shared snapshot.
    preferences.removePreferencesFromCacheSync(context, FormService.NAME);
    return preferences.getPreferencesSync(context, { name: FormService.NAME });
  }

  static load(context: common.Context): DailyFormData {
    try {
      const serialized = FormService.store(context).getSync('snapshot', '') as string;
      if (serialized.length > 0) {
        return JSON.parse(serialized) as DailyFormData;
      }
    } catch (_error) {}
    return new DailyFormData();
  }

  private static ids(store: preferences.Preferences): string[] {
    try {
      const ids = JSON.parse(store.getSync('formIds', '[]') as string) as string[];
      return Array.isArray(ids) ? ids.filter((id: string) => typeof id === 'string' && /^\d+$/.test(id)) : [];
    } catch (_error) {
      return [];
    }
  }

  static register(context: common.Context, formId: string): void {
    if (!/^\d+$/.test(formId)) {
      return;
    }
    const store = FormService.store(context);
    const ids = FormService.ids(store);
    if (ids.indexOf(formId) < 0) {
      ids.push(formId);
      store.putSync('formIds', JSON.stringify(ids));
      store.flushSync();
    }
  }

  static remove(context: common.Context, formId: string): void {
    const store = FormService.store(context);
    store.putSync('formIds', JSON.stringify(FormService.ids(store).filter((id: string) => id !== formId)));
    store.flushSync();
  }

  static binding(context: common.Context): formBindingData.FormBindingData {
    return formBindingData.createFormBindingData(FormService.load(context));
  }

  static async update(snapshot: AppSnapshot, context: common.Context): Promise<void> {
    const data = new DailyFormData();
    data.word = snapshot.dailyWord.word || '每天一点光';
    data.wordId = snapshot.dailyWord.id;
    data.meaning = snapshot.dailyWord.meaning || '打开词萤，点亮第一个单词';
    data.newDone = snapshot.plan.newDone;
    data.newTarget = snapshot.plan.newTarget;
    data.progress = `${data.newDone} / ${data.newTarget}`;
    data.dueCount = snapshot.dueCount;
    data.estimatedMinutes = snapshot.plan.estimatedMinutes;
    data.streak = snapshot.stats.streak;
    data.date = snapshot.plan.date;
    const store = FormService.store(context);
    store.putSync('snapshot', JSON.stringify(data));
    store.flushSync();
    let ids = FormService.ids(store);
    try {
      // Reconcile with the system after reinstall, migration, or a missed lifecycle callback.
      const running: formInfo.RunningFormInfo[] = await formProvider.getPublishedRunningFormInfos();
      running.forEach((form: formInfo.RunningFormInfo) => {
        if (ids.indexOf(form.formId) < 0) {
          ids.push(form.formId);
        }
      });
      store.putSync('formIds', JSON.stringify(ids));
      store.flushSync();
    } catch (_error) {}
    const binding = formBindingData.createFormBindingData(data);
    for (const id of ids) {
      try {
        await formProvider.updateForm(id, binding);
      } catch (error) {
        // An unavailable card must never prevent recording a learning result.
        console.warn(`词萤卡片刷新未完成: ${String(error)}`);
      }
    }
  }
}
