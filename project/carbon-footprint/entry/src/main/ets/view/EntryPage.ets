/**
 * 记一笔 —— 主要功能 1：低碳行为核算
 *
 * 流程：选类目 → 选具体行为 → 填数量 → 选日期 → 保存
 * 保存时按「数量 × 因子」算出减排量，同时发放积分。
 *
 * 实现备注（ArkTS/ArkUI 约束）：
 *   1. 不用 @Builder 传值参数渲染选中态——值传递的参数不会触发刷新，
 *      会把「选中的胶囊不高亮」。这里直接内联 ForEach，确保状态变化能刷新。
 *   2. 不使用 `!` 非空断言，改用 EMPTY_FACTOR 兜底对象。
 */
import { CarbonRepository } from '../data/CarbonRepository';
import { factorById, factorsOf } from '../data/FactorLibrary';
import { classify, ClassifyDetail, pickFromGallery, releaseOcr } from '../ai/LowCarbonClassifier';
import {
  Bg, Brand, CatColor, Edge, FontSize, Ink, Radius, Semantic, Space, Weight,
  Motion, buttonGradient, shadowCard, shadowRaised
} from '../common/Theme';
import { HeroCard } from './Common';
import { refreshAllCards } from '../cardentry/CarbonCardAbility';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { resourceManager } from '@kit.LocalizationKit';
import {
  ALL_CATEGORIES,
  BehaviorRecord,
  Category,
  categoryLabel,
  Factor,
  newId,
  round2,
  today
} from '../model/Models';

/**
 * 每日低碳目标（kg CO₂e）。
 * 取 3.0 的依据：按本应用因子库，单人每日通勤改为步行/骑行约可减排 2~4 kg，
 * 这是一个「努力一下能够到」的量级 —— 目标定得太高会让人放弃，太低又没有激励作用。
 */
const DAILY_GOAL: number = 3.0;

/** 兜底因子：未选中任何行为时占位，避免空断言 */
const EMPTY_FACTOR: Factor = {
  id: '',
  category: '',
  name: '',
  unit: '',
  savedPerUnit: 0,
  baseline: '',
  source: ''
};

/**
 * 显式「零阴影」。
 *
 * 为什么需要它：类目格只有**选中**的那一块要浮起来，未选中的必须保持平贴。
 * 而 ArkUI 的属性不能按条件决定「写不写」，只能二选一传值，
 * 所以未选中态需要一个合法的空阴影对象，而不是省略 .shadow()。
 */
function noShadow(): ShadowOptions {
  return {
    radius: 0,
    color: Color.Transparent,
    offsetX: 0,
    offsetY: 0
  };
}

@Component
export struct EntryPage {
  /** 数据版本号，页签切换时由 Index 递增，用于刷新（原因见 SmartService 注释） */
  @Prop @Watch('onVersion') version: number = 0;

  @State category: string = Category.TRAVEL;
  @State factorId: string = '';
  @State amount: string = '';
  @State date: string = today();
  @State hint: string = '';
  @State hintOk: boolean = true;
  @State recent: BehaviorRecord[] = [];
  @State total: number = 0;
  @State todayTotal: number = 0;
  @State weekTotal: number = 0;

  // 创新点 2：端侧 AI 识图
  @State aiBusy: boolean = false;
  @State aiReason: string = '';
  @State aiConfidence: number = 0;
  @State aiApplied: boolean = false;
  @State aiPreview: image.PixelMap | undefined = undefined;

  aboutToAppear(): void {
    this.pickCategory(Category.TRAVEL);
    this.refresh();
  }

  onVersion(): void {
    this.refresh();
  }

  aboutToDisappear(): void {
    releaseOcr();
  }

