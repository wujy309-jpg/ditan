/**
 * 记录 —— 低碳行为明细（分类查询）
 *
 * 为什么单独成页，而不是继续挂在「记一笔」页面底部：
 *   赛题二的「支持分类查询历史记录」是**看板**的要求（折线/柱状/饼图那一行），
 *   查询本身又是「翻旧账」的独立动作。之前把筛选项 + 全量列表直接垒在保存按钮
 *   下面，等于在一条已经五段的录入流程尾部再接一段列表 —— 页面越用越长，
 *   每加一个功能就在底部堆一层，观感上就成了「功能堆」。
 *
 *   现在的信息架构：
 *     记一笔页 —— 只留 3 条「最近记录」+ 行内入口『全部 ›』
 *     看板页   —— 分类占比的每一行可点，直接带着类目跳到这里
 *     本页     —— 整屏明细：类目筛选（一行横滑）+ 全量列表 + 删除
 *
 * 这是「二级页」而不是第六个页签：页签栏放五个已经是上限，
 * 而记录查询是低频的「查」动作，不该占常驻位置。
 */
import { CarbonRepository } from '../data/CarbonRepository';
import {
  ALL_CATEGORIES,
  BehaviorRecord,
  categoryLabel,
  round2
} from '../model/Models';
import { catColor, EmptyHint } from './Common';
import {
  Bg, Brand, Edge, FontSize, Ink, Radius, Rule, Seal, Semantic, Serif, Space, Weight
} from '../common/Theme';

@Component
export struct RecordsPage {
  /** 数据版本号（与其它页一致，仅用于跟随刷新） */
  @Prop version: number = 0;
  /** 进入时的初始类目；空串 = 全部 */
  @Prop initialCategory: string = '';
  /** 关闭回调：整页是 Index 里的一层覆盖，返回交给 Index 收起 */
  onClose: () => void = () => {
  };

  @State filterCat: string = '';
  /** 全量记录 */
  @State all: BehaviorRecord[] = [];
  /** 当前筛选结果 */
  @State shown: BehaviorRecord[] = [];
  /** 当前筛选结果合计 */
  @State sum: number = 0;
  @State ready: boolean = false;

  aboutToAppear(): void {
    this.filterCat = this.initialCategory;
    this.load();
  }

