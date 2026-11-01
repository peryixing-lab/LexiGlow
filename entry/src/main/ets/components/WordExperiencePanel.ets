import { SentenceMemory, SkillEvidence } from '../model/ExperienceModels';
import { ExperienceService } from '../service/ExperienceService';
import { skillEvidence } from '../utils/ExperienceUtils';

@ComponentV2
export struct WordExperiencePanel {
  @Param wordId: number = 0;
  @Param compact: boolean = false;
  @Event onSource: (articleId: number, paragraphKey: string) => void = () => {};
  @Local sentences: SentenceMemory[] = [];
  @Local evidence: SkillEvidence[] = [];
  @Local expanded: boolean = false;
  @Local error: string = '';
  @Local editingId: string = '';
  @Local noteDraft: string = '';
  @Local busy: boolean = false;
  private generation: number = 0;
  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { this.generation++; }
  @Monitor('wordId')
  wordChanged(): void { this.load(); }

  private async load(): Promise<void> {
    const generation = ++this.generation; this.expanded = !this.compact; this.sentences = []; this.evidence = [];
    this.editingId = ''; this.busy = false; this.error = '';
    try {
      const sentences = await ExperienceService.getInstance().sentences(this.wordId);
      const evidence = skillEvidence(await ExperienceService.getInstance().attempts(this.wordId));
      if (generation === this.generation) { this.sentences = sentences; this.evidence = evidence; }
    } catch { if (generation === this.generation) { this.error = '原句和练习记录暂未载入'; } }
  }

  private async saveNote(item: SentenceMemory): Promise<void> {
    if (this.busy) { return; }
    const generation = this.generation; this.busy = true; this.error = '';
    const copy = JSON.parse(JSON.stringify(item)) as SentenceMemory; copy.note = this.noteDraft;
    try { await ExperienceService.getInstance().saveSentence(copy); if (generation === this.generation) { await this.load(); } }
    catch { if (generation === this.generation) { this.error = '备注未能保存，请重试'; } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }

  private remove(item: SentenceMemory): void {
    this.getUIContext().showAlertDialog({ title: '删除这条原句？', message: '单词和学习进度会保留。', buttons: [
      { value: '保留', action: () => {} }, { value: '删除', action: () => { this.deleteSentence(item.id); } }
    ] });
  }

  private async deleteSentence(id: string): Promise<void> {
    const generation = this.generation; this.busy = true;
    try { await ExperienceService.getInstance().removeSentence(id); if (generation === this.generation) { await this.load(); } }
    catch { if (generation === this.generation) { this.error = '原句未能删除，请重试'; } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }

  build() {
    Column({ space: 14 }) {
      if (!this.compact) {
        Text('我练到哪一步了').fontSize(19).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
        ForEach(this.evidence, (item: SkillEvidence) => {
          Text(`${item.label} · ${item.total === 0 ? '尚未练习' : `最近 ${item.total} 题答对 ${item.correct} 题${item.hinted > 0 ? `，其中 ${item.hinted} 题有提示` : ''}`}`)
            .fontSize(14).lineHeight(23).fontColor($r('app.color.text_secondary')).width('100%')
        }, (item: SkillEvidence) => item.mode)
        Text('听音写词同时涉及听辨与拼写；这些记录不等同于完全掌握。').fontSize(12).lineHeight(20)
          .fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.sentences.length > 0) {
        Button(this.expanded ? '收起我的原句' : `想不起来？看看我的原句 · ${this.sentences.length}`)
          .height(46).width('100%').backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
          .onClick(() => { this.expanded = !this.expanded; })
        if (this.expanded) {
          if (this.compact) { Text('原句是回忆提示，用过提示后请按真实情况判断。').fontSize(12).fontColor($r('app.color.text_secondary')) }
          ForEach(this.sentences.slice(0, this.compact ? 1 : 100), (item: SentenceMemory) => {
            Column({ space: 10 }) {
              Text(item.sentence).fontSize(17).lineHeight(28).fontColor($r('app.color.text_primary')).width('100%')
              Text(`来自「${item.articleTitle}」`).fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
              if (item.note) { Text(item.note).fontSize(14).lineHeight(23).fontColor($r('app.color.text_secondary')).width('100%') }
              if (!this.compact) {
                if (this.editingId === item.id) {
                  TextArea({ text: this.noteDraft, placeholder: '这句话让我想起…' }).maxLength(500).height(100)
                    .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
                    .onChange((text: string) => { this.noteDraft = text; })
                  Button('保存备注').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).enabled(!this.busy).onClick(() => { this.saveNote(item); })
                }
                Flex({ wrap: FlexWrap.Wrap }) {
                  if (item.articleId !== 0) {
                    Button('回到原文').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).margin({ right: 8, bottom: 8 }).enabled(!this.busy)
                      .onClick(() => { this.onSource(item.articleId, item.paragraphKey); })
                  } else { Text('来源文章已删除，原句仍保留').fontSize(12).fontColor($r('app.color.text_secondary')) }
                  Button('写备注').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).margin({ right: 8, bottom: 8 }).enabled(!this.busy)
                    .onClick(() => { this.editingId = item.id; this.noteDraft = item.note; })
                  Button('删除').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).margin({ bottom: 8 }).enabled(!this.busy).onClick(() => { this.remove(item); })
                }
              }
            }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 10, bottom: 10 })
          }, (item: SentenceMemory) => item.id)
        }
      } else if (!this.compact) {
        Text('我的原句 · 在文章中点词，保存遇见它的那句话。').fontSize(14).lineHeight(23)
          .fontColor($r('app.color.text_secondary')).width('100%')
      }
      if (this.error) {
        Text(this.error).fontSize(13).fontColor($r('app.color.text_secondary'))
        Button('重新载入').height(44).backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary')).onClick(() => { this.load(); })
      }
    }.width('100%').padding(this.compact && this.sentences.length === 0 && !this.error ? 0 : 20)
      .backgroundColor($r('app.color.surface')).borderRadius(22)
  }
}
