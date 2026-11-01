import { WordEnrichment, WordRelation, ConfusingWord } from '../model/AppModels';
import { strengthName } from '../utils/MemoryUtils';

@ComponentV2
export struct WordKnowledgeCard {
  @Param enrichment: WordEnrichment = new WordEnrichment();
  @Param autoExpand: boolean = false;
  @Event onOpenWord: (id: number) => void = (_id: number) => {};
  @Local rootOpen: boolean = false;
  @Local confusingOpen: boolean = false;

  aboutToAppear(): void { this.confusingOpen = this.autoExpand; }

  build() {
    Column({ space: 14 }) {
      if (this.enrichment.coreMeanings.length > 0) {
        Text('先记住这些核心意思').fontSize(13).fontColor($r('app.color.text_secondary')).width('100%')
        Text(this.enrichment.coreMeanings.join('；')).fontSize(20).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).width('100%').padding(16)
          .backgroundColor($r('app.color.glow')).borderRadius(16)
      }
      if (this.enrichment.collocations.length > 0) {
        Text('常用搭配').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary')).width('100%')
        ForEach(this.enrichment.collocations, (phrase: string) => {
          Text(phrase).fontSize(16).lineHeight(26).fontColor($r('app.color.text_primary')).width('100%')
        }, (phrase: string) => phrase)
      }
      if (this.enrichment.analysis) {
        Button(this.rootOpen ? '词根解析  −' : '词根解析  +').width('100%').height(46)
          .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
          .onClick(() => { this.rootOpen = !this.rootOpen; })
        if (this.rootOpen) {
          Text(this.enrichment.analysis).fontSize(16).lineHeight(26).fontColor($r('app.color.text_primary')).width('100%')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.enrichment.familyWords, (relation: WordRelation) => {
              Button(`${relation.word.word} · ${relation.learned ? strengthName(relation.strength) : '未学'}`)
                .margin({ right: 8, bottom: 8 }).height(44).backgroundColor($r('app.color.soft_surface'))
                .fontColor(relation.strength >= 75 ? $r('app.color.success') : $r('app.color.text_primary'))
                .onClick(() => { this.onOpenWord(relation.word.id); })
            }, (relation: WordRelation) => `${relation.word.id}`)
          }.width('100%')
        }
      }
      if (this.enrichment.confusingWords.length > 0) {
        Button(this.confusingOpen ? '易混辨析  −' : '易混辨析  +').height(46).width('100%')
          .backgroundColor($r('app.color.soft_surface')).fontColor($r('app.color.text_primary'))
          .onClick(() => { this.confusingOpen = !this.confusingOpen; })
        if (this.confusingOpen) {
          ForEach(this.enrichment.confusingWords, (pair: ConfusingWord) => {
            Column({ space: 8 }) {
              Button(`${pair.word.word}  ${pair.word.phonetic}`).fontSize(18).height(48)
                .backgroundColor(Color.Transparent).fontColor($r('app.color.success'))
                .onClick(() => { this.onOpenWord(pair.word.id); })
              Text(pair.word.meaning).fontSize(15).lineHeight(24).fontColor($r('app.color.text_primary')).width('100%')
              Text(pair.note).fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%')
              if (pair.word.example) {
                Text(pair.word.example).fontSize(14).lineHeight(24).fontColor($r('app.color.text_secondary')).width('100%')
              }
            }.padding(16).backgroundColor($r('app.color.soft_surface')).borderRadius(18).width('100%')
          }, (pair: ConfusingWord) => `${pair.word.id}`)
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
