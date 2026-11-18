import { Fonts } from '../../common/Fonts';
import { I18n } from '../../common/I18n';
import { Dim } from '../../common/DesignTokens';
import { ModelInfo } from '../../model/ModelInfo';
import { UsageRecord, UsageStore } from '../../service/db/UsageStore';
import { Logger } from '../../common/Logger';

const TAG: string = 'UsagePage';

/** 筛选范围索引：0 今天 / 1 近7天 / 2 近30天 / 3 全部 */
const RANGE_OPTIONS: string[] = ['usageFilterToday', 'usageFilter7d', 'usageFilter30d', 'usageFilterAll'];
const RANGE_START_OFFSET_MS: number[] = [24 * 3600 * 1000, 7 * 24 * 3600 * 1000, 30 * 24 * 3600 * 1000, Number.MAX_SAFE_INTEGER];

/** 汇总统计 */
class UsageSummary {
  cost: number = 0;
  inMiss: number = 0;
  inHit: number = 0;
  output: number = 0;
  searches: number = 0;
  replies: number = 0;
}

/** 按日聚合行 */
class DayRow {
  key: string = '';
  ts: number = 0;
  cost: number = 0;
  input: number = 0;
  output: number = 0;
  searches: number = 0;
}

/**
 * 用量统计页（NavDestination）：token 消耗与费用估算。
 * 数据来自本地消息库回执 usage，按请求时段峰谷单价本地估算，仅供参考。
 */
@ComponentV2
export struct UsagePage {
  @Local records: UsageRecord[] = [];
  @Local range: number = 2;
  @Local loading: boolean = true;

  aboutToAppear(): void {
    UsageStore.load().then((r: UsageRecord[]) => {
      this.records = r;
      this.loading = false;
    }).catch((err: object) => {
      Logger.warn(TAG, `load failed: ${JSON.stringify(err)}`);
      this.loading = false;
    });
  }

  /** 当前筛选范围内的记录（@Computed：records/range 变化自动重算） */
  @Computed
  get summary(): UsageSummary {
    const s = new UsageSummary();
    const start = Date.now() - RANGE_START_OFFSET_MS[this.range];
    for (const r of this.records) {
      if (r.ts < start) {
        continue;
      }
      s.cost += r.cost;
      s.inMiss += r.inputMiss;
      s.inHit += r.inputHit;
      s.output += r.output;
      s.searches += r.searches;
      s.replies++;
    }
    return s;
  }

