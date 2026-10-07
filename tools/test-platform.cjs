/* Tests actual ArkTS service sources with native Kit mocks. Device/permission tests remain separate. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const nativeZlib = require('node:zlib');
const { execFileSync } = require('node:child_process');
const deveco = process.env.DEVECO_STUDIO_HOME || '/Applications/DevEco-Studio.app/Contents';
const ts = require(process.env.LEXIGLOW_TYPESCRIPT ||
  path.join(deveco, 'plugins/openharmony/ace-server/node_modules/typescript'));
const root = path.resolve(__dirname, '..');

let listener;
let engineParameters;
let stops = 0;
let shutdowns = 0;
const spoken = [];
const engine = {
  setListener(value) { listener = value; },
  speak(text, parameters) { spoken.push([text, parameters.requestId]); },
  stop() { stops++; },
  shutdown() { shutdowns++; }
};
let notificationsEnabled = true;
let nextReminderId = 12;
const reminderRequests = [];
const cancelledReminders = [];
const reminderValues = new Map([['reminderId', 8]]);
let inflateEndCount = 0;
const xmlEventsScript = `import sys,json,xml.etree.ElementTree as ET
root=ET.fromstring(sys.stdin.read())
events=[]
def visit(element,depth):
    tag=element.tag
    namespace,name=(tag[1:].split('}',1) if tag.startswith('{') else ('',tag))
    events.append([2,name,namespace,depth,''])
    if element.text: events.append([4,name,namespace,depth,element.text])
    for child in element:
        visit(child,depth+1)
        if child.tail: events.append([4,name,namespace,depth,child.tail])
    events.append([3,name,namespace,depth,''])
visit(root,1)
print(json.dumps(events,ensure_ascii=False))`;
class MockXmlPullParser {
  constructor(bytes) { this.source = new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
  parseXml(options) {
    assert.equal(options.supportDoctype, false);
    const events = JSON.parse(execFileSync(process.env.LEXIGLOW_PYTHON || 'python3', ['-c', xmlEventsScript], {
      input: this.source, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024
    }));
    for (const [type, name, namespace, depth, content] of events) {
      const token = { getName: () => name, getNamespace: () => namespace, getDepth: () => depth,
        getText: () => content };
      if (!options.tokenValueCallbackFunction(type, token)) { break; }
    }
  }
}
const kitMocks = {
  '@kit.AbilityKit': {},
  '@kit.BasicServicesKit': {
    zlib: {
      ReturnStatus: { OK: 0, STREAM_END: 1 }, CompressFlushMode: { FINISH: 4 },
      async createZip() {
        let state = {};
        return {
          async inflateInit2(_stream, windowBits) { assert.equal(windowBits, -15); return 0; },
          async inflate(stream, _flush) {
            const bytes = nativeZlib.inflateRawSync(Buffer.from(stream.nextIn), { maxOutputLength: stream.availableOut });
            new Uint8Array(stream.nextOut).set(bytes);
            state = { totalIn: stream.nextIn.byteLength, totalOut: bytes.length };
            return 1;
          },
          async getZStream() { return state; },
          async inflateEnd() { inflateEndCount++; return 0; }
        };
      },
      async createChecksum() { return { async crc32(crc, bytes) { return nativeZlib.crc32(new Uint8Array(bytes), crc); } }; }
    }
  },
  '@kit.ArkTS': {
    util: {
      TextDecoder: { create: (_encoding, options) => ({ decodeToString: bytes =>
        new TextDecoder('utf-8', options).decode(bytes) }) },
      TextEncoder: class { encodeInto(text) { return new TextEncoder().encode(text); } }
    },
    xml: { XmlPullParser: MockXmlPullParser,
      EventType: { START_TAG: 2, END_TAG: 3, TEXT: 4, CDSECT: 5, ENTITY_REFERENCE: 9 } }
  },
  '@kit.CoreFileKit': {},
  '@kit.CoreSpeechKit': {
    textToSpeech: { async createEngine(parameters) { engineParameters = parameters; return engine; } }
  },
  '@kit.ArkData': {
    preferences: { async getPreferences() {
      return {
        async get(key, fallback) { return reminderValues.has(key) ? reminderValues.get(key) : fallback; },
        async put(key, value) { reminderValues.set(key, value); },
        async flush() {}
      };
    } }
  },
  '@kit.NotificationKit': {
    notificationManager: {
      async isNotificationEnabled() { return notificationsEnabled; },
      async requestEnableNotification() {}
    }
  },
  '@kit.BackgroundTasksKit': {
    reminderAgentManager: {
      async cancelReminder(id) { cancelledReminders.push(id); },
      async publishReminder(request) { reminderRequests.push(request); return nextReminderId++; },
      ReminderType: { REMINDER_TYPE_CALENDAR: 1 },
      ActionButtonType: { ACTION_BUTTON_TYPE_CLOSE: 0 }
    }
  }
};
const originalLoad = Module._load;
const originalEtsLoader = require.extensions['.ets'];
Module._load = function(name, parent, isMain) {
  if (Object.prototype.hasOwnProperty.call(kitMocks, name)) { return kitMocks[name]; }
  return originalLoad.call(this, name, parent, isMain);
};
require.extensions['.ets'] = function(module, filename) {
  const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 },
    fileName: filename
  });
  module._compile(result.outputText, filename);
};
const service = name => require(path.join(root, 'entry/src/main/ets/service', `${name}.ets`));
const { TransferService } = service('TransferService');
const { AudioService } = service('AudioService');
const { ReminderService } = service('ReminderService');
const nextTurn = () => new Promise(resolve => setImmediate(resolve));

async function testImport() {
  const validCases = [
    ['array JSON', '[{"word":"  Glow ","meaning":"光"}]',
      book => assert.equal(book.words[0].word, 'glow')],
    ['named JSON', '{"name":"光词","words":[{"word":"learn","meaning":"学习"}]}',
      book => assert.equal(book.name, '光词')],
    ['BOM CRLF quoted CSV', '\ufeffword,phonetic,meaning,example,translation\r\nglow,,"光,微光","He said ""glow"".\r\nIt shines.",它发光\r\n',
      book => {
        assert.equal(book.words[0].meaning, '光,微光');
        assert.equal(book.words[0].example, 'He said "glow".\r\nIt shines.');
      }],
    ['deduplication', 'word,meaning\nGlow,光\nglow,微光',
      book => assert.equal(book.words.length, 1)],
    ['short CSV', 'word,meaning,example\nshine,发光',
      book => assert.equal(book.words[0].example, '')]
  ];
  for (const [label, input, check] of validCases) {
    check(TransferService.parse(input));
    console.log(`PASS ${label}`);
  }
  const invalidCases = [
    '[]', '{}', '[null]', '[{"word":12,"meaning":"a"}]', '[{"word":"a","meaning":{}}]',
    'word,meaning\na,', 'word,meaning\na,"unterminated', 'word,meaning\na,"glow"oops',
    'word,meaning\na,光,unquoted', 'word,word,meaning\na,a,光', 'word,meaning\n汉字,光',
    '[{"word":"a","meaning":"a"}',
    JSON.stringify(Array.from({ length: 5001 }, () => ({ word: 'a', meaning: 'a' })))
  ];
  for (const input of invalidCases) {
    assert.throws(() => TransferService.parse(input));
  }
  console.log(`PASS ${invalidCases.length} malformed / unsafe / oversized inputs rejected`);
}

function zipFixture(entries) {
  const localParts = [], centralParts = [];
  let offset = 0;
  for (const [name, source, stored = false] of entries) {
    const filename = Buffer.from(name);
    const plain = Buffer.from(source);
    const compressed = stored ? plain : nativeZlib.deflateRawSync(plain);
    const method = stored ? 0 : 8;
    const crc = nativeZlib.crc32(plain);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034B50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(method, 8);
    local.writeUInt32LE(crc, 14); local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(plain.length, 22); local.writeUInt16LE(filename.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014B50, 0); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
    central.writeUInt16LE(method, 10); central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(compressed.length, 20); central.writeUInt32LE(plain.length, 24);
    central.writeUInt16LE(filename.length, 28); central.writeUInt32LE(offset, 42);
    localParts.push(local, filename, compressed); centralParts.push(central, filename);
    offset += local.length + filename.length + compressed.length;
  }
  const directory = Buffer.concat(centralParts);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054B50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
  return new Uint8Array(Buffer.concat([...localParts, directory, end]));
}

async function testTextAndDocx() {
  const plain = TransferService.parse('\ufeffglow\t光\r\nretain\r\ntake off   起飞\nshine：发光\nlearn: 学习');
  assert.deepEqual(plain.words.map(word => [word.word, word.meaning]), [
    ['glow', '光'], ['retain', ''], ['take off', '起飞'], ['shine', '发光'], ['learn', '学习']
  ]);
  const tabs = TransferService.parse('单词\t音标\t中文释义\t例句\t译文\nglow\t/gloʊ/\t光\tIt glows.\t它发光。');
  assert.equal(tabs.words[0].example, 'It glows.');
  assert.equal(tabs.words[0].translation, '它发光。');
  assert.throws(() => TransferService.parse('This is an ordinary English paragraph without punctuation'));
  assert.throws(() => TransferService.parse('word,meaning\nglow,'));
  console.log('PASS TXT BOM/CRLF, tabs, Chinese definitions, phrases, colon, word-only lookup and Chinese headers');

  const namespace = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  const paragraph = text => `<w:p><w:r><w:t>${text}</w:t></w:r></w:p>`;
  const cell = text => `<w:tc>${paragraph(text)}</w:tc>`;
  const content = `<w:document xmlns:w="${namespace}"><w:body>` +
    paragraph('词书标题') + paragraph('This ordinary English paragraph should be ignored') + paragraph('retain') +
    `<w:tbl><w:tr>${['单词','音标','中文释义','例句','译文'].map(cell).join('')}</w:tr>` +
    `<w:tr><w:tc><w:p><w:r><w:t>gl</w:t></w:r><w:r><w:t>ow</w:t></w:r></w:p></w:tc>` +
    cell('/gloʊ/') + cell('光 &lt;亮&gt;') + cell('He said &quot;glow&quot;, then smiled.') + cell('他笑了。') +
    '</w:tr></w:tbl></w:body></w:document>';
  const manifest = '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';
  for (const stored of [false, true]) {
    const fixture = zipFixture([['[Content_Types].xml',manifest],['word/document.xml',content,stored]]);
    const book = await TransferService.parseDocx(fixture, '真实 DOCX 测试');
    assert.equal(book.name, '真实 DOCX 测试');
    assert.deepEqual(book.words.map(word => word.word), ['retain','glow']);
    assert.equal(book.words[0].meaning, '');
    assert.equal(book.words[1].meaning, '光 <亮>');
    assert.equal(book.words[1].example, 'He said "glow", then smiled.');
  }
  assert(inflateEndCount >= 1);
  await assert.rejects(TransferService.parseDocx(zipFixture([
    ['[Content_Types].xml',manifest],['word/document.xml',content],['../escape.txt','bad']
  ])), /不安全/);
  await assert.rejects(TransferService.parseDocx(zipFixture([
    ['[Content_Types].xml',manifest],['word/document.xml','<!DOCTYPE x [<!ENTITY evil SYSTEM "file:///private/secrets">]><x/>']
  ])), /DTD/);
  await assert.rejects(TransferService.parseDocx(zipFixture([
    ['[Content_Types].xml',manifest],['word/document.xml','x'.repeat(4 * 1024 * 1024 + 1)]
  ])), /4 MB/);
  const broken = zipFixture([['[Content_Types].xml',manifest],['word/document.xml',content,true]]);
  const bodyOffset = Buffer.from(broken).indexOf(Buffer.from(content));
  broken[bodyOffset] ^= 1;
  await assert.rejects(TransferService.parseDocx(broken), /校验/);
  await assert.rejects(TransferService.parseDocx(new Uint8Array([1,2,3])), /DOCX/);
  console.log('PASS DOCX ZIP stored/deflate extraction, split runs, tables, decoded entities, skipped prose, CRC, traversal/DTD/size rejection');

  for (const format of ['json','csv','txt']) {
    const original = tabs.words;
    original[0].meaning = '光, "微光"';
    const exported = TransferService.formatBook('自定义词书', original, format);
    const imported = TransferService.parse(exported);
    assert.equal(imported.words[0].word, original[0].word);
    assert.equal(imported.words[0].meaning, original[0].meaning);
    assert.equal(imported.words[0].phonetic, original[0].phonetic);
    assert.equal(imported.words[0].example, original[0].example);
  }
  console.log('PASS JSON / CSV / TXT book export and re-import');
}

async function testAudio() {
  const audio = AudioService.getInstance();
  let finished = false;
  let playback = audio.speak('glow').then(() => { finished = true; });
  await nextTurn();
  assert.deepEqual(engineParameters, { language: 'en-US', person: 8, online: 1 });
  listener.onComplete(spoken[0][1], { type: 0 });
  await nextTurn();
  assert.equal(finished, false);
  listener.onComplete(spoken[0][1], { type: 1 });
  await playback;
  playback = audio.speak('shine');
  await nextTurn();
  audio.stop();
  await playback;
  playback = audio.speak('learn');
  await nextTurn();
  listener.onError(spoken[2][1], 42, 'unavailable');
  await assert.rejects(playback, /语音包/);
  audio.release();
  assert.equal(shutdowns, 1);
  assert(stops >= 1);
  await assert.rejects(audio.speak(''), /为空/);
  console.log('PASS TTS offline parameters, synthesis-vs-playback completion, cancellation, error, resource release');
}

async function testReminder() {
  const context = { applicationInfo: { name: 'com.lovexjy.lexiglow' } };
  await ReminderService.configure(context, true, 21, 0);
  assert.deepEqual(reminderRequests[0].daysOfWeek, [1, 2, 3, 4, 5, 6, 7]);
  assert.equal(reminderRequests[0].wantAgent.parameters.route, 'today');
  assert.deepEqual(cancelledReminders, [8]);
  assert.equal(reminderValues.get('reminderId'), 12);
  await ReminderService.configure(context, false, 21, 0);
  assert.deepEqual(cancelledReminders, [8, 12]);
  assert.equal(reminderValues.get('reminderId'), -1);
  notificationsEnabled = false;
  await assert.rejects(ReminderService.configure(context, true, 21, 0), /通知/);
  assert.equal(reminderRequests.length, 1);
  await assert.rejects(ReminderService.configure(context, true, 99, 0), /有效/);
  console.log('PASS reminders own-ID replacement/cancel, daily calendar, route, denied notifications and invalid time');
}

function testFormSchema() {
  const Ajv = require(path.join(deveco, 'tools/hvigor/hvigor-ohos-plugin/node_modules/ajv'));
  const ajv = new Ajv({ strict: false });
  const schema = JSON.parse(fs.readFileSync(
    path.join(deveco, 'sdk/default/openharmony/toolchains/modulecheck/forms.json'), 'utf8'));
  const definitions = JSON.parse(fs.readFileSync(
    path.join(root, 'entry/src/main/resources/base/profile/form_config.json'), 'utf8'));
  const validate = ajv.compile(schema);
  assert(validate(definitions), JSON.stringify(validate.errors));
  console.log('PASS both form definitions validate against the installed Huawei SDK schema');
}

(async () => {
  await testImport();
  await testTextAndDocx();
  await testAudio();
  await testReminder();
  testFormSchema();
  console.log('All platform service checks passed. Native Kit availability and permissions require device validation.');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
}).finally(() => {
  AudioService.getInstance().release();
  Module._load = originalLoad;
  if (originalEtsLoader) { require.extensions['.ets'] = originalEtsLoader; }
  else { delete require.extensions['.ets']; }
});
