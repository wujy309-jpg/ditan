/**
 * 通用视觉组件 v3 —— 「碳账本」
 *
 * 这一版把「卡片」这个概念从组件里删掉了。页面上的分组不再靠白底圆角块，
 * 而是靠：表头（宋体标题 + 双细线）+ 行（等宽数字 + 引导点线）+ 留白。
 *
 * 组件列表（名字与 v2 一致，页面不用改 import）：
 *   HeroCard     抬头区：墨色封面 + 期次 + 朱印 + 双线
 *   SectionCard  账目段：宋体小标题 + 双线 + 内容
 *   CardTitle    段内二级标题
 *   StatTile     一格数（标签上、数字下、右对齐）
 *   Chip         方角筛选器（选中 = 墨底纸字）
 *   RankRow      分类明细行（引导点线 + 细比例条）
 *   RingStat     环形进度（朱砂）
 *   EmptyHint    空账页提示
 *   InfoRow      账目「项 —— 值」行
 *   Seal         朱砂印章（新）
 *   DottedRule   引导点线（新，内部用）
 */
import {
  Bg, Brand, CatColor, Edge, FontSize, Ink, LineHeight, Radius, Rule, Seal as SealColor, Semantic,
  Serif, Space, Weight, shadowCard
} from '../common/Theme';
import { Category } from '../model/Models';

// ---------------------------------------------------------------------------
// 类目 → 颜色
// ---------------------------------------------------------------------------

export function catColor(c: string): string {
  if (c === Category.ENERGY) {
    return CatColor.ENERGY;
  }
  if (c === Category.RECYCLE) {
    return CatColor.RECYCLE;
  }
  if (c === Category.FOOD) {
    return CatColor.FOOD;
  }
  return CatColor.TRAVEL;
}

export function catSoft(c: string): string {
  if (c === Category.ENERGY) {
    return CatColor.ENERGY_SOFT;
  }
  if (c === Category.RECYCLE) {
    return CatColor.RECYCLE_SOFT;
  }
  if (c === Category.FOOD) {
    return CatColor.FOOD_SOFT;
  }
  return CatColor.TRAVEL_SOFT;
}

/** 等宽数字 —— 账本里所有数字都要用 */
export function tnum(t: TextAttribute): TextAttribute {
  return t.fontFeature('"tnum" 1');
}

// ---------------------------------------------------------------------------
// 朱砂印章
// ---------------------------------------------------------------------------

/**
 * 一枚长方形朱印，两字竖排，轻微倾斜。
 *
 * 为什么要「轻微倾斜」：真正盖出来的章不可能摆正。这个 -5° 是整套界面里
 * 唯一一处「不整齐」，也是让人相信「这是被设计过的」而不是「这是生成的」的细节。
 */
@Component
export struct Seal {
  @Prop text: string = '核减';
  /**
   * > 0 时改盖「连续 N 天」方印。
   * 连续天数是一个人的身份，不是一个统计值 —— 这东西该被盖章，不该只当小字。
   */
  @Prop days: number = 0;
  @Prop sealSize: number = 13;
  @Prop angle: number = -5;

  build() {
    Column() {
      if (this.days > 0) {
        // 2×2 方印：连 / 续 / N / 天
        Column() {
          Row() {
            Text('连')
              .fontFamily(Serif.FAMILY)
              .fontSize(this.sealSize * 0.78)
              .fontColor(SealColor.RED)
            Text('续')
              .fontFamily(Serif.FAMILY)
              .fontSize(this.sealSize * 0.78)
              .fontColor(SealColor.RED)
              .margin({ left: 1 })
          }
          Row() {
            Text(`${this.days}`)
              .fontFamily(Serif.FAMILY)
              .fontSize(this.sealSize * 0.86)
              .fontColor(SealColor.RED)
              .fontFeature('"tnum" 1')
            Text('天')
              .fontFamily(Serif.FAMILY)
              .fontSize(this.sealSize * 0.78)
              .fontColor(SealColor.RED)
              .margin({ left: 1 })
          }
          .margin({ top: 1 })
        }
        .padding(1)
        .border({ width: 0.6, color: SealColor.RED, radius: 0.5 })
      } else {
        Text(this.text.substring(0, 1))
          .fontFamily(Serif.FAMILY)
          .fontSize(this.sealSize)
          .fontColor(SealColor.RED)
        Text(this.text.substring(1, 2))
          .fontFamily(Serif.FAMILY)
          .fontSize(this.sealSize)
          .fontColor(SealColor.RED)
      }
    }
    .width(this.sealSize * (this.days > 0 ? 3.0 : 2.1))
    .height(this.sealSize * (this.days > 0 ? 3.1 : 2.9))
    .justifyContent(FlexAlign.Center)
    .border({ width: 1.2, color: SealColor.RED, radius: 1 })
    .rotate({ angle: this.angle })
    .opacity(0.92)
  }
}