  private async load(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      this.ready = true;
      return;
    }
    this.all = await repo.listBehaviors();
    this.applyFilter();
    this.ready = true;
  }

  private applyFilter(): void {
    const out: BehaviorRecord[] = [];
    let s: number = 0;
    for (let i = 0; i < this.all.length; i++) {
      const r: BehaviorRecord = this.all[i];
      if (this.filterCat.length === 0 || r.category === this.filterCat) {
        out.push(r);
        s += r.saved;
      }
    }
    this.shown = out;
    this.sum = round2(s);
  }

  private pick(cat: string): void {
    this.filterCat = cat;
    this.applyFilter();
  }

  private async remove(id: string): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    await repo.deleteBehavior(id);
    await this.load();
  }

  /** 一条明细：色点 + 日期 + 行为 + 数量 + 减排量 + 删 */
  @Builder
  recordRow(r: BehaviorRecord) {
    Row() {
      // 类目色点：与看板饼图/图例同一套颜色，翻账时还能对得上图
      Column()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(catColor(r.category))
        .margin({ right: 10, top: 6 })

      Column() {
        Text(r.name)
          .fontSize(FontSize.BODY_M)
          .fontColor(Ink.L1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${r.date.substring(5)} · ${r.amount}${r.unit} · ${categoryLabel(r.category)}`)
          .fontSize(FontSize.CAPTION)
          .fontColor(Ink.L3)
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row() {
        Text(`−${r.saved}`)
          .fontSize(FontSize.SUB_S)
          .fontColor(Ink.L1)
          .fontWeight(Weight.SUBTITLE)
          .fontFeature('"tnum" 1')
        Text('kg')
          .fontSize(9)
          .fontColor(Ink.L3)
          .margin({ left: 2, bottom: 3 })
      }
      .alignItems(VerticalAlign.Bottom)

      Text('删')
        .fontSize(FontSize.CAPTION)
        .fontColor(Ink.L4)
        .padding({ left: 12, top: 8, bottom: 8 })
        .onClick(() => {
          this.remove(r.id);
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: Space.LG, right: Space.LG, top: 13, bottom: 13 })
    .border({ width: { bottom: 0.8 }, color: Rule.HAIR })
  }

  build() {
    Column() {
      // ============ 顶栏：返回 + 标题 + 合计 ============
      Row() {
        Text('←')
          .fontSize(18)
          .fontColor(Ink.L1)
          .padding({ right: 14, top: 4, bottom: 4 })
          .onClick(() => {
            this.onClose();
          })

        Column() {
          Text('低 碳 记 录')
            .fontFamily(Serif.FAMILY)
            .fontSize(16)
            .letterSpacing(2)
            .fontColor(Ink.L1)
          Text(this.filterCat.length === 0 ? '全部类目' : categoryLabel(this.filterCat))
            .fontSize(FontSize.CAPTION)
            .fontColor(Ink.L3)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text(`${this.shown.length}`)
            .fontFamily(Serif.FAMILY)
            .fontSize(18)
            .fontColor(Ink.L1)
            .fontFeature('"tnum" 1')
          Text('条记录')
            .fontSize(9)
            .fontColor(Ink.L3)
            .margin({ top: 1 })
        }
        .alignItems(HorizontalAlign.End)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: Space.LG, right: Space.LG, top: 14, bottom: 12 })

      Column().width('100%').height(1).backgroundColor(Rule.STRONG)
      Column().width('100%').height(1).backgroundColor(Rule.HAIR).margin({ top: 2.5 })

      // ============ 类目筛选：五等分账页签 ============
      // 不用胶囊 chips：五个类目横排会顶到屏幕边缘、最后一个被切掉；
      // 换成等分的账页签，选中态用朱砂下划线，和「统计粒度」同一套语言。
      Row() {
        Column() {
          Text('全部')
            .fontSize(FontSize.BODY_S)
            .fontColor(this.filterCat.length === 0 ? Ink.L1 : Ink.L4)
            .fontWeight(this.filterCat.length === 0 ? Weight.SUBTITLE : Weight.BODY)
          Column()
            .width(14)
            .height(2)
            .backgroundColor(this.filterCat.length === 0 ? Seal.RED : Color.Transparent)
            .margin({ top: 6 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 10, bottom: 6 })
        .onClick(() => {
          this.pick('');
        })

        ForEach(ALL_CATEGORIES, (c: string) => {
          Column() {
            Text(categoryLabel(c))
              .fontSize(FontSize.BODY_S)
              .fontColor(this.filterCat === c ? Ink.L1 : Ink.L4)
              .fontWeight(this.filterCat === c ? Weight.SUBTITLE : Weight.BODY)
            Column()
              .width(14)
              .height(2)
              .backgroundColor(this.filterCat === c ? Seal.RED : Color.Transparent)
              .margin({ top: 6 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 10, bottom: 6 })
          .onClick(() => {
            this.pick(c);
          })
        }, (c: string) => c)
      }
      .width('100%')
      .border({ width: { bottom: 1 }, color: Rule.HAIR })

      // ============ 合计 ============
      Row() {
        Text(`合 计 ${this.sum.toFixed(2)} kg CO₂e`)
          .fontSize(FontSize.CAPTION)
          .fontColor(Ink.L2)
          .letterSpacing(0.5)
          .fontFeature('"tnum" 1')
          .layoutWeight(1)
        Text('按时间倒序')
          .fontSize(9)
          .fontColor(Ink.L4)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: Space.LG, right: Space.LG, top: 8, bottom: 4 })

      // ============ 明细列表 ============
      // 用 List 而不是 Scroll+Column：List 能吃掉剩余高度，
      // 筛出 5 条时纸面照样铺到页脚，不会在屏幕中间「撕」出半张纸。
      List() {
        if (!this.ready) {
          ListItem() {
            Row() {
              LoadingProgress()
                .width(28)
                .height(28)
                .color(Brand.PRIMARY)
            }
            .width('100%')
            .height(200)
            .justifyContent(FlexAlign.Center)
          }
        } else if (this.shown.length === 0) {
          ListItem() {
            EmptyHint({
              title: this.filterCat.length === 0 ? '还没有记录' : '这一类还没有记录',
              desc: this.filterCat.length === 0
                ? '去「记一笔」记下第一条低碳行为，这里就会出现明细。'
                : '换个类目看看，或者回「记一笔」补一条。',
              icon: $r('app.media.ic_tab_book')
            })
          }
        } else {
          ForEach(this.shown, (r: BehaviorRecord) => {
            ListItem() {
              this.recordRow(r)
            }
          }, (r: BehaviorRecord) => r.id)

        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Bg.CARD)
      .scrollBar(BarState.Off)

      // ============ 说明 ============
      Row() {
        Text('全部数据存在本机，不上传云端')
          .fontSize(9)
          .fontColor(Ink.L4)
        Blank()
        Text('碳 迹')
          .fontSize(9)
          .fontColor(Seal.RED)
          .letterSpacing(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: Space.LG, right: Space.LG, top: 10, bottom: 14 })
      .border({ width: { top: 0.8 }, color: Rule.HAIR })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Bg.PAGE)
    .backgroundImage($r('app.media.paper_page'), ImageRepeat.XY)
  }
}
