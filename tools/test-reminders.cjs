/* Execute the actual ArkTS service with SDK-shaped mocks. These checks protect daily
 * reminders while retiring historical tests; they do not establish native delivery. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  '/Applications/DevEco-Studio.app/Contents/plugins/openharmony/ace-server/node_modules/typescript');
const sourcePath = path.resolve(__dirname, '../entry/src/main/ets/service/ReminderService.ets');
const compiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, fileName: sourcePath
}).outputText;
const context = { abilityInfo: { bundleName: 'com.lovexjy.lexiglow' } };
const values = new Map();
const durable = new Map();
const reminders = new Map();
const delivered = new Map();
const cancelFailures = new Map();
const publications = [];
const exclusions = new Map();
let clockTime = new Date(2030, 0, 10, 12).getTime();
class ClockDate extends Date {
  constructor(...args) { super(...(args.length ? args : [clockTime])); }
  static now() { return clockTime; }
}
let publishError = 0, excludeQueryError = 0, addFailures = 0, deleteFailures = 0, putFailures = 0, flushFailures = 0;
let operations = [], enabled, grantAfterRequest, queryError, activeError, deliveredCancelError, putError, queryCount, mutateOnQuery;
const clone = value => JSON.parse(JSON.stringify(value));
const business = code => Object.assign(new Error('Native failure ' + code), { code });
const notificationKey = (id, label = '') => id + ':' + label;
const store = {
  async get(key, fallback) { return values.has(key) ? values.get(key) : fallback; },
  async put(key, value) {
    operations.push('put:' + key + ':' + value);
    if (putFailures-- > 0) { throw business(123); }
    values.set(key, value);
  },
  async flush() {
    operations.push('flush'); if (flushFailures-- > 0) { throw business(124); } durable.clear();
    for (const [key, value] of values) { durable.set(key, value); }
  }
};
const kits = {
  '@kit.ArkData': { preferences: { async getPreferences() { return store; } } },
  '@kit.NotificationKit': { notificationManager: {
    SlotType: { SERVICE_INFORMATION: 2 },
    async isNotificationEnabled() { operations.push('permission-query'); return enabled; },
    async requestEnableNotification() { operations.push('request-permission'); if (grantAfterRequest) { enabled = true; } },
    async getActiveNotifications() {
      operations.push('active-query');
      if (activeError) { throw business(activeError); }
      return [...delivered.values()].map(clone);
    },
    async cancel(id, label = '') {
      operations.push('cancel-notification:' + notificationKey(id, label));
      if (deliveredCancelError) { throw business(deliveredCancelError); }
      if (!delivered.delete(notificationKey(id, label))) { throw business(1600007); }
    }
  } },
  '@kit.BackgroundTasksKit': { reminderAgentManager: {
    ReminderType: { REMINDER_TYPE_ALARM: 2, REMINDER_TYPE_CALENDAR: 1, REMINDER_TYPE_TIMER: 0 },
    ActionButtonType: { ACTION_BUTTON_TYPE_CLOSE: 0 },
    async getAllValidReminders() {
      operations.push('query'); queryCount++;
      if (queryError) { throw business(queryError); }
      if (mutateOnQuery) { mutateOnQuery(queryCount); }
      return [...reminders].map(([reminderId, reminderReq]) => ({ reminderId, reminderReq: clone(reminderReq) }));
    },
    async publishReminder(request) {
      operations.push('publish');
      if (publishError) { throw business(publishError); }
      const id = 20 + publications.length;
      // 原生 publish 创建独立实例；相同 notificationId 不会自动取消已有日程。
      publications.push([id, clone(request)]); reminders.set(id, clone(request)); exclusions.set(id, []); return id;
    },
    async getExcludeDates(id) {
      operations.push('get-excludes:' + id);
      if (excludeQueryError) { throw business(excludeQueryError); }
      if (!reminders.has(id) || reminders.get(id).reminderType !== 1) { throw business(1700003); }
      return (exclusions.get(id) || []).map(value => new Date(value));
    },
    async addExcludeDate(id, date) {
      operations.push('add-exclude:' + id);
      if (addFailures-- > 0) { throw business(201); }
      if (!reminders.has(id) || reminders.get(id).reminderType !== 1) { throw business(1700003); }
      const midnight = new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
      const dates = exclusions.get(id) || [];
      if (!dates.includes(midnight)) { dates.push(midnight); }
      exclusions.set(id, dates);
    },
    async deleteExcludeDates(id) {
      operations.push('delete-excludes:' + id);
      if (deleteFailures-- > 0) { throw business(201); }
      if (!reminders.has(id) || reminders.get(id).reminderType !== 1) { throw business(1700003); }
      exclusions.set(id, []);
    },
    async cancelReminder(id) {
      operations.push('cancel-reminder:' + id);
      if (cancelFailures.has(id)) { throw business(cancelFailures.get(id)); }
      if (!reminders.delete(id)) { throw business(1700003); } exclusions.delete(id);
    }
  } },
  '@kit.PerformanceAnalysisKit': { hilog: { warn() {}, info() {} } }
};
const exportsObject = {};
vm.runInThisContext('(function(exports, require, Date) { ' + compiled + '\n})', { filename: sourcePath })(
  exportsObject, name => { if (!kits[name]) { throw new Error('Unexpected Kit import ' + name); } return kits[name]; }, ClockDate);
const { ReminderService, ReminderError } = exportsObject;
function reset() {
  values.clear(); durable.clear(); reminders.clear(); delivered.clear(); exclusions.clear(); cancelFailures.clear(); publications.length = 0;
  operations = []; enabled = true; grantAfterRequest = false;
  queryError = 0; activeError = 0; deliveredCancelError = 0; putError = 0; queryCount = 0; mutateOnQuery = undefined;
  publishError = 0; excludeQueryError = 0; addFailures = 0; deleteFailures = 0; putFailures = 0; flushFailures = 0;
  clockTime = new Date(2030, 0, 10, 12).getTime();
}
function daily(id = 8, type = 1) {
  const request = { reminderType: type, notificationId: 1024, groupId: 'lexiglow_daily', hour: 21, minute: 0,
    dateTime: { year: 2030, month: 1, day: 10, hour: 21, minute: 0, second: 0 },
    daysOfWeek: [1, 2, 3, 4, 5, 6, 7], content: '今天的任务还没完成哦，赶紧来学习吧', expiredContent: '今天的任务还没完成哦，赶紧来学习吧' };
  exclusions.set(id, []);
  reminders.set(id, request); values.set('reminderId', id); durable.set('reminderId', id); return clone(request);
}
function legacy(id = 9, fields = {}) {
  reminders.set(id, { reminderType: 0, notificationId: 1025, title: '词萤 · 提醒测试', ...fields });
  values.set('testReminderId', id); durable.set('testReminderId', id);
}
function notification(id = 1025, title = '词萤 · 提醒测试', fields = {}) {
  const record = { id, content: { contentType: 0, normal: { title, text: '测试提醒已送达。' } }, ...fields };
  delivered.set(notificationKey(id, record.label), record);
}
function assertNoEnableOrPublish() {
  assert.ok(!operations.includes('request-permission')); assert.equal(publications.length, 0);
}
async function rejectsCode(operation, code) {
  await assert.rejects(operation, error => error instanceof ReminderError && error.code === code);
}
let count = 0;
async function check(name, test) { reset(); await test(); count++; console.log('PASS ' + name); }
(async () => {
  await check('test publishing and interactive cancel APIs are retired', async () => {
    assert.equal(ReminderService.test, undefined); assert.equal(ReminderService.cancelTest, undefined);
    assert.equal((await ReminderService.status(context)).testReminderId, undefined);
  });
  await check('daily calendar repeats all weekdays with exact task reminder copy and route', async () => {
    await ReminderService.configure(context, true, 21, 17);
    const request = reminders.get(durable.get('reminderId'));
    assert.equal(request.reminderType, 1); assert.equal(request.dateTime.hour, 21); assert.equal(request.dateTime.minute, 17);
    assert.equal(request.content, '今天的任务还没完成哦，赶紧来学习吧'); assert.equal(request.expiredContent, request.content);
    assert.equal(request.dateTime.day, 10);
    assert.deepEqual(request.daysOfWeek, [1, 2, 3, 4, 5, 6, 7]); assert.equal(request.notificationId, 1024);
    assert.equal(request.slotType, 2); assert.equal(request.wantAgent.pkgName, context.abilityInfo.bundleName);
    assert.equal(request.wantAgent.parameters.route, 'today'); assert.equal(request.title, '词萤 · 每天一点光');
  });
  await check('explicit daily enable still requests permission only when required', async () => {
    enabled = false; grantAfterRequest = true;
    await ReminderService.configure(context, true, 21, 0); assert.ok(enabled); assert.equal(publications.length, 1);
    assert.ok(operations.includes('request-permission'));
  });
  await check('denied daily authorization prevents publishing', async () => {
    enabled = false; await rejectsCode(ReminderService.configure(context, true, 21, 0), 1700001);
    assert.equal(publications.length, 0);
  });
  await check('cleanup removes pending and delivered tests, preserving daily records and settings', async () => {
    const before = daily(); legacy(); notification(); notification(1024, '词萤 · 每天一点光');
    values.set('settings', '{"reminderEnabled":true}'); durable.set('settings', values.get('settings'));
    await ReminderService.cleanupLegacyTests(context);
    assert.deepEqual(reminders.get(8), before); assert.equal(reminders.size, 1);
    assert.equal(durable.get('reminderId'), 8); assert.equal(durable.get('settings'), '{"reminderEnabled":true}');
    assert.equal(durable.get('testReminderId'), -1); assert.equal(delivered.size, 1);
    assert.ok(delivered.has(notificationKey(1024))); assertNoEnableOrPublish();
  });
  await check('cleanup works with notifications disabled without opening authorization', async () => {
    daily(); legacy(); enabled = false;
    await ReminderService.cleanupLegacyTests(context); assert.ok(reminders.has(8)); assert.ok(!reminders.has(9));
    assertNoEnableOrPublish(); assert.ok(!operations.includes('permission-query'));
  });
  await check('stale test preference pointing to daily native ID never cancels daily', async () => {
    const before = daily(); values.set('testReminderId', 8); durable.set('testReminderId', 8);
    await ReminderService.cleanupLegacyTests(context); assert.deepEqual(reminders.get(8), before);
    assert.ok(!operations.some(item => item.startsWith('cancel-reminder:'))); assertNoEnableOrPublish();
  });
  await check('missing preferences still allow recognition of historical test group', async () => {
    daily(); legacy(9, { notificationId: 555, groupId: 'lexiglow_test' }); values.delete('testReminderId');
    await ReminderService.cleanupLegacyTests(context); assert.ok(!reminders.has(9)); assert.ok(reminders.has(8));
  });
  await check('legacy records without group are identified by reserved test notification ID', async () => {
    daily(); legacy(); await ReminderService.cleanupLegacyTests(context);
    assert.ok(!reminders.has(9)); assert.ok(reminders.has(8));
  });
  await check('alarm and calendar IDs are never treated as timer tests', async () => {
    daily(); legacy(9, { reminderType: 2 }); legacy(10, { reminderType: 1 });
    await ReminderService.cleanupLegacyTests(context); assert.equal(reminders.size, 3);
    assert.ok(!operations.some(item => item.startsWith('cancel-reminder:')));
  });
  await check('daily notification or daily group overrides conflicting test markers', async () => {
    legacy(9, { notificationId: 1024, groupId: 'lexiglow_test' }); legacy(10, { groupId: 'lexiglow_daily' });
    await ReminderService.cleanupLegacyTests(context); assert.equal(reminders.size, 2);
  });
  await check('native ID recycled between queries cannot cancel its new daily record', async () => {
    legacy(); mutateOnQuery = count => { if (count === 2) { daily(9); } };
    await ReminderService.cleanupLegacyTests(context); assert.ok(reminders.has(9));
    assert.ok(!operations.includes('cancel-reminder:9')); assert.equal(durable.get('reminderId'), 9);
  });
  await check('unrelated timers and notifications remain intact', async () => {
    reminders.set(30, { reminderType: 0, notificationId: 333 }); values.set('testReminderId', 30);
    notification(333, '另一个通知'); notification(1025, '其他业务通知');
    await ReminderService.cleanupLegacyTests(context); assert.ok(reminders.has(30)); assert.equal(delivered.size, 2);
    assert.ok(!operations.some(item => item.startsWith('cancel-')));
  });
  await check('labelled test notification is removed by its exact native identity', async () => {
    notification(1025, '词萤 · 提醒测试', { label: 'legacy-label' });
    notification(1025, '其他业务通知', { label: 'keep-label' });
    await ReminderService.cleanupLegacyTests(context);
    assert.ok(!delivered.has(notificationKey(1025, 'legacy-label')));
    assert.ok(delivered.has(notificationKey(1025, 'keep-label')));
    assert.ok(operations.includes('cancel-notification:1025:legacy-label'));
  });
  await check('test group permits cleaning reserved ID even when displayed title changed', async () => {
    notification(1025, '', { groupName: 'lexiglow_test' }); notification(1024, '词萤 · 提醒测试', { groupName: 'lexiglow_test' });
    await ReminderService.cleanupLegacyTests(context); assert.equal(delivered.size, 1);
    assert.ok(delivered.has(notificationKey(1024)));
  });
  await check('already dismissed native notification is a successful cleanup', async () => {
    daily(); notification(); deliveredCancelError = 1600007;
    await ReminderService.cleanupLegacyTests(context); assert.equal(durable.get('testReminderId'), -1);
    assert.ok(reminders.has(8)); assertNoEnableOrPublish();
  });
  await check('native query denial reports code without touching daily or requesting permissions', async () => {
    const before = daily(); queryError = 201;
    await rejectsCode(ReminderService.cleanupLegacyTests(context), 201);
    assert.deepEqual(reminders.get(8), before); assert.ok(!operations.some(item => item.startsWith('cancel-')));
    assertNoEnableOrPublish();
  });
  await check('test cancellation failure preserves daily and leaves cleanup retryable', async () => {
    const before = daily(); legacy(); cancelFailures.set(9, 201);
    await rejectsCode(ReminderService.cleanupLegacyTests(context), 201);
    assert.deepEqual(reminders.get(8), before); assert.equal(durable.get('testReminderId'), 9);
    cancelFailures.clear(); await ReminderService.cleanupLegacyTests(context); assert.ok(!reminders.has(9));
  });
  await check('notification service failure preserves daily and reports original code', async () => {
    const before = daily(); activeError = 1600003;
    await rejectsCode(ReminderService.cleanupLegacyTests(context), 1600003);
    assert.deepEqual(reminders.get(8), before); assertNoEnableOrPublish();
  });
  await check('notification cancellation failure remains retryable without daily cancellation', async () => {
    const before = daily(); notification(); deliveredCancelError = 1600003;
    await rejectsCode(ReminderService.cleanupLegacyTests(context), 1600003); assert.deepEqual(reminders.get(8), before);
    deliveredCancelError = 0; await ReminderService.cleanupLegacyTests(context); assert.equal(delivered.size, 0);
  });
  await check('repeated startup cleanup is idempotent and never publishes', async () => {
    const before = daily(); legacy(); notification(); await ReminderService.cleanupLegacyTests(context);
    await ReminderService.cleanupLegacyTests(context); assert.deepEqual(reminders.get(8), before);
    assert.equal(operations.filter(item => item === 'cancel-reminder:9').length, 1); assertNoEnableOrPublish();
  });
  await check('daily status still reflects current native record and notification authorization', async () => {
    values.set('reminderId', 8); assert.equal((await ReminderService.status(context)).dailyReminderId, -1);
    daily(); enabled = false; const status = await ReminderService.status(context);
    assert.equal(status.dailyReminderId, 8); assert.equal(status.notificationEnabled, false);
  });
  await check('invalid daily times fail before touching native services', async () => {
    await assert.rejects(ReminderService.configure(context, true, 24, 0), /有效/);
    await assert.rejects(ReminderService.configure(context, true, 12, 60), /有效/);
    assert.equal(operations.length, 0);
  });
  const settings = fields => ({ reminderEnabled: true, reminderHour: 21, reminderMinute: 0, dailyNewTarget: 20, ...fields });
  const today = () => new Date(new ClockDate().getFullYear(), new ClockDate().getMonth(), new ClockDate().getDate()).getTime();
  await check('incomplete task uses existing cycle without replacing its native ID', async () => {
    daily(); await ReminderService.syncDailyProgress(context, settings(), 19);
    assert.equal(durable.get('reminderId'), 8); assert.equal(exclusions.get(8).length, 0); assertNoEnableOrPublish();
  });
  await check('incomplete refresh at the scheduled instant cannot exclude a pending native delivery', async () => {
    daily(); clockTime = new Date(2030, 0, 10, 21).getTime();
    await ReminderService.syncDailyProgress(context, settings(), 19);
    assert.deepEqual(exclusions.get(8), []); assert.ok(!operations.includes('add-exclude:8'));
    assert.ok(!operations.some(item => item.startsWith('cancel-'))); assertNoEnableOrPublish();
  });
  await check('late incomplete refresh cleans old exclusions without skipping an unfinished day', async () => {
    daily(); exclusions.set(8, [new Date(2030, 0, 9).getTime()]);
    clockTime = new Date(2030, 0, 10, 22).getTime();
    await ReminderService.syncDailyProgress(context, settings(), 19);
    assert.deepEqual(exclusions.get(8), []); assert.ok(!operations.includes('add-exclude:8')); assertNoEnableOrPublish();
  });
  await check('completion exactly at the custom target excludes only today and keeps tomorrow cycle', async () => {
    daily(); await ReminderService.syncDailyProgress(context, settings(), 20);
    assert.deepEqual(exclusions.get(8), [today()]); assert.ok(reminders.has(8)); assertNoEnableOrPublish();
    assert.deepEqual(reminders.get(8).daysOfWeek, [1, 2, 3, 4, 5, 6, 7]);
  });
  await check('goal increase restores the pending reminder before today scheduled time', async () => {
    daily(); await ReminderService.syncDailyProgress(context, settings(), 20);
    await ReminderService.syncDailyProgress(context, settings({ dailyNewTarget: 30 }), 20);
    assert.deepEqual(exclusions.get(8), []); assert.ok(reminders.has(8)); assertNoEnableOrPublish();
  });
  await check('goal increase after reminder time keeps today excluded and never republishes overdue notification', async () => {
    daily(); await ReminderService.syncDailyProgress(context, settings(), 20);
    clockTime = new Date(2030, 0, 10, 22).getTime();
    await ReminderService.syncDailyProgress(context, settings({ dailyNewTarget: 30 }), 20);
    assert.deepEqual(exclusions.get(8), [today()]); assertNoEnableOrPublish();
  });
  await check('next-day progress removes prior completed-day exclusion without app midnight work', async () => {
    daily(); await ReminderService.syncDailyProgress(context, settings(), 20);
    clockTime = new Date(2030, 0, 11, 9).getTime(); await ReminderService.syncDailyProgress(context, settings(), 0);
    assert.deepEqual(exclusions.get(8), []); assertNoEnableOrPublish();
  });
  await check('queued yesterday completion cannot exclude today after the operation crosses midnight', async () => {
    daily(); exclusions.set(8, [today()]);
    clockTime = new Date(2030, 0, 10, 23, 59).getTime();
    const pending = ReminderService.syncDailyProgress(context, settings(), 20);
    clockTime = new Date(2030, 0, 11, 0, 1).getTime(); await pending;
    assert.deepEqual(exclusions.get(8), []); assertNoEnableOrPublish();
  });
  await check('new registration crossing an authorization boundary cannot carry yesterday completion forward', async () => {
    enabled = false; grantAfterRequest = true; clockTime = new Date(2030, 0, 10, 23, 59).getTime();
    mutateOnQuery = () => { clockTime = new Date(2030, 0, 11, 0, 1).getTime(); };
    await ReminderService.configure(context, true, 21, 0, 20, 20);
    const id = durable.get('reminderId'); assert.equal(reminders.get(id).dateTime.day, 11);
    assert.deepEqual(exclusions.get(id), []); assert.ok(operations.includes('request-permission'));
  });
  await check('exclusion history is bounded to today during consecutive completions', async () => {
    daily(); await ReminderService.syncDailyProgress(context, settings(), 20);
    clockTime = new Date(2030, 0, 11, 9).getTime(); await ReminderService.syncDailyProgress(context, settings(), 20);
    assert.deepEqual(exclusions.get(8), [today()]); assertNoEnableOrPublish();
  });
  await check('registration after scheduled time begins tomorrow and cannot catch up today', async () => {
    clockTime = new Date(2030, 0, 10, 22).getTime(); await ReminderService.configure(context, true, 21, 0, 0, 20);
    const id = durable.get('reminderId'); assert.equal(reminders.get(id).dateTime.day, 11);
    assert.deepEqual(exclusions.get(id), [today()]);
  });
  await check('completed task registration retains daily cycle with today excluded', async () => {
    await ReminderService.configure(context, true, 21, 0, 20, 20);
    const id = durable.get('reminderId'); assert.deepEqual(exclusions.get(id), [today()]);
    assert.equal(reminders.get(id).dateTime.day, 10);
  });
  await check('completed progress clears labelled delivered daily notification while preserving schedule and tests', async () => {
    daily(); legacy(); notification(1024, '每日提醒', { label: 'reminder_agent' }); notification();
    await ReminderService.syncDailyProgress(context, settings(), 20);
    assert.ok(reminders.has(8)); assert.ok(reminders.has(9)); assert.ok(!delivered.has(notificationKey(1024, 'reminder_agent')));
    assert.ok(delivered.has(notificationKey(1025))); assert.ok(operations.includes('cancel-notification:1024:reminder_agent'));
  });
  await check('notification authorization is never requested during passive synchronization', async () => {
    daily(); enabled = false; await ReminderService.syncDailyProgress(context, settings(), 20);
    assert.deepEqual(exclusions.get(8), []); assertNoEnableOrPublish(); assert.ok(!operations.includes('query'));
  });
  await check('explicit disable cancels only actual daily identities despite stale stored IDs', async () => {
    daily(); legacy(); values.set('reminderId', 9); await ReminderService.configure(context, false, 21, 0, 0, 20);
    assert.ok(!reminders.has(8)); assert.ok(reminders.has(9)); assert.equal(durable.get('reminderId'), -1);
    assertNoEnableOrPublish();
  });
  await check('passive disabled snapshot cannot cancel a newly enabled native reminder', async () => {
    daily(); await ReminderService.syncDailyProgress(context, settings({ reminderEnabled: false }), 0);
    assert.ok(reminders.has(8)); assert.equal(operations.length, 0); assertNoEnableOrPublish();
  });
  await check('user denial preserves previous native daily schedule', async () => {
    const before = daily(); enabled = false;
    await rejectsCode(ReminderService.configure(context, true, 20, 0, 0, 20), 1700001);
    assert.deepEqual(reminders.get(8), before); assert.equal(durable.get('reminderId'), 8); assert.equal(publications.length, 0);
  });
  await check('legacy alarm migrates to conditional calendar and explicitly cancels the still-live old instance', async () => {
    daily(8, 2); await ReminderService.syncDailyProgress(context, settings(), 0);
    assert.equal(reminders.size, 1); assert.equal(reminders.get(durable.get('reminderId')).reminderType, 1);
    assert.ok(operations.includes('cancel-reminder:8')); assert.ok(!operations.includes('request-permission'));
    assert.ok(operations.indexOf('publish') < operations.indexOf('cancel-reminder:8'));
  });
  await check('daily ID missing from local preferences is recovered by valid notification identity', async () => {
    daily(); values.set('reminderId', 333); reminders.set(333, { reminderType: 0, notificationId: 333 });
    await ReminderService.syncDailyProgress(context, settings(), 20);
    assert.equal(durable.get('reminderId'), 8); assert.ok(reminders.has(333)); assert.deepEqual(exclusions.get(8), [today()]);
  });
  await check('publish error preserves original reminder before native mutation', async () => {
    const before = daily(); publishError = 201;
    await rejectsCode(ReminderService.configure(context, true, 20, 0, 0, 20), 201);
    assert.deepEqual(reminders.get(8), before); assert.equal(durable.get('reminderId'), 8);
  });
  for (const failure of ['put', 'flush']) {
    await check(failure + ' failure removes the independent new calendar and retains the original schedule and exclusion state', async () => {
      daily(); exclusions.set(8, [today()]);
      if (failure === 'put') { putFailures = 1; } else { flushFailures = 1; }
      await rejectsCode(ReminderService.configure(context, true, 20, 0, 0, 20), failure === 'put' ? 123 : 124);
      const id = durable.get('reminderId'); assert.equal(reminders.size, 1); assert.equal(reminders.get(id).dateTime.hour, 21);
      assert.equal(id, 8); assert.deepEqual(exclusions.get(id), [today()]); assert.ok(!reminders.has(20));
      assert.ok(!operations.includes('cancel-reminder:8')); assert.equal(publications.length, 1);
    });
  }
  await check('changed time publishes a second instance before explicitly retiring the prior calendar', async () => {
    daily(); await ReminderService.configure(context, true, 20, 15, 0, 20);
    const id = durable.get('reminderId'); assert.equal(id, 20); assert.equal(reminders.size, 1);
    assert.ok(!reminders.has(8)); assert.equal(reminders.get(id).dateTime.hour, 20);
    assert.equal(reminders.get(id).dateTime.minute, 15);
    assert.ok(operations.indexOf('publish') < operations.indexOf('cancel-reminder:8'));
    assert.ok(operations.indexOf('flush') < operations.indexOf('cancel-reminder:8'));
  });
  await check('failed old-instance cancellation removes the new instance and preserves the original schedule for retry', async () => {
    const before = daily(); exclusions.set(8, [today()]); cancelFailures.set(8, 201);
    await rejectsCode(ReminderService.configure(context, true, 20, 15, 0, 20), 201);
    assert.equal(reminders.size, 1); assert.deepEqual(reminders.get(8), before); assert.ok(!reminders.has(20));
    assert.equal(durable.get('reminderId'), 8); assert.deepEqual(exclusions.get(8), [today()]);
    assert.ok(operations.indexOf('cancel-reminder:8') < operations.indexOf('cancel-reminder:20'));
    cancelFailures.clear(); await ReminderService.configure(context, true, 20, 15, 0, 20);
    const id = durable.get('reminderId'); assert.equal(reminders.size, 1); assert.ok(!reminders.has(8));
    assert.equal(reminders.get(id).dateTime.hour, 20); assert.equal(reminders.get(id).dateTime.minute, 15);
  });
  await check('exclusion add failure restores existing native calendar without losing future reminder', async () => {
    daily(); addFailures = 1; await rejectsCode(ReminderService.syncDailyProgress(context, settings(), 20), 201);
    assert.ok(reminders.has(8)); assert.deepEqual(exclusions.get(8), []); assert.equal(durable.get('reminderId'), 8);
    await ReminderService.syncDailyProgress(context, settings(), 20); assert.deepEqual(exclusions.get(8), [today()]);
  });
  await check('goal restoration exclusion delete failure restores completion state for retry', async () => {
    daily(); exclusions.set(8, [today()]); deleteFailures = 1;
    await rejectsCode(ReminderService.syncDailyProgress(context, settings({ dailyNewTarget: 30 }), 20), 201);
    assert.deepEqual(exclusions.get(8), [today()]); assert.ok(reminders.has(8));
    await ReminderService.syncDailyProgress(context, settings({ dailyNewTarget: 30 }), 20); assert.deepEqual(exclusions.get(8), []);
  });
  await check('failure on newly created completion exclusion restores original alarm', async () => {
    daily(8, 2); addFailures = 1;
    await rejectsCode(ReminderService.configure(context, true, 21, 0, 20, 20), 201);
    assert.equal(reminders.size, 1); assert.equal(reminders.get(durable.get('reminderId')).reminderType, 2);
  });
  await check('disable persistence failure restores original repeating calendar and exclusions', async () => {
    daily(); exclusions.set(8, [today()]); flushFailures = 1;
    await rejectsCode(ReminderService.configure(context, false, 21, 0, 0, 20), 124);
    const id = durable.get('reminderId'); assert.equal(reminders.size, 1); assert.equal(reminders.get(id).reminderType, 1);
    assert.deepEqual(exclusions.get(id), [today()]);
  });
  await check('rollback failure exposes original and recovery error codes', async () => {
    daily(); flushFailures = 1; cancelFailures.set(20, 201);
    await assert.rejects(ReminderService.configure(context, true, 20, 0, 0, 20), error =>
      error instanceof ReminderError && error.code === 124 && /恢复原提醒也失败/.test(error.message) && /201/.test(error.message));
  });
  await check('concurrent progress changes serialize and retain final target state', async () => {
    daily(); await Promise.all([ReminderService.syncDailyProgress(context, settings(), 20),
      ReminderService.syncDailyProgress(context, settings({ dailyNewTarget: 30 }), 20)]);
    assert.deepEqual(exclusions.get(8), []); assert.equal(reminders.size, 1); assertNoEnableOrPublish();
  });
  await check('queued settings are copied before the caller mutates its UI object', async () => {
    daily(); const input = settings(); const pending = ReminderService.syncDailyProgress(context, input, 20);
    input.dailyNewTarget = 30; await pending; assert.deepEqual(exclusions.get(8), [today()]);
  });
  await check('invalid progress or target never touches native state', async () => {
    await assert.rejects(ReminderService.configure(context, true, 21, 0, -1, 20), /进度/);
    await assert.rejects(ReminderService.configure(context, true, 21, 0, 0, 0), /目标/);
    assert.equal(operations.length, 0);
  });
  await check('status reports native today exclusion rather than assuming it from progress or past dates', async () => {
    daily(); assert.equal((await ReminderService.status(context)).dailySkippedToday, false);
    exclusions.set(8, [new Date(2030, 0, 9).getTime()]);
    assert.equal((await ReminderService.status(context)).dailySkippedToday, false);
    exclusions.set(8, [today()]); assert.equal((await ReminderService.status(context)).dailySkippedToday, true);
    clockTime = new Date(2030, 0, 11, 9).getTime();
    assert.equal((await ReminderService.status(context)).dailySkippedToday, false);
  });
  await check('legacy alarm status cannot claim the native schedule skips today', async () => {
    daily(8, 2); const state = await ReminderService.status(context);
    assert.equal(state.dailyReminderId, 8); assert.equal(state.dailySkippedToday, false);
    assert.ok(!operations.some(item => item.startsWith('get-excludes:')));
  });
  await check('native exclusion query failure prevents a false skipped-today status', async () => {
    const before = daily(); excludeQueryError = 201;
    await rejectsCode(ReminderService.status(context), 201); assert.deepEqual(reminders.get(8), before);
    assertNoEnableOrPublish();
  });
  console.log('All ' + count + ' reminder retirement and daily regression checks passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
