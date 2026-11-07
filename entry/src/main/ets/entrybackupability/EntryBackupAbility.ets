import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackupExtensionAbility, BundleVersion, fileIo } from '@kit.CoreFileKit';
import { contextConstant } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';

/** Only the consistent SQLite copy enters the system backup; temporary recordings never do. */
export default class EntryBackupAbility extends BackupExtensionAbility {
  async onBackup(): Promise<void> {
    this.context.area = contextConstant.AreaMode.EL2;
    const directory = `${this.context.filesDir}/lexiglow_system_backup`;
    if (!fileIo.accessSync(directory)) { fileIo.mkdirSync(directory, true); }
    const store = await relationalStore.getRdbStore(this.context, {
      name: 'ciying.db', securityLevel: relationalStore.SecurityLevel.S1
    });
    try { await store.backup(`${directory}/learning.db`); }
    finally { await store.close(); }
    hilog.info(0x0000, 'LexiGlowBackup', 'consistent learning snapshot prepared');
  }

  async onRestore(_bundleVersion: BundleVersion): Promise<void> {
    this.context.area = contextConstant.AreaMode.EL2;
    const directory = `${this.context.filesDir}/lexiglow_system_backup`;
    if (!fileIo.accessSync(`${directory}/learning.db`)) { throw new Error('系统学习备份缺失'); }
    // rootDir opens the transported file read-only, without creating an empty replacement on failure.
    const snapshot = await relationalStore.getRdbStore(this.context, {
      name: 'learning.db', rootDir: directory, securityLevel: relationalStore.SecurityLevel.S1
    });
    try {
      if (snapshot.version < 1 || snapshot.version > 6) { throw new Error('系统备份版本不受支持'); }
      const rows = await snapshot.querySql('PRAGMA quick_check');
      try { if (!rows.goToFirstRow() || rows.getString(0) !== 'ok') { throw new Error('系统备份不完整'); } }
      finally { rows.close(); }
      const required = await snapshot.querySql('SELECT COUNT(*) FROM word_progress');
      required.close();
    } finally { await snapshot.close(); }
    const store = await relationalStore.getRdbStore(this.context, {
      name: 'ciying.db', securityLevel: relationalStore.SecurityLevel.S1
    });
    try { await store.restore(`${directory}/learning.db`); }
    finally { await store.close(); }
    hilog.info(0x0000, 'LexiGlowBackup', 'learning snapshot restored');
  }
}