  @Computed
  get days(): DayRow[] {
    const map: Record<string, DayRow> = {};
    const start = Date.now() - RANGE_START_OFFSET_MS[this.range];
    for (const r of this.records) {
      if (r.ts < start) {
        continue;
      }
      const d = new Date(r.ts);
      const key = `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
      let row = map[key];
      if (row === undefined) {
        row = new DayRow();
        row.key = key;
        row.ts = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        map[key] = row;
      }
      row.input += r.inputMiss + r.inputHit;
      row.output += r.output;
      row.searches += r.searches;
      row.cost += r.cost;
    }
    const rows: DayRow[] = Object.keys(map).map((k: string): DayRow => map[k]);
    rows.sort((a: DayRow, b: DayRow): number => b.ts - a.ts);
    return rows;
  }

  build() {
    NavDestination() {
      Column() {
        // 筛选
        Row() {
          Blank()
          Select(this.filterOptions())
            .selected(this.range)
            .value(I18n.translate(RANGE_OPTIONS[this.range]))
            .font({ size: Fonts.body2() })
            .fontColor($r('app.color.text_primary'))
            .optionFont({ size: Fonts.body2() })
            .onSelect((idx: number, _value: string) => {
              this.range = idx;
            })
        }
        .width('100%')
        .padding({ left: Dim.pagePadding, right: Dim.pagePadding, top: 4 })

        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(36).height(36).color($r('app.color.brand'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.records.length === 0) {
          Column({ space: 8 }) {
            Text(I18n.translate('usageEmpty'))
              .fontSize(Fonts.body2())
              .fontColor($r('app.color.text_tertiary'))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ left: Dim.pagePadding, right: Dim.pagePadding })
        } else {
          Scroll() {
            Column({ space: 12 }) {
              // 汇总卡
              Column({ space: 6 }) {
                Text(this.fmtCost(this.summary.cost))
                  .fontSize(Fonts.headline6())
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                Text(`${I18n.translate('usageCostTotal')} · ${this.summary.replies} replies`)
                  .fontSize(Fonts.caption())
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')
              .padding(Dim.cardPadding)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusM)

              // 分类明细卡
              Column() {
                this.detailRow(I18n.translate('usageInMiss'), this.fmtTokens(this.summary.inMiss),
                  this.fmtCost(this.costOf(this.summary.inMiss, false, false)))
                this.detailRow(I18n.translate('usageInHit'), this.fmtTokens(this.summary.inHit),
                  this.fmtCost(this.costOf(this.summary.inHit, false, true)))
                this.detailRow(I18n.translate('usageOutput'), this.fmtTokens(this.summary.output),
                  this.fmtCost(this.costOf(this.summary.output, true, false)))
                this.detailRow(I18n.translate('usageSearch'), `${this.summary.searches}`,
                  this.fmtCost(this.summary.searches * ModelInfo.PRICE_SEARCH_PER_CALL))
                Divider().color($r('app.color.list_separator')).strokeWidth(Dim.separator)
                this.detailRow(I18n.translate('usageCostTotal'), '', this.fmtCost(this.summary.cost))
              }
              .padding({ left: Dim.cardPadding, right: Dim.cardPadding })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusM)
              .width('100%')

              // 按日明细
              Text(I18n.translate('usageByDay'))
                .fontSize(Fonts.body2())
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .padding({ left: 4 })
              Column() {
                ForEach(this.days, (d: DayRow) => {
                  Row({ space: 8 }) {
                    Text(this.fmtDay(d.ts))
                      .fontSize(Fonts.caption())
                      .fontColor($r('app.color.text_primary'))
                      .width(72)
                    Text(`${this.fmtTokens(d.input)} / ${this.fmtTokens(d.output)}`)
                      .fontSize(Fonts.caption())
                      .fontColor($r('app.color.text_secondary'))
                      .layoutWeight(1)
                    Text(this.fmtCost(d.cost))
                      .fontSize(Fonts.caption())
                      .fontColor($r('app.color.text_primary'))
                  }
                  .width('100%')
                  .height(36)
                }, (d: DayRow) => d.key)
              }
              .padding({ left: Dim.cardPadding, right: Dim.cardPadding })
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(Dim.radiusM)
              .width('100%')

              // 定价说明
              Text(I18n.translate('usageNote'))
                .fontSize(Fonts.caption())
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .padding({ left: 4, bottom: 24 })
            }
            .padding({ left: Dim.pagePadding, right: Dim.pagePadding, top: Dim.pagePadding, bottom: 20 })
            .constraintSize({ maxWidth: Dim.contentMaxWidth })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          // 内容滚动手势条下方：行滚到底部只被手势条浮层遮住，不在安全区分界线被裁切
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(I18n.translate('usageStats'))
    .backgroundColor($r('app.color.settings_bg'))
    // 灰底延伸进手势条避让区，否则 Navigation 白底在页面底部露条
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  /** 明细行：label 用体内求值保持语言响应式 */
  @Builder
  detailRow(label: string, tokens: string, cost: string) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(Fonts.body2())
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      if (tokens !== '') {
        Text(tokens)
          .fontSize(Fonts.caption())
          .fontColor($r('app.color.text_secondary'))
      }
      Text(cost)
        .fontSize(Fonts.caption())
        .fontColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height(40)
  }

  private filterOptions(): SelectOption[] {
    const arr: SelectOption[] = [];
    for (const k of RANGE_OPTIONS) {
      const o: SelectOption = { value: I18n.translate(k) };
      arr.push(o);
    }
    return arr;
  }

  /** 分类小计：峰谷混合时按时段分别累计（遍历范围内记录） */
  private costOf(totalTokens: number, isOutput: boolean, isCacheHit: boolean): number {
    const start = Date.now() - RANGE_START_OFFSET_MS[this.range];
    let sum = 0;
    for (const r of this.records) {
      if (r.ts < start) {
        continue;
      }
      const tokens = isOutput ? r.output : (isCacheHit ? r.inputHit : r.inputMiss);
      sum += ModelInfo.replyCost(r.peak, isOutput || isCacheHit ? 0 : tokens, isOutput || !isCacheHit ? 0 : tokens,
        isOutput ? tokens : 0, 0);
    }
    return sum;
  }

  private fmtTokens(n: number): string {
    if (n >= 1000000) {
      return `${(n / 1000000).toFixed(2)}M`;
    }
    if (n >= 1000) {
      return `${(n / 1000).toFixed(1)}K`;
    }
    return `${n}`;
  }

  private fmtCost(n: number): string {
    return `¥${n < 1 ? n.toFixed(4) : n.toFixed(2)}`;
  }

  private fmtDay(ts: number): string {
    const d = new Date(ts);
    return `${d.getMonth() + 1}/${d.getDate()}`;
  }
}