  /** 拍照/选图 → 端侧识别 → 高置信才预填，低置信交给用户确认 */
  private async doAiRecognize(): Promise<void> {
    if (this.aiBusy) {
      return;
    }
    this.aiBusy = true;
    this.aiReason = '正在识别…';
    this.aiApplied = false;
    try {
      const pm: image.PixelMap | undefined = await pickFromGallery();
      if (pm === undefined) {
        this.aiReason = '';
        return;
      }
      this.aiPreview = pm;

      const rawCtx = this.getUIContext().getHostContext();
      if (rawCtx === undefined) {
        this.aiReason = '拿不到应用上下文';
        return;
      }
      const ctx: common.Context = rawCtx as common.Context;
      const appCtx: common.ApplicationContext = ctx.getApplicationContext();
      const mgr: resourceManager.ResourceManager = appCtx.resourceManager;

      const detail: ClassifyDetail = await classify(mgr, pm);
      this.aiConfidence = detail.suggestion.confidence;
      const parts: string[] = [detail.suggestion.reason];
      if (detail.note.length > 0) {
        parts.push(detail.note);
      }
      this.aiReason = parts.join('　·　');

      // 关键产品设计：只有高置信且因子存在时才预填
      if (detail.suggestion.confidence >= 0.5 && detail.suggestion.factorId.length > 0) {
        const f: Factor | undefined = factorById(detail.suggestion.factorId);
        if (f !== undefined) {
          this.category = f.category;
          this.factorId = f.id;
          this.aiApplied = true;
        }
      }
    } catch (e) {
      this.aiReason = '识别失败，请手动选择';
    } finally {
      this.aiBusy = false;
    }
  }

  private pickCategory(c: string): void {
    this.category = c;
    const list: Factor[] = factorsOf(c);
    this.factorId = list.length > 0 ? list[0].id : '';
  }

  /** 当前因子，未选中时返回 EMPTY_FACTOR */
  private factor(): Factor {
    const f: Factor | undefined = factorById(this.factorId);
    return f === undefined ? EMPTY_FACTOR : f;
  }

  private hasFactor(): boolean {
    return this.factorId.length > 0;
  }

  /** 实时预览：当前输入能减排多少 */
  private preview(): string {
    if (!this.hasFactor()) {
      return '—';
    }
    const amt: number = Number.parseFloat(this.amount);
    if (!(amt > 0)) {
      return '—';
    }
    return `${round2(amt * this.factor().savedPerUnit)} kg CO₂e`;
  }

  private async refresh(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    const list: BehaviorRecord[] = await repo.listBehaviors();
    this.recent = list.slice(0, 5);
    this.total = await repo.totalSaved();

    // 今日与本周：英雄区的环形进度与副数据要用
    const todayStr: string = today();
    let tSum: number = 0;
    let wSum: number = 0;
    const weekAgo: Date = new Date();
    weekAgo.setDate(weekAgo.getDate() - 6);
    for (let i = 0; i < list.length; i++) {
      const r: BehaviorRecord = list[i];
      if (r.date === todayStr) {
        tSum += r.saved;
      }
      const d: Date = new Date(`${r.date}T00:00:00`);
      if (!Number.isNaN(d.getTime()) && d.getTime() >= weekAgo.getTime()) {
        wSum += r.saved;
      }
    }
    this.todayTotal = Math.round(tSum * 100) / 100;
    this.weekTotal = Math.round(wSum * 100) / 100;
  }

  /** 今日目标完成度（0~100），用于环形进度 */
  private goalPercent(): number {
    const p: number = Math.round(this.todayTotal / DAILY_GOAL * 100);
    return p > 100 ? 100 : p;
  }

  /** 类目 → 图标。写成方法而不是全局函数，因为 $r 需要在组件上下文里解析 */
  private categoryIcon(c: string): Resource {
    if (c === Category.ENERGY) {
      return $r('app.media.ic_energy');
    }
    if (c === Category.RECYCLE) {
      return $r('app.media.ic_recycle');
    }
    if (c === Category.FOOD) {
      return $r('app.media.ic_food');
    }
    return $r('app.media.ic_travel');
  }

