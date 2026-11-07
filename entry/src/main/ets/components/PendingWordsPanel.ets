import { PendingWordDraft } from '../model/PendingWordModels';
import { PendingWordService } from '../service/PendingWordService';

@ComponentV2
export struct PendingWordsPanel {
  @Event onChanged: () => void = () => {};
  @Local drafts: PendingWordDraft[] = [];
  @Local expanded: boolean = false;
  @Local editingId: string = '';
  @Local meaningDraft: string = '';
  @Local busy: boolean = false;
  @Local feedback: string = '';
  private generation: number = 0;
  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { this.generation++; }
  private async load(): Promise<void> {
    const generation = ++this.generation;
    try {
      const drafts = await PendingWordService.getInstance().list();
      if (generation === this.generation) { this.drafts = drafts; }
    } catch { if (generation === this.generation) { this.feedback = '待补充词未能载入，可点此重试。'; } }
  }
  private async save(): Promise<void> {
    if (this.busy || !this.meaningDraft.trim()) { return; }
    const generation = this.generation; const id = this.editingId; const meaning = this.meaningDraft;
    this.busy = true; this.feedback = '';
    try {
      await PendingWordService.getInstance().complete(id, meaning);
      if (generation !== this.generation) { return; }
      this.editingId = ''; this.meaningDraft = ''; this.busy = false;
      this.feedback = '词条和原句已保存，可在下方查看。'; this.onChanged(); await this.load();
    } catch (error) {
      if (generation === this.generation) { this.feedback = (error as Error).message || '没有保存成功，请重试'; }
    } finally { if (generation === this.generation) { this.busy = false; } }
  }
  private async remove(id: string): Promise<void> {
    if (this.busy) { return; }
    const generation = this.generation; this.busy = true; this.feedback = '';
    try {
      await PendingWordService.getInstance().remove(id);
      if (generation !== this.generation) { return; }
      this.busy = false; this.editingId = ''; await this.load();
    } catch { if (generation === this.generation) { this.feedback = '未能删除，请重试'; } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }
  build() {
    Column({ space: 12 }) {
      if (this.drafts.length > 0) {
        Button(`待补充词 · ${this.drafts.length} 条 ${this.expanded ? '收起' : '展开'}`)
          .height(48).fontColor($r('app.color.text_primary')).backgroundColor($r('app.color.glow'))
          .enabled(!this.busy).onClick(() => { this.expanded = !this.expanded; })
        if (this.expanded) {
          Text('填好释义后保存为词条与原句。它们不会自动加入每日学习。').fontSize(13).lineHeight(22)
            .fontColor($r('app.color.text_secondary')).width('100%')
          ForEach(this.drafts.slice(0, 20), (draft: PendingWordDraft) => {
            Column({ space: 10 }) {
              Text(draft.spelling).fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
              Text(draft.sentence).fontSize(16).lineHeight(26).fontColor($r('app.color.text_primary')).width('100%')
              Text(`来自「${draft.articleTitle}」`).fontSize(12).fontColor($r('app.color.text_secondary')).width('100%')
              if (this.editingId === draft.id) {
                TextArea({ text: this.meaningDraft, placeholder: '填写你确认的中文释义' }).height(100).maxLength(4000)
                  .onChange((text: string) => { this.meaningDraft = text; })
                Button('保存词条与原句').height(44).enabled(!this.busy && this.meaningDraft.trim().length > 0)
                  .backgroundColor($r('app.color.glow')).fontColor($r('app.color.text_primary')).onClick(() => { this.save(); })
              }
              Row({ space: 12 }) {
                Button(this.editingId === draft.id ? '取消编辑' : '补充释义').height(44).enabled(!this.busy)
                  .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
                  .onClick(() => { this.editingId = this.editingId === draft.id ? '' : draft.id; this.meaningDraft = ''; })
                Button('删除待补充').height(44).enabled(!this.busy)
                  .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_secondary')).onClick(() => { this.remove(draft.id); })
              }
            }.padding(18).width('100%').backgroundColor($r('app.color.soft_surface')).borderRadius(18)
          }, (draft: PendingWordDraft) => draft.id)
          if (this.drafts.length > 20) { Text('先整理最近 20 条，完成后会显示更早的记录。').fontSize(12).fontColor($r('app.color.text_secondary')) }
        }
      }
      if (this.feedback) { Button(this.feedback).fontSize(13).backgroundColor(Color.Transparent)
        .fontColor($r('app.color.text_secondary')).onClick(() => { this.load(); }) }
    }.width('100%')
  }
}