// ---------------------------------------------------------------------------
// 引导点线：账本里「项目 ………… 金额」之间那串点
// ---------------------------------------------------------------------------

/**
 * 用重复的「·」撑满剩余宽度，再裁掉溢出部分。
 * ArkUI 的 Divider 不支持虚线，Shape 的 strokeDashArray 在低版本上行为不一致，
 * 这是最稳的一张牌：一个 Text + layoutWeight(1) + Clip，任何分辨率的真机都一样。
 */
@Component
struct DottedRule {
  @Prop dotColor: string = Rule.DASH;

  build() {
    Text('····································································································')
      .fontSize(10)
      .fontColor(this.dotColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Clip })
      .layoutWeight(1)
      .margin({ left: 6, right: 6 })
      .translate({ y: -2 })
  }
}

// ---------------------------------------------------------------------------
// 抬头区
// ---------------------------------------------------------------------------

/**
 * @param variant  兼容 v2 的调用（brand/deep/fresh），v3 已统一为墨色封面
 * @param deco     兼容参数，不再使用
 * @param period   期次文本（右上角小字，如「2026-10 · 第 6 号」）
 * @param stamp    印章文字，空串表示不盖
 */
@Component
export struct HeroCard {
  @Prop variant: string = 'brand';
  @Prop deco: boolean = true;
  @Prop bottomSpace: number = Space.MD;
  @Prop period: string = '';
  @Prop stamp: string = '碳迹';
  /** > 0 时右上角盖「连续 N 天」方印（没有连续数据时才显示「碳迹」二字章） */
  @Prop days: number = 0;
  @BuilderParam content: () => void;