  /** 类目 → 识别色 */
  private categoryColor(c: string): string {
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

  /** 类目 → 浅色底 */
  private categorySoft(c: string): string {
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

  private async save(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      this.hintOk = false;
      this.hint = '数据层未就绪，请稍候重试';
      return;
    }
    if (!this.hasFactor()) {
      this.hintOk = false;
      this.hint = '请先选择行为类型';
      return;
    }
    const amt: number = Number.parseFloat(this.amount);
    if (!(amt > 0)) {
      this.hintOk = false;
      this.hint = '请输入大于 0 的数量';
      return;
    }

    const f: Factor = this.factor();
    const saved: number = round2(amt * f.savedPerUnit);
    const rec: BehaviorRecord = {
      id: newId(),
      category: f.category,
      factorId: f.id,
      name: f.name,
      amount: amt,
      unit: f.unit,
      saved: saved,
      date: this.date,
      ts: Date.now()
    };

    try {
      const entry = await repo.addBehavior(rec);
      this.hintOk = true;
      this.hint = `已记录：减排 ${saved} kg CO₂e，获得 ${entry.delta} 积分`;
      this.amount = '';
      await this.refresh();

      // 通知桌面卡片刷新，让桌面上立刻反映最新数据。
      // 单独 try/catch：卡片刷新失败绝不能影响记录已经保存成功这件事。
      try {
        const ctx = this.getUIContext().getHostContext();
        if (ctx !== undefined) {
          await refreshAllCards(ctx as common.Context);
        }
      } catch (ce) {
        this.hint = `${this.hint}（桌面卡片刷新失败，不影响记录）`;
      }
    } catch (e) {
      this.hintOk = false;
      this.hint = '保存失败，请重试';
    }
  }

  private async remove(id: string): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    await repo.deleteBehavior(id);
    await this.refresh();
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // ===== 英雄区：主卡（第一级）=====
          // 改用 Common.ets 的 HeroCard：20 内边距 / 32 圆角 / 高光描边 / 品牌色投影 /
          // 装饰色斑都已内置，页面这里只描述「内容是什么」，与看板、积分页保持同一套语言。
          HeroCard({ variant: 'brand' }) {
            Row() {
              Column() {
                Text('累计减排')
                  .fontSize(FontSize.BODY_S)
                  .fontColor(Ink.ON_BRAND_2)
                Row() {
                  Text(`${this.total}`)
                    .fontSize(FontSize.DISPLAY_M)
                    .fontWeight(Weight.DISPLAY)
                    .fontColor(Ink.ON_BRAND)
                  Text('kg')
                    .fontSize(FontSize.SUB_S)
                    .fontColor(Ink.ON_BRAND_2)
                    .margin({ left: 5, bottom: 7 })
                }
                .alignItems(VerticalAlign.Bottom)
                .margin({ top: 2 })

                Text(`CO₂e · 本周 ${this.weekTotal} kg`)
                  .fontSize(FontSize.BODY_S)
                  .fontColor(Ink.ON_BRAND_2)
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              // 环形进度：今日目标完成度。用 Progress 而不是 Canvas ——
              // 官方提示 Canvas 不随 @State 自动重绘，环形进度用 Progress 更省心。
              Stack() {
                Progress({
                  value: this.goalPercent(),
                  total: 100,
                  type: ProgressType.Ring
                })
                  .width(78)
                  .height(78)
                  .color(Ink.ON_BRAND)
                  // 半透明装饰白：进度环底轨，需要露出下面的渐变底，故不取实色令牌
                  .backgroundColor('#40FFFFFF')
                  .style({ strokeWidth: 7 })

                Column() {
                  Row() {
                    Text(`${this.goalPercent()}`)
                      .fontSize(FontSize.TITLE_S)
                      .fontWeight(Weight.SUBTITLE)
                      .fontColor(Ink.ON_BRAND)
                    Text('%')
                      .fontSize(FontSize.CAPTION)
                      .fontColor(Ink.ON_BRAND_2)
                      .margin({ left: 1, bottom: 3 })
                  }
                  .alignItems(VerticalAlign.Bottom)

                  Text('今日目标')
                    .fontSize(FontSize.CAPTION)
                    .fontColor(Ink.ON_BRAND_2)
                    .margin({ top: 1 })
                }
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }
              .width(78)
              .height(78)

              Column()
                .width(1)
                .height(46)
                .backgroundColor(Edge.ON_BRAND)
                .margin({ left: Space.LG, right: Space.LG })

              Column() {
                Text(`${this.recent.length}`)
                  .fontSize(FontSize.TITLE_S)
                  .fontWeight(Weight.SUBTITLE)
                  .fontColor(Ink.ON_BRAND)
                Text('今日记录')
                  .fontSize(FontSize.CAPTION)
                  .fontColor(Ink.ON_BRAND_2)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }

          // 创新点 2：端侧 AI 识图
          Column() {
            Row() {
              Text('端侧 AI 识图')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Ink.L1)
                .layoutWeight(1)
              Text('创新点 2')
                .fontSize(10)
                .fontColor(Semantic.ALERT)
                .backgroundColor(Semantic.ALERT_SOFT)
                .borderRadius(8)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            }
            .width('100%')

            Text('拍一张照片或从相册选图，应用在本机识别低碳行为并自动预填，图片不会上传。')
              .fontSize(11)
              .fontColor(Ink.L3)
              .lineHeight(17)
              .width('100%')
              .margin({ top: 6 })

            if (this.aiPreview !== undefined) {
              Image(this.aiPreview)
                .width('100%')
                .height(120)
                .objectFit(ImageFit.Cover)
                .borderRadius(10)
                .margin({ top: 10 })
            }

            Button(this.aiBusy ? '识别中…' : '拍照 / 选图识别')
              .width('100%')
              .height(40)
              .fontSize(14)
              .backgroundColor(Brand.PRIMARY)
              .margin({ top: 10 })
              .enabled(!this.aiBusy)
              .onClick(() => {
                this.doAiRecognize();
              })

            if (this.aiReason.length > 0) {
              Text(this.aiReason)
                .fontSize(11)
                .fontColor(this.aiApplied ? Brand.PRIMARY : Ink.L3)
                .lineHeight(17)
                .width('100%')
                .margin({ top: 8 })
            }
            if (this.aiApplied) {
              Text('已根据识别结果预填，可在下方修改')
                .fontSize(11)
                .fontColor(Brand.PRIMARY)
                .width('100%')
                .margin({ top: 4 })
            }
          }
          .width('100%')
          .padding(Space.LG)
          .backgroundColor(Bg.CARD)
          .borderRadius(Radius.MD)
          .shadow(shadowCard())
          .margin({ bottom: Space.MD })

          // 1 · 类目
          Column() {
            Text('1 · 选择类目')
              .fontSize(FontSize.SUB_L)
              .fontWeight(Weight.SUBTITLE)
              .fontColor(Ink.L1)
              .width('100%')
              .margin({ bottom: Space.MD })
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(ALL_CATEGORIES, (c: string) => {
                Column() {
                  Image(this.categoryIcon(c))
                    .width(26)
                    .height(26)
                    .fillColor(this.category === c ? Ink.ON_BRAND : this.categoryColor(c))
                    .objectFit(ImageFit.Contain)
                  Text(categoryLabel(c))
                    .fontSize(FontSize.BODY_S)
                    .fontWeight(this.category === c ? Weight.SUBTITLE : Weight.BODY)
                    .fontColor(this.category === c ? Ink.ON_BRAND : Ink.L2)
                    .margin({ top: 7 })
                }
                .width('48%')
                .height(84)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(this.category === c
                  ? this.categoryColor(c)
                  : this.categorySoft(c))
                .borderRadius(Radius.MD)
                // 只有选中的那一块浮起来；未选中态保持平贴的浅色底
                .shadow(this.category === c ? shadowRaised() : noShadow())
                .margin({ bottom: Space.SM })
                .onClick(() => {
                  animateTo(Motion.QUICK, () => {
                    this.pickCategory(c);
                  });
                })
              }, (c: string) => c)
            }
            .width('100%')
          }
          .width('100%')
          .padding(Space.LG)
          .backgroundColor(Bg.CARD)
          .borderRadius(Radius.MD)
          .shadow(shadowCard())
          .margin({ bottom: Space.MD })

          // 2 · 具体行为
          Column() {
            Text('2 · 选择行为')
              .fontSize(FontSize.SUB_L)
              .fontWeight(Weight.SUBTITLE)
              .fontColor(Ink.L1)
              .width('100%')
              .margin({ bottom: Space.MD })
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(factorsOf(this.category), (f: Factor) => {
                Text(f.name)
                  .fontSize(FontSize.BODY_M)
                  .fontWeight(this.factorId === f.id ? Weight.SUBTITLE : Weight.BODY)
                  .fontColor(this.factorId === f.id ? Ink.ON_BRAND : Ink.L2)
                  .backgroundColor(this.factorId === f.id ? Brand.PRIMARY : Bg.SUBTLE)
                  .borderRadius(Radius.FULL)
                  .padding({ left: 16, right: 16, top: 8, bottom: 8 })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.factorId = f.id;
                  })
              }, (f: Factor) => f.id)
            }
            .width('100%')

