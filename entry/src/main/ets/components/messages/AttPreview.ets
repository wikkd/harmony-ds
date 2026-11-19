import { Fonts } from '../../common/Fonts';
import { Dim } from '../../common/DesignTokens';

/** 会话区图片预览缩略图：加载失败（缓存被清等）自动降级为文件条 */
@ComponentV2
export struct AttPreview {
  @Param path: string = '';
  @Param name: string = '';
  @Param onOpen: (path: string) => void = (): void => {};
  @Local failed: boolean = false;

  /** 文件名截断（7.0.0.111 实机回归：列表内数字 constraintSize(maxWidth) 会毒化子树，改代码级截断） */
  private shortName(): string {
    return this.name.length > 16 ? `${this.name.slice(0, 16)}…` : this.name;
  }

  build() {
    if (this.failed) {
      Row({ space: 4 }) {
        Image($r('app.media.ic_public_picture'))
          .width(14)
          .height(14)
          .fillColor($r('app.color.text_primary_contrary'))
        Text(this.shortName())
          .fontSize(Fonts.caption())
          .fontColor($r('app.color.text_primary_contrary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor($r('app.color.brand_pressed'))
      .borderRadius(Dim.radiusS)
    } else {
      // 沙箱路径需要 file:// 方案，纯绝对路径 Image 不认
      Image(`file://${this.path}`)
        .width(168)
        .height(168)
        .objectFit(ImageFit.Cover)
        .borderRadius(Dim.radiusL)
        .alt($r('app.media.ic_public_picture'))
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
        .onClick(() => {
          this.onOpen(this.path);
        })
        .onError(() => {
          this.failed = true;
        })
    }
  }
}
