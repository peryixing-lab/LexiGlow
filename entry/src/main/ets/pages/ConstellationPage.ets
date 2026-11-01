import { LearnedWord } from '../model/AppModels';
import { LearningService } from '../service/LearningService';
import { strengthName } from '../utils/MemoryUtils';
import { AdaptiveWindowState, adaptiveWindowState } from '../utils/AdaptiveWindow';

class Star {
  item: LearnedWord = new LearnedWord();
  x: number = 0;
  y: number = 0;
}

@ComponentV2
export struct ConstellationPage {
  @Event onOpenWord: (id: number) => void = (_id: number) => {};
  @Local windowState: AdaptiveWindowState = adaptiveWindowState();
  @Local items: LearnedWord[] = [];
  @Local selected: LearnedWord = new LearnedWord();
  @Local error: string = '';
  @Local loading: boolean = true;
  private stars: Star[] = [];
  private readonly settings: RenderingContextSettings = new RenderingContextSettings(true);
  private readonly canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasWidth: number = 0;
  private canvasHeight: number = 360;
  private active: boolean = false;
  private canvasReady: boolean = false;

  aboutToAppear(): void { this.active = true; this.load(); }
  aboutToDisappear(): void { this.active = false; }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const items = await LearningService.getInstance().getConstellationWords(120);
      if (!this.active) { return; }
      this.items = items;
      this.selected = items[0] || new LearnedWord();
      this.draw();
    } catch { if (this.active) { this.error = '星图暂时没能载入，请重试。'; } }
    finally { if (this.active) { this.loading = false; } }
  }

  private color(strength: number): string {
    return strength < 25 ? '#8F9DA5' : strength < 50 ? '#EAB786' : strength < 75 ? '#E7D994' : '#FFD45C';
  }

  private draw(): void {
    if (!this.canvasReady || this.canvasWidth <= 0) { return; }
    this.canvas.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    this.stars = this.items.map((item: LearnedWord): Star => {
      const star = new Star();
      star.item = item;
      star.x = 22 + ((item.word.id * 0.61803398875) % 1) * Math.max(0, this.canvasWidth - 44);
      star.y = 22 + ((item.word.id * 0.41421356237) % 1) * (this.canvasHeight - 44);
      return star;
    });
    const families = new Map<string, Star>();
    for (const star of this.stars) {
      if (star.item.strength < 75 || !star.item.familyKey) { continue; }
      const related = families.get(star.item.familyKey);
      if (related) {
        this.canvas.beginPath();
        this.canvas.strokeStyle = '#655A39';
        this.canvas.lineWidth = 1;
        this.canvas.moveTo(related.x, related.y);
        this.canvas.lineTo(star.x, star.y);
        this.canvas.stroke();
      }
      families.set(star.item.familyKey, star);
    }
    for (const star of this.stars) {
      this.canvas.beginPath();
      this.canvas.fillStyle = this.color(star.item.strength);
      this.canvas.shadowColor = this.color(star.item.strength);
      this.canvas.shadowBlur = star.item.strength >= 75 ? 12 : 3;
      this.canvas.arc(star.x, star.y, 2.5 + star.item.strength / 32, 0, Math.PI * 2);
      this.canvas.fill();
    }
    this.canvas.shadowBlur = 0;
  }

  private select(x: number, y: number): void {
    let closest: Star | undefined = undefined;
    let distance = 28 * 28;
    for (const star of this.stars) {
      const current = (star.x - x) * (star.x - x) + (star.y - y) * (star.y - y);
      if (current < distance) { closest = star; distance = current; }
    }
    if (closest) { this.selected = closest.item; }
  }

  build() {
    Scroll() {
      Column({ space: 20 }) {
        Text('每一个词，都是一点光。').fontSize(26).fontColor($r('app.color.text_primary')).width('100%')
        Text('显示最近学习的最多 120 个词。同根词达到掌握后相连，点击光点查看单词。')
          .fontSize(14).lineHeight(23).fontColor($r('app.color.text_secondary')).width('100%')
        if (this.loading) { LoadingProgress().width(32).height(32) }
        if (this.error) {
          Text(this.error).fontColor($r('app.color.text_secondary'))
          Button('重新载入').onClick(() => { this.load(); })
        }
        Canvas(this.canvas).height(360).width('100%').backgroundColor('#1A1D1E').borderRadius(24)
          .onReady(() => { this.canvasReady = true; this.draw(); })
          .onAreaChange((_old: Area, area: Area) => { this.canvasWidth = Number(area.width); this.draw(); })
          .onClick((event: ClickEvent) => { this.select(event.x, event.y); })
          .accessibilityText(`词汇星图，已展示 ${this.items.length} 个已学词，可使用下方单词按钮选择`)
        Text('灰：陌生  ·  橙：模糊  ·  淡黄：熟悉  ·  金：掌握').fontSize(12).fontColor($r('app.color.text_secondary'))
        if (this.selected.word.id > 0) {
          Column({ space: 10 }) {
            Text(this.selected.word.word).fontSize(30).fontFamily('serif').fontColor($r('app.color.text_primary'))
            Text(`${strengthName(this.selected.strength)} · ${this.selected.strength} / 100`).fontColor($r('app.color.success'))
            Text(this.selected.word.meaning).fontSize(18).lineHeight(28).fontColor($r('app.color.text_primary'))
            Button('查看单词').backgroundColor($r('app.color.brand_ink')).fontColor($r('app.color.inverse_text'))
              .onClick(() => { this.onOpenWord(this.selected.word.id); })
          }.width('100%').padding(24).backgroundColor($r('app.color.surface')).borderRadius(24)
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.items, (item: LearnedWord) => {
              Button(item.word.word).height(42).margin(4).backgroundColor($r('app.color.soft_surface'))
                .fontColor($r('app.color.text_primary')).accessibilityText(`${item.word.word}，${strengthName(item.strength)}`)
                .onClick(() => { this.selected = item; })
            }, (item: LearnedWord) => `${item.word.id}`)
          }.width('100%')
        } else if (!this.loading && !this.error) {
          Text('先点亮几个词，星空就会留下你的记忆。').fontColor($r('app.color.text_secondary'))
        }
      }.width('100%').constraintSize({ maxWidth: 920 }).padding({ left: 24, right: 24, top: 76 })
    }.width('100%').height(LayoutPolicy.matchParent).align(Alignment.Top)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .contentEndOffset(24 + this.windowState.bottomInset)
      .background($r('app.color.background'))
  }
}
