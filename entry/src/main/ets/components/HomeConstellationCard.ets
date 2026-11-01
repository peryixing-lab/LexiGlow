/** A decorative constellation illustration; the learned count comes only from the study snapshot. */
@ComponentV2
export struct HomeConstellationCard {
  @Param learnedCount: number = 0;
  @Event onOpen: () => void = () => {};
  @Local cardWidth: number = 0;

  private count(): number { return Math.max(0, Math.floor(this.learnedCount)); }

  private previewWidth(): number { return this.cardWidth >= 440 ? 142 : 104; }
  private previewScale(): number { return this.previewWidth() / 142; }
  private previewHeight(): number { return 94 * this.previewScale(); }

  @Builder
  StarIllustration() {
    Image($r('app.media.home_constellation_preview'))
      .width(this.previewWidth()).height(this.previewHeight()).objectFit(ImageFit.Contain)
      .accessibilityLevel('no-hide-descendants')
  }

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 16 }) {
        Row({ space: 14 }) {
          Column({ space: 9 }) {
            Text('词汇星图').fontSize(20).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Text(this.count() > 0 ? `已学习 ${this.count()} 个单词` : '第一颗星，等你点亮')
              .fontSize(16).fontWeight(FontWeight.Medium).lineHeight(25).fontColor($r('app.color.success'))
            Text(this.count() > 0 ? '每次回忆，都留下一点光。' : '从一个词，开始你的星空。')
              .fontSize(12).lineHeight(20).fontColor($r('app.color.text_secondary'))
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          this.StarIllustration()
        }.width('100%').alignItems(VerticalAlign.Center)
        Row() {
          Text('查看我的星图').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.success'))
          Blank()
          Text('↗').fontSize(20).fontColor($r('app.color.success')).width(34).height(34)
            .textAlign(TextAlign.Center).backgroundColor($r('app.color.constellation_cta')).borderRadius(17)
        }.width('100%').padding({ top: 12 })
          .border({ width: { top: 1 }, color: $r('app.color.constellation_border') })
      }.width('100%').padding(22).alignItems(HorizontalAlign.Start)
    }.width('100%').padding(0)
      .backgroundColor($r('app.color.constellation_surface'))
      .border({ width: 1, color: $r('app.color.constellation_border'), radius: 24 })
      .borderRadius(24).clip(true)
      .hoverEffect(HoverEffect.Auto).accessibilityGroup(true)
      .accessibilityText(`词汇星图，已学习 ${this.count()} 个单词，查看我的星图`)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const width = Number(newArea.width);
        if (Math.abs(width - this.cardWidth) >= 1) { this.cardWidth = width; }
      })
      .onClick(() => { this.onOpen(); })
  }
}
