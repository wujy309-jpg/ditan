/**
 * 通用视觉组件 —— 让五个页面「看起来像同一个应用」
 *
 * 为什么要有这个文件：
 *   诊断发现，v1 的界面之所以「朴素」，很大一部分原因是**每个页面各自手搓卡片**——
 *   同样是「白底 + 16 圆角 + 16 内边距」的容器，在 5 个文件里被抄了 30 多遍，
 *   每抄一遍就会漂移一点（有的加阴影有的不加、有的圆角 14 有的 16）。
 *
 *   把「卡片长什么样」收敛到这里之后：
 *     · 改一处，全应用同步变；
 *     · 页面代码只剩「内容是什么」，不再重复描述「长什么样」。
 *
 * 组件与用途：
 *   HeroCard     页面第一屏的渐变主卡（五个页面统一用它，只换 variant）
 *   SectionCard  带阴影的标准内容卡（含图标标题行）
 *   CardTitle    卡片内的小标题行（不想套整张卡时单独用）
 *   StatTile     三宫格里的「大数字 + 标签」
 *   Chip         胶囊标签 / 筛选器
 *   RankRow      带进度条的分类明细行
 *   RingStat     环形进度（英雄区里用）
 *   EmptyHint    空状态
 */
import {
  Bg, Brand, CatColor, Edge, FontSize, Ink, LineHeight, Radius, Semantic, Space, Weight,
  decoBlob, heroGradient, heroGradientDeep, heroGradientFresh,
  shadowBrand, shadowCard
} from '../common/Theme';
import { Category } from '../model/Models';

// ---------------------------------------------------------------------------
// 类目 → 颜色（图表、标签、进度条共用同一套，保证「同色同义」）
// ---------------------------------------------------------------------------

/** 类目识别色。必须与 Charts.ets 里 pieColors() 的取值一一对应 */
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

/** 类目浅色底 */
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

// ---------------------------------------------------------------------------
// 英雄区：页面第一屏的渐变主卡
// ---------------------------------------------------------------------------

/**
 * @param variant  'brand' 标准绿 / 'deep' 深墨绿（数据页）/ 'fresh' 清爽绿（科普页）
 * @param deco     预留参数（当前实现不再叠加装饰层，原因见 Theme.heroGradient 注释）
 */
@Component
export struct HeroCard {
  @Prop variant: string = 'brand';
  @Prop deco: boolean = true;
  @Prop bottomSpace: number = Space.MD;
  @BuilderParam content: () => void;

  private gradient(): LinearGradientOptions {
    if (this.variant === 'deep') {
      return heroGradientDeep();
    }
    if (this.variant === 'fresh') {
      return heroGradientFresh();
    }
    return heroGradient();
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.XL)
    .linearGradient(this.gradient())
    .borderRadius(Radius.XL)
    // 1px 半透明白描边 —— 让渐变卡的边缘有一道「高光」，像玻璃的厚度
    .border({ width: 1, color: Edge.SHEEN })
    .clip(true)
    .shadow(shadowBrand())
    .margin({ bottom: this.bottomSpace })
  }
}

// ---------------------------------------------------------------------------
// 标准内容卡
// ---------------------------------------------------------------------------

/**
 * 带阴影的内容卡。
 *
 * v1 最大的问题之一：阴影函数定义了却只在 1 个页面调用过 4 次，
 * 其余 30 多张卡片是「贴在背景上的白块」。卡片没有阴影 = 没有层级 = 看起来平。
 * 这里把 shadowCard() 变成卡片的**默认行为**，从机制上杜绝漏加。
 *
 * @param title     标题；空串表示不要标题行
 * @param icon      标题图标；不传则不画（配合 showIcon=false）
 * @param showIcon  是否显示标题图标
 * @param padding   内边距；默认 16
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
  @Prop badgeColor: string = Semantic.ALERT;
  @Prop badgeSoft: string = Semantic.ALERT_SOFT;
  @BuilderParam content: () => void;

  build() {
    Column() {
      if (this.title.length > 0) {
        Row() {
          if (this.showIcon) {
            // 图标底：给图标一个浅色圆角底，比裸图标更有「设计过」的感觉
            Column() {
              Image(this.icon)
                .width(16)
                .height(16)
                .fillColor(this.iconColor)
                .objectFit(ImageFit.Contain)
            }
            .width(28)
            .height(28)
            .borderRadius(Radius.SM)
            .backgroundColor(Bg.SUBTLE)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ right: Space.SM })
          }
          Text(this.title)
            .fontSize(FontSize.SUB_M)
            .fontWeight(Weight.SUBTITLE)
            .fontColor(Ink.L1)
            .layoutWeight(1)
          if (this.badge.length > 0) {
            Text(this.badge)
              .fontSize(FontSize.CAPTION)
              .fontWeight(Weight.SUBTITLE)
              .fontColor(this.badgeColor)
              .backgroundColor(this.badgeSoft)
              .borderRadius(Radius.XS)
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: Space.MD })
      }

      this.content()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(this.inset)
    .backgroundColor(Bg.CARD)
    .borderRadius(Radius.MD)
    .shadow(shadowCard())
    .margin({ bottom: this.bottomSpace })
  }
}

/** 不带外卡的小标题行：用于已经在大卡内部的二级分组 */
@Component
export struct CardTitle {
  @Prop title: string = '';
  @Prop icon: Resource = $r('app.media.ic_leaf');
  @Prop showIcon: boolean = true;
  @Prop iconColor: string = Brand.PRIMARY;

