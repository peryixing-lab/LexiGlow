import { Word } from '../model/AppModels';
import { LearningService } from '../service/LearningService';
import { SharedWordService } from '../service/SharedWordService';

@ComponentV2
export struct SharedWordsPage {
  @Param text: string = '';
  @Event onDone: () => void = () => {};
  @Event onImport: (text: string) => void = (_text: string) => {};
  @Local words: Word[] = [];
  @Local missing: string[] = [];
  @Local selected: number[] = [];
  @Local candidateLabels: Map<number, string> = new Map<number, string>();
  @Local loading: boolean = true;
  @Local saving: boolean = false;
  @Local error: string = '';
  private active: boolean = false;

  aboutToAppear(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    const words: Word[] = [];
    const missing: string[] = [];
    const selected: number[] = [];
    const labels = new Map<number, string>();
    try {
      for (const headword of SharedWordService.wordsFromText(this.text)) {
        const candidates = await LearningService.getInstance().lookupCandidates(headword);
        if (!this.active) { return; }
        if (candidates.length === 0) { missing.push(headword); }
        for (const word of candidates) {
          if (!words.some((existing: Word): boolean => existing.id === word.id)) { words.push(word); }
          const previous = labels.get(word.id) || '';
          const label = candidates.length > 1 ? `原文 ${headword} · 存在多个候选，请选择` :
            (word.word !== headword ? `原文 ${headword} → ${word.word}` : '');
          if (label) { labels.set(word.id, previous ? `${previous}；${label}` : label); }
          if (candidates.length === 1 && selected.indexOf(word.id) < 0) { selected.push(word.id); }
        }
      }
      this.words = words;
      this.missing = missing;
      this.selected = selected;
      this.candidateLabels = labels;
    } catch { if (this.active) { this.error = '本地匹配暂时没能完成，请重试。'; } }
    finally { if (this.active) { this.loading = false; } }
  }

  private toggle(id: number): void {
    this.selected = this.selected.indexOf(id) >= 0 ? this.selected.filter((value: number) => value !== id) :
      this.selected.concat([id]);
  }

  private async save(): Promise<void> {
    if (this.saving || this.selected.length === 0) { return; }
    this.saving = true;
    this.error = '';
    const revision = AppStorage.get<number>('lexiglowSharedRevision') || 0;
    const selected = this.selected.slice();
    try {
      for (const id of selected) { await LearningService.getInstance().setNewWord(id, true); }
      if (revision === (AppStorage.get<number>('lexiglowSharedRevision') || 0)) {
        AppStorage.setOrCreate('lexiglowSharedText', '');
      }
      if (this.active) {
        this.getUIContext().getPromptAction().showToast({ message: `${selected.length} 个词已加入生词本` });
        this.onDone();
      }
    } catch { if (this.active) { this.error = '部分单词尚未保存，再次保存即可继续。'; } }
    finally { if (this.active) { this.saving = false; } }
  }

  build() {
    Scroll() {
      Column({ space: 18 }) {
        Text('确认要收下的单词').fontSize(26).fontColor($r('app.color.text_primary')).width('100%')
        Text('最多识别 20 个原文词形。变形会尝试还原；有多个候选时请按原文选择。选中后加入生词本。').fontSize(14).lineHeight(24)
          .fontColor($r('app.color.text_secondary')).width('100%')
        if (this.loading) { LoadingProgress().width(36).height(36) }
        if (this.error) {
          Text(this.error).fontColor($r('app.color.text_secondary'))
          if (!this.saving) { Button('重新匹配').onClick(() => { this.load(); }) }
        }
        ForEach(this.words, (word: Word) => {
          Row({ space: 14 }) {
            Checkbox({ name: `${word.id}` }).select(this.selected.indexOf(word.id) >= 0)
              .selectedColor($r('app.color.success')).enabled(!this.saving)
              .onChange(() => { this.toggle(word.id); }).accessibilityText(`收下 ${word.word}`)
            Column({ space: 7 }) {
              Text(`${word.word}  ${word.phonetic}`).fontSize(22).fontColor($r('app.color.text_primary'))
              if (this.candidateLabels.has(word.id)) {
                Text(this.candidateLabels.get(word.id) || '').fontSize(12).lineHeight(20)
                  .fontColor($r('app.color.text_secondary'))
              }
              Text(word.meaning).fontSize(15).lineHeight(24).fontColor($r('app.color.text_secondary'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.padding(20).width('100%').backgroundColor($r('app.color.surface')).borderRadius(22)
        }, (word: Word) => `${word.id}`)
        if (!this.loading && this.words.length === 0 && !this.error) {
          Text('本地词库中没有匹配到这些词。').fontSize(18).fontColor($r('app.color.text_primary'))
        }
        if (this.missing.length > 0) {
          Text(`待补充释义：${this.missing.join('、')}`).fontSize(15).lineHeight(25).fontColor($r('app.color.text_secondary'))
          Button('到导入页补充释义').height(48).fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.soft_surface')).enabled(!this.saving)
            .onClick(() => { this.onImport(this.missing.join('\n')); })
        }
        if (this.words.length > 0) {
          Button(this.saving ? '正在保存…' : `收下 ${this.selected.length} 个词`).width('100%').height(52)
            .enabled(!this.saving && this.selected.length > 0).backgroundColor($r('app.color.brand_ink'))
            .fontColor($r('app.color.inverse_text')).onClick(() => { this.save(); })
        }
      }.width('100%').constraintSize({ maxWidth: 760 }).padding({ left: 24, right: 24, top: 76, bottom: 40 })
    }.width('100%').height('100%').align(Alignment.Top).backgroundColor($r('app.color.background'))
  }
}
