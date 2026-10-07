import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { TransferService } from '../../../main/ets/service/TransferService';

/** Uses real Huawei zlib/XML; reads a test resource and never opens the learning database. */
export default function platformNativeTest(): void {
  describe('PlatformNativeTest', () => {
    it('docxNativeZipXml', 0, async () => {
      const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext()
        .getApplicationContext().createModuleContext('entry_test');
      const bytes = await context.resourceManager.getRawFileContent('platform_wordbook.docx');
      const book = await TransferService.parseDocx(bytes, '原生导入测试');
      expect(book.name).assertEqual('原生导入测试');
      expect(book.words.length).assertEqual(3);
      expect(book.words[0].word).assertEqual('unlistedword');
      expect(book.words[0].meaning).assertEqual('');
      const glow = book.words.find((word) => word.word === 'glow');
      const retain = book.words.find((word) => word.word === 'retain');
      expect(glow !== undefined).assertTrue();
      expect(retain !== undefined).assertTrue();
      if (glow && retain) {
        expect(glow.meaning).assertEqual('光；发光');
        expect(glow.example).assertEqual('The lamp glows.');
        expect(glow.translation).assertEqual('灯发出微光。');
        expect(retain.meaning).assertEqual('保留');
      }
    });

    it('textNativeParsing', 0, () => {
      const book = TransferService.parse('\uFEFFglow\t光\r\nretain\ntake off 起飞\nshine：发光');
      expect(book.words.length).assertEqual(4);
      expect(book.words[0].word).assertEqual('glow');
      expect(book.words[0].meaning).assertEqual('光');
      expect(book.words[1].meaning).assertEqual('');
      expect(book.words[2].word).assertEqual('take off');
      expect(book.words[2].meaning).assertEqual('起飞');
      expect(book.words[3].meaning).assertEqual('发光');
    });

    it('bookNativeExportRoundTrip', 0, () => {
      const source = TransferService.parse('[{"word":"glow","phonetic":"/gloʊ/","meaning":"光,微光","example":"He said \\"glow\\".","translation":"他说微光。"}]');
      const formats: string[] = ['json', 'csv', 'txt'];
      formats.forEach((format: string) => {
        const exported = TransferService.formatBook('原生导出测试', source.words, format);
        const result = TransferService.parse(exported);
        expect(result.words.length).assertEqual(1);
        expect(result.words[0].word).assertEqual('glow');
        expect(result.words[0].meaning).assertEqual('光,微光');
        expect(result.words[0].phonetic).assertEqual('/gloʊ/');
        expect(result.words[0].example).assertEqual(source.words[0].example);
      });
    });
  });
}