  build() {
    Row() {
      if (this.showIcon) {
        Image(this.icon)
          .width(16)
          .height(16)
          .fillColor(this.iconColor)
          .objectFit(ImageFit.Contain)
          .margin({ right: 6 })
      }
      Text(this.title)
        .fontSize(FontSize.SUB_S)
        .fontWeight(Weight.SUBTITLE)
        .fontColor(Ink.L1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}

// ---------------------------------------------------------------------------
// 数字块
// ---------------------------------------------------------------------------

/**
 * 大数字 + 单位 + 标签。
 *
 * 排版要点（照着做就不会「廉价」）：
 *   · 数字与标签**不同色**（数字用语义色，标签用 Ink.L2），靠色彩拉开层级；
 *   · 单位比数字小两档、且**底部对齐**，不要居中 —— 居中会让数字显得矮；
 *   · 数字不用 Bold 以外的字重，也不用 Display 级（三宫格里 24–26 最稳）。
 */
@Component
export struct StatTile {
  @Prop value: string = '0';
  @Prop unit: string = '';
  @Prop label: string = '';
  @Prop valueColor: string = Brand.PRIMARY;

  build() {
    Column() {
      Row() {
        Text(this.value)
          .fontSize(FontSize.TITLE_M)
          .fontWeight(Weight.DISPLAY)
          .fontColor(this.valueColor)
        if (this.unit.length > 0) {
          Text(this.unit)
            .fontSize(FontSize.BODY_S)
            .fontColor(Ink.L3)
            .margin({ left: 3, bottom: 3 })
        }
      }
      .alignItems(VerticalAlign.Bottom)

      Text(this.label)
        .fontSize(FontSize.BODY_S)
        .fontColor(Ink.L2)
        .margin({ top: 5 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }
}

// ---------------------------------------------------------------------------
// 胶囊
// ---------------------------------------------------------------------------

/** 胶囊标签 / 筛选器。选中态用主色实底，未选中用「白底 + 描边」 */
@Component
export struct Chip {
  @Prop label: string = '';
  @Prop selected: boolean = false;
  @Prop activeColor: string = Brand.PRIMARY;
  onTap: () => void = () => {
  };

  build() {
    Text(this.label)
      .fontSize(FontSize.BODY_M)
      .fontWeight(this.selected ? Weight.SUBTITLE : Weight.BODY)
      .fontColor(this.selected ? Ink.ON_BRAND : Ink.L2)
      .backgroundColor(this.selected ? this.activeColor : Bg.SUBTLE)
      .borderRadius(Radius.FULL)
      .borderWidth(1)
      .borderColor(this.selected ? this.activeColor : Edge.NORMAL)
      .padding({ left: 16, right: 16, top: 7, bottom: 7 })
      .margin({ right: Space.SM, bottom: Space.SM })
      .onClick(() => {
        this.onTap();
      })
  }
}

// ---------------------------------------------------------------------------
// 带进度条的排行行
// ---------------------------------------------------------------------------

/**
 * 分类明细行。
 *
 * v1 是一行「类目名 …… 绿色数字」，四行里有三行是 0，看起来像表格。
 * 这里加了：色点（和饼图/柱状图同色，形成呼应）+ 百分比 + 渐变进度条。
 * 不画比例关系，读者就得自己算 —— 这是「有数据但不好看」的典型。
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
        // 8 圆点：与图表配色一一对应
        Column()
          .width(8)
          .height(8)
          .borderRadius(Radius.FULL)
          .backgroundColor(this.color)
          .margin({ right: Space.SM })

        Text(this.label)
          .fontSize(FontSize.BODY_M)
          .fontColor(Ink.L2)
          .layoutWeight(1)

        Text(this.value)
          .fontSize(FontSize.BODY_M)
          .fontWeight(Weight.SUBTITLE)
          .fontColor(Ink.L1)
        Text(`${this.percent}%`)
          .fontSize(FontSize.BODY_S)
          .fontColor(Ink.L3)
          .width(44)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 进度条：底槽用 6% 的主色，填充用横向渐变
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height(6)
          .borderRadius(Radius.FULL)
          .backgroundColor(Bg.SUBTLE)
        Column()
          .width(`${this.percent}%`)
          .height(6)
          .borderRadius(Radius.FULL)
          .linearGradient({
            angle: 90,
            // 用同色但左端 70% 透明度做「推进感」，避免纯色条的呆板
            colors: [[`#B3${this.color.substring(1)}`, 0.0], [this.color, 1.0]]
          })
      }
      .width('100%')
      .height(6)
      .margin({ top: 7 })
    }
    .width('100%')
    .margin({ bottom: Space.MD })
  }
}

// ---------------------------------------------------------------------------
// 环形进度
// ---------------------------------------------------------------------------

/**
 * 环形进度。
 *
 * API 12 的 Progress 组件只收单色 color，做不出渐变拖尾，
 * 所以这里用 Stack 叠两个 Circle + 一个带扫描渐变的圆环：
 *   底层  —— 半透明白底环
 *   上层  —— 用 Progress(Ring) 画出实际进度（保证与系统动效一致）
 * 中心放内容由调用方通过 BuilderParam 决定。
 */
@Component
export struct RingStat {
  @Prop percent: number = 0;
  @Prop diameter: number = 88;
  @Prop ringWidth: number = 7;
  @Prop trackColor: string = Edge.ON_BRAND;
  @Prop ringColor: string = Ink.ON_BRAND;
  @BuilderParam content: () => void;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Progress({ value: 0, total: 100, type: ProgressType.Ring })
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
      Column() {
        Image(this.icon)
          .width(30)
          .height(30)
          .fillColor(Brand.LIME)
          .objectFit(ImageFit.Contain)
      }
      .width(60)
      .height(60)
      .borderRadius(Radius.FULL)
      .backgroundColor(Brand.MIST)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text(this.title)
        .fontSize(FontSize.SUB_M)
        .fontWeight(Weight.SUBTITLE)
        .fontColor(Ink.L1)
        .margin({ top: Space.MD })
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
    .padding({ top: 28, bottom: 28, left: Space.LG, right: Space.LG })
    .backgroundColor(Bg.CARD)
    .borderRadius(Radius.MD)
    .shadow(shadowCard())
    .alignItems(HorizontalAlign.Center)
  }
}

// ---------------------------------------------------------------------------
// 信息行（我的页 / 同步面板用）
// ---------------------------------------------------------------------------

/** 带图标的「标签 —— 值」行，替代 v1 的纯文字调试面板观感 */
@Component
export struct InfoRow {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop icon: Resource = $r('app.media.ic_check');
  @Prop showIcon: boolean = true;
  @Prop valueColor: string = Ink.L1;
  @Prop showDivider: boolean = false;

  build() {
    Column() {
      Row() {
        if (this.showIcon) {
          Image(this.icon)
            .width(15)
            .height(15)
            .fillColor(Ink.L3)
            .objectFit(ImageFit.Contain)
            .margin({ right: Space.SM })
        }
        Text(this.label)
          .fontSize(FontSize.BODY_M)
          .fontColor(Ink.L2)
          .layoutWeight(1)
        Text(this.value)
          .fontSize(FontSize.BODY_M)
          .fontWeight(Weight.SUBTITLE)
          .fontColor(this.valueColor)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.showDivider) {
        Divider()
          .color(Edge.HAIR)
          .strokeWidth(1)
          .margin({ top: Space.MD })
      }
    }
    .width('100%')
    .padding({ top: 9, bottom: 9 })
  }
}
