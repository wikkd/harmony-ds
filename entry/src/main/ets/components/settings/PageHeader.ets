/** 二级页面通用页头：灰色圆形返回钮 + 居中标题（仿官方设置子页） */
@ComponentV2
export struct PageHeader {
  @Param title: string = '';
  @Param onBack: () => void = (): void => {};

  build() {
    Row() {
      Row() {
        Image($r('app.media.ic_public_back'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.text_primary'))
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r('app.color.component_normal'))
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
      .onClick(() => {
        this.onBack();
      })
      Blank()
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Row()
        .width(40)
        .height(40)
    }
    .width('100%')
    .height(56)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
  }
}