            if (this.hasFactor()) {
              // 微卡（第三级）：浅底、无阴影、小圆角。用于承托「出处」这类次要但重要的信息。
              Column() {
                Text(`${this.factor().savedPerUnit} kg CO₂e / ${this.factor().unit}`)
                  .fontSize(FontSize.BODY_M)
                  .fontWeight(Weight.SUBTITLE)
                  .fontColor(Brand.DEEP)
                  .width('100%')
                Text(`基准：${this.factor().baseline}`)
                  .fontSize(FontSize.BODY_S)
                  .fontColor(Ink.L2)
                  .width('100%')
                  .margin({ top: 4 })
                Text(`出处：${this.factor().source}`)
                  .fontSize(FontSize.CAPTION)
                  .fontColor(Ink.L3)
                  .width('100%')
                  .margin({ top: 3 })
              }
              .width('100%')
              .padding(Space.MD)
              .backgroundColor(Bg.SUBTLE)
              .borderRadius(Radius.SM)
              .margin({ top: Space.MD })
            }
          }
          .width('100%')
          .padding(Space.LG)
          .backgroundColor(Bg.CARD)
          .borderRadius(Radius.MD)
          .shadow(shadowCard())
          .margin({ bottom: Space.MD })

          // 3 · 数量与日期
          Column() {
            Text('3 · 填写数量与日期')
              .fontSize(FontSize.SUB_L)
              .fontWeight(Weight.SUBTITLE)
              .fontColor(Ink.L1)
              .width('100%')
              .margin({ bottom: Space.MD })

            Row() {
              TextInput({ placeholder: '数量', text: this.amount })
                .type(InputType.NUMBER_DECIMAL)
                .layoutWeight(1)
                .height(44)
                .onChange((v: string) => {
                  this.amount = v;
                })
              Text(this.factor().unit)
                .fontSize(14)
                .fontColor(Ink.L2)
                .margin({ left: 10 })
            }
            .width('100%')

            Row() {
              TextInput({ placeholder: 'YYYY-MM-DD', text: this.date })
                .layoutWeight(1)
                .height(44)
                .onChange((v: string) => {
                  this.date = v;
                })
              Button('今天')
                .fontSize(13)
                .height(36)
                .backgroundColor(Brand.SOFT)
                .fontColor(Brand.PRIMARY)
                .margin({ left: 10 })
                .onClick(() => {
                  this.date = today();
                })
            }
            .width('100%')
            .margin({ top: 10 })

            Row() {
              Text('本次减排')
                .fontSize(13)
                .fontColor(Ink.L2)
              Text(this.preview())
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Brand.PRIMARY)
                .margin({ left: 8 })
            }
            .width('100%')
            .margin({ top: 12 })
          }
          .width('100%')
          .padding(Space.LG)
          .backgroundColor(Bg.CARD)
          .borderRadius(Radius.MD)
          .shadow(shadowCard())
          .margin({ bottom: Space.MD })

          Button('保 存')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor(Ink.ON_BRAND)
            // 官方约束：Button 设渐变前必须把 backgroundColor 置为透明，否则实色底会盖住渐变
            .backgroundColor(Color.Transparent)
            .linearGradient(buttonGradient())
            .borderRadius(Radius.FULL)
            .onClick(() => {
              animateTo(Motion.QUICK, () => {
                this.save();
              });
            })

          if (this.hint.length > 0) {
            Text(this.hint)
              .fontSize(13)
              .fontColor(this.hintOk ? Brand.PRIMARY : Semantic.WARNING)
              .width('100%')
              .margin({ top: 10 })
          }

          // 最近记录
          if (this.recent.length > 0) {
            Column() {
              Text('最近记录')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor(Ink.L1)
                .width('100%')
                .margin({ bottom: 10 })
              ForEach(this.recent, (r: BehaviorRecord) => {
                Row() {
                  Column() {
                    Text(`${r.name}  ${r.amount}${r.unit}`)
                      .fontSize(14)
                      .fontColor(Ink.L1)
                    Text(`${r.date} · ${categoryLabel(r.category)}`)
                      .fontSize(11)
                      .fontColor(Ink.L3)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text(`-${r.saved}`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Brand.PRIMARY)
                  Text('kg')
                    .fontSize(11)
                    .fontColor(Ink.L3)
                    .margin({ left: 2 })

                  Button('删')
                    .fontSize(11)
                    .height(28)
                    .width(40)
                    .backgroundColor(Semantic.WARNING_SOFT)
                    .fontColor(Semantic.WARNING)
                    .borderRadius(Radius.FULL)
                    .margin({ left: 10 })
                    .onClick(() => {
                      this.remove(r.id);
                    })
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
              }, (r: BehaviorRecord) => r.id)
            }
            .width('100%')
            .padding(Space.LG)
            .backgroundColor(Bg.CARD)
            .borderRadius(Radius.MD)
            .shadow(shadowCard())
            .margin({ top: Space.MD })
          }
        }
        .width('100%')
        .padding(16)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}
