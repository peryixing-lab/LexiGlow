import { KeyCode } from '@kit.InputKit';

@ComponentV2
export struct PrimaryNavigation {
  @Param selectedIndex: number = 0;
  @Event onSelect: (index: number) => void = () => {};

  private boundedIndex(): number {
    return Math.max(0, Math.min(3, Math.floor(this.selectedIndex)));
  }

  @Builder
  private navigationItem(icon: Resource, label: string, index: number) {
    Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      Row({ space: 8 }) {
        Image(icon).width(20).height(20)
          .fillColor(index === this.boundedIndex() ? $r('app.color.brand_ink') : $r('app.color.text_secondary'))
        Text(label).fontSize(16).maxLines(1)
          .fontWeight(index === this.boundedIndex() ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(index === this.boundedIndex() ? $r('app.color.brand_ink') : $r('app.color.text_secondary'))
      }
    }
    .width(84).height(40).padding({ left: 12, right: 12 })
    .border({ width: 0 }).borderRadius(12)
    .backgroundColor(index === this.boundedIndex() ? $r('app.color.glow') : Color.Transparent)
    .focusable(true).hoverEffect(HoverEffect.Highlight)
    .accessibilityText(label)
    .accessibilityDescription(index === this.boundedIndex() ? '当前页面，已选中' : `切换到${label}页面`)
    .onKeyEvent((event: KeyEvent): boolean => {
      if (event.type === KeyType.Down && (event.keyCode === KeyCode.KEYCODE_ENTER ||
        event.keyCode === KeyCode.KEYCODE_SPACE || event.keyCode === KeyCode.KEYCODE_NUMPAD_ENTER)) {
        this.onSelect(index);
        return true;
      }
      return false;
    })
    .onClick(() => { this.onSelect(index); })
  }

  build() {
    Row({ space: 24 }) {
      Row({ space: 10 }) {
        Image($r('app.media.ciying_icon')).width(32).height(32).objectFit(ImageFit.Contain).borderRadius(8)
        Text('LexiGlow').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.text_primary'))
          .layoutWeight(1).maxLines(1)
      }.width(164).height(40)
      Row({ space: 8 }) {
        this.navigationItem($r('app.media.dock_home'), '首页', 0)
        this.navigationItem($r('app.media.dock_books'), '词库', 1)
        this.navigationItem($r('app.media.dock_statistics'), '统计', 2)
        this.navigationItem($r('app.media.dock_profile'), '我的', 3)
      }.height(40)
    }.height(40).constraintSize({ maxWidth: 640 })
  }
}
