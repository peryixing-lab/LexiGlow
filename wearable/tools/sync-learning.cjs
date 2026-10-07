#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');

// An entry HAP cannot depend on another entry HAP. Keep one authoritative learning
// implementation in entry, and verify these build-local copies instead of forking it.
const moduleRoot = path.resolve(__dirname, '..');
const sourceRoot = path.resolve(moduleRoot, '..', 'entry', 'src', 'main');
const targetRoot = path.join(moduleRoot, 'src', 'main');
const core = [
  'ets/model/AppModels.ets',
  'ets/repository/DatabaseManager.ets',
  'ets/repository/LearningRepository.ets',
  'ets/service/LearningService.ets',
  'ets/service/ReviewScheduler.ets',
  'ets/store/UserSettingsStore.ets',
  'ets/utils/MemoryUtils.ets',
  'ets/utils/TimeUtils.ets'
];
const resources = [
  'resources/rawfile/wordbooks/catalog.json',
  'resources/rawfile/licenses/ECDICT-MIT.txt',
  'resources/base/media/ciying_icon.svg'
];
const args = new Set(process.argv.slice(2));
for (const arg of args) {
  if (!['--check', '--core', '--resources'].includes(arg)) {
    throw new Error(`Unknown argument: ${arg}`);
  }
}
const selected = args.has('--core') || args.has('--resources') ?
  [...(args.has('--core') ? core : []), ...(args.has('--resources') ? resources : [])] :
  [...core, ...resources];
const stale = [];
for (const relative of selected) {
  const source = fs.readFileSync(path.join(sourceRoot, relative));
  const destination = path.join(targetRoot, relative);
  if (args.has('--check')) {
    if (!fs.existsSync(destination) || !source.equals(fs.readFileSync(destination))) {
      stale.push(relative);
    }
  } else {
    fs.mkdirSync(path.dirname(destination), { recursive: true });
    fs.writeFileSync(destination, source);
  }
}
if (stale.length > 0) {
  console.error(`Wearable learning copies are stale:\n${stale.join('\n')}\nRun node wearable/tools/sync-learning.cjs.`);
  process.exitCode = 1;
} else {
  console.log(`${args.has('--check') ? 'Verified' : 'Synchronized'} ${selected.length} wearable learning files.`);
}