  build() {
    Column() {
      // —— 抬头：刊名 + 期次 + 印
      Row() {
        Text('碳 迹 · 减 排 账')
          .fontFamily(Serif.FAMILY)
          .fontSize(11)
          .fontColor(Ink.ON_BRAND_3)
          .letterSpacing(1)

        Blank()

        if (this.period.length > 0) {
          Text(this.period)
            .fontFamily(Serif.FAMILY)
            .fontSize(10)
            .fontColor(Ink.ON_BRAND_3)
            .letterSpacing(0.5)
            .margin({ right: 10 })
        }

        if (this.days > 0) {
          Seal({ text: this.stamp, days: this.days, sealSize: 11 })
        } else if (this.stamp.length > 0) {
          Seal({ text: this.stamp, sealSize: 11 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .height(34)

      // —— 双线：账簿表头的标准画法（粗线在上、细线在下）
      Column()
        .width('100%')
        .height(1)
        .backgroundColor('#3A3226')
        .margin({ top: 10 })
      Column()
        .width('100%')
        .height(1)
        .backgroundColor('#2A241B')
        .margin({ top: 2.5, bottom: 16 })

      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: Space.XL, right: Space.XL, top: 10, bottom: Space.XL })
    .backgroundColor(Ink.DECK)
    // 墨面上的颗粒：像压过的深色卡纸，不是一块纯色
    .backgroundImage($r('app.media.ink_card'), ImageRepeat.XY)
    .borderRadius(Radius.MD)
    .margin({ bottom: this.bottomSpace })
  }
}

// ---------------------------------------------------------------------------
// 账目段
// ---------------------------------------------------------------------------

/**
 * @param title     段标题（宋体）
 * @param icon      兼容 v2；v3 不再画图标，改画一道朱砂短横
 * @param showIcon  兼容参数
 * @param inset     内边距；v3 默认 16
 * @param badge     右上角小字（如「共 6 条」），方角、朱砂
 */
@Component
export struct SectionCard {
  @Prop title: string = '';
  @Prop icon: Resource = $r('app.media.ic_leaf');
  @Prop showIcon: boolean = false;
  @Prop iconColor: string = Brand.PRIMARY;
  @Prop inset: number = Space.LG;
  @Prop bottomSpace: number = Space.MD;
  @Prop badge: string = '';
  @Prop badgeColor: string = SealColor.RED;
  @Prop badgeSoft: string = SealColor.RED_SOFT;
  @BuilderParam content: () => void;

  build() {
    Column() {
      if (this.title.length > 0) {
        Row() {
          // 表头前的一小段朱砂 —— 像账页上的栏目索引
          Column()
            .width(9)
            .height(2)
            .backgroundColor(SealColor.RED)
            .margin({ right: 7 })

          Text(this.title)
            .fontFamily(Serif.FAMILY)
            .fontSize(15)
            .fontColor(Ink.L1)
            .letterSpacing(0.8)
            .layoutWeight(1)

          if (this.badge.length > 0) {
            Text(this.badge)
              .fontSize(FontSize.CAPTION)
              .fontColor(this.badgeColor)
              .letterSpacing(0.5)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .border({ width: 0.8, color: this.badgeColor, radius: 1 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 8 })

        // 双线分隔：账本每个栏目之间都这么画
        Column().width('100%').height(1).backgroundColor(Rule.STRONG)
        Column().width('100%').height(1).backgroundColor(Rule.HAIR).margin({ top: 2.5, bottom: 12 })
      }

      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: this.inset, right: this.inset, top: 14, bottom: 12 })
    .backgroundColor(Bg.CARD)
    // 纸纹：17 级左右的暖褐颗粒，肉眼几乎看不出，但「不是纯色」
    .backgroundImage($r('app.media.paper_card'), ImageRepeat.XY)
    .borderRadius(Radius.MD)
    .margin({ bottom: this.bottomSpace })
  }
}

/** 段内二级小标题 */
@Component
export struct CardTitle {
  @Prop title: string = '';
  @Prop icon: Resource = $r('app.media.ic_leaf');
  @Prop showIcon: boolean = true;
  @Prop iconColor: string = Brand.PRIMARY;

  build() {
    Row() {
      Text(this.title)
        .fontFamily(Serif.FAMILY)
        .fontSize(FontSize.BODY_M)
        .fontColor(Ink.L2)
        .letterSpacing(0.6)
        .layoutWeight(1)
      Text('—')
        .fontSize(FontSize.CAPTION)
        .fontColor(Ink.L4)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 8 })
  }
}

// ---------------------------------------------------------------------------
// 一格数
// ---------------------------------------------------------------------------

/**
 * 标签在上、数值在下、整体左对齐 —— 印刷表格里「指标 + 数值」的标准排法。
 * 数字必须 tnum，否则每格宽度会随数字变化而抖动。
 */
@Component
export struct StatTile {
  @Prop value: string = '0';
  @Prop unit: string = '';
  @Prop label: string = '';
  @Prop valueColor: string = Ink.L1;

  build() {
    Column() {
      Text(this.label)
        .fontSize(FontSize.CAPTION)
        .fontColor(Ink.L3)
        .letterSpacing(0.8)
        .width('100%')

      Row() {
        Text(this.value)
          .fontSize(FontSize.TITLE_M)
          .fontWeight(Weight.DISPLAY)
          .fontColor(this.valueColor)
          .fontFeature('"tnum" 1')
        if (this.unit.length > 0) {
          Text(this.unit)
            .fontSize(FontSize.CAPTION)
            .fontColor(Ink.L3)
            .margin({ left: 2, bottom: 3 })
        }
      }
      .alignItems(VerticalAlign.Bottom)
      .width('100%')
      .margin({ top: 2 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 0 })
  }
}

// ---------------------------------------------------------------------------
// 筛选器
// ---------------------------------------------------------------------------

/** 方角筛选器。选中 = 墨底纸字，未选中 = 纸底墨字 + 细框。没有胶囊。 */
@Component
export struct Chip {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  @Prop activeColor: string = '';
  onTap: () => void = () => {
  };

  build() {
    Text(this.label)
      .fontSize(FontSize.BODY_S)
      .letterSpacing(0.5)
      .fontColor(this.selected ? Ink.ON_BRAND : Ink.L2)
      .backgroundColor(this.selected ? Ink.L1 : Color.Transparent)
      .borderRadius(Radius.XS)
      .borderWidth(0.8)
      .borderColor(this.selected ? Ink.L1 : Rule.HAIR)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .margin({ right: Space.SM, bottom: Space.SM })
      .onClick(() => {
        this.onTap();
      })
  }
}

// ---------------------------------------------------------------------------
// 分类明细行
// ---------------------------------------------------------------------------

/**
 * 一行账目：色标 + 名称 + 引导点线 + 数值 + 百分比，下面压一条 3vp 的比例条。
 * 点线是这套界面的签名元素 —— 它把「名称」和「金额」在视觉上连成一行账，
 * 而不是两个各说各话的文本。
 */
@Component
export struct RankRow {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop percent: number = 0;
  @Prop color: string = Brand.PRIMARY;

  build() {
    Column() {
      Row() {
        Column()
          .width(6)
          .height(6)
          .backgroundColor(this.color)
          .margin({ right: 7 })

        Text(this.label)
          .fontSize(FontSize.BODY_M)
          .fontColor(Ink.L2)
          .letterSpacing(0.4)

        DottedRule({ dotColor: Rule.DASH })

        Text(this.value)
          .fontSize(FontSize.BODY_M)
          .fontColor(Ink.L1)
          .fontFeature('"tnum" 1')

        Text(`${this.percent}%`)
          .fontSize(FontSize.CAPTION)
          .fontColor(Ink.L3)
          .fontFeature('"tnum" 1')
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height(3)
          .backgroundColor(Bg.SUNKEN)
        Column()
          .width(`${this.percent}%`)
          .height(3)
          .backgroundColor(this.color)
      }
      .width('100%')
      .height(3)
      .margin({ top: 6 })
    }
    .width('100%')
    .margin({ bottom: Space.MD })
  }
}

// ---------------------------------------------------------------------------
// 环形进度
// ---------------------------------------------------------------------------

@Component
export struct RingStat {
  @Prop percent: number = 0;
  @Prop diameter: number = 88;
  @Prop ringWidth: number = 3;
  @Prop trackColor: string = Edge.ON_BRAND;
  @Prop ringColor: string = SealColor.RED;
  @BuilderParam content: () => void;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Progress({ value: 100, total: 100, type: ProgressType.Ring })
        .width(this.diameter)
        .height(this.diameter)
        .color(this.trackColor)
        .style({ strokeWidth: this.ringWidth, enableSmoothEffect: false })
      Progress({ value: this.percent, total: 100, type: ProgressType.Ring })
        .width(this.diameter)
        .height(this.diameter)
        .color(this.ringColor)
        .style({ strokeWidth: this.ringWidth, enableSmoothEffect: true })
      Column() {
        this.content()
      }
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width(this.diameter)
    .height(this.diameter)
  }
}

// ---------------------------------------------------------------------------
// 空状态
// ---------------------------------------------------------------------------

@Component
export struct EmptyHint {
  @Prop title: string = '还没有数据';
  @Prop desc: string = '';
  @Prop icon: Resource = $r('app.media.ic_leaf');

  build() {
    Column() {
      Text('——')
        .fontFamily(Serif.FAMILY)
        .fontSize(15)
        .fontColor(Ink.L4)
        .letterSpacing(2)

      Text(this.title)
        .fontFamily(Serif.FAMILY)
        .fontSize(FontSize.BODY_M)
        .fontColor(Ink.L2)
        .letterSpacing(1)
        .margin({ top: 8 })

      if (this.desc.length > 0) {
        Text(this.desc)
          .fontSize(FontSize.BODY_S)
          .fontColor(Ink.L3)
          .lineHeight(LineHeight.BODY_S)
          .textAlign(TextAlign.Center)
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding({ top: 26, bottom: 26, left: Space.LG, right: Space.LG })
    .backgroundColor(Color.Transparent)
    .alignItems(HorizontalAlign.Center)
  }
}

// ---------------------------------------------------------------------------
// 账目行
// ---------------------------------------------------------------------------

/** 「项 —— 值」：左名称、右数值，中间点线。我的页 / 同步面板用。 */
@Component
export struct InfoRow {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop icon: Resource = $r('app.media.ic_check');
  @Prop showIcon: boolean = false;
  @Prop valueColor: string = Ink.L1;
  @Prop showDivider: boolean = false;

  build() {
    Column() {
      Row() {
        Text(this.label)
          .fontSize(FontSize.BODY_S)
          .fontColor(Ink.L3)
          .letterSpacing(0.4)

        DottedRule({ dotColor: Rule.DASH })

        Text(this.value)
          .fontSize(FontSize.BODY_S)
          .fontColor(this.valueColor)
          .fontFeature('"tnum" 1')
          .textAlign(TextAlign.End)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.showDivider) {
        Divider()
          .color(Rule.HAIR)
          .strokeWidth(1)
          .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }
}
