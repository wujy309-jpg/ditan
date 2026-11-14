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
import {
  classify,
  ClassifyDetail,
  pickFromGallery,
  pickFromPhonePhoto,
  releaseOcr
} from '../ai/LowCarbonClassifier';
import {
  Bg, Brand, CatColor, Edge, FontSize, Ink, Radius, Rule, Seal, Semantic, Serif, Space, Weight,
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

/** 单次记录的数量上限：100000 只是「大到不可能」，用来挡住无穷大与误粘贴 */
const AMOUNT_MAX: number = 100000;

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
  /**
   * 打开「碳迹记录」明细页。
   * 明细是整屏二级页（在 Index 里覆盖），本页只保留 3 条最近记录 + 一个行内入口。
   * 这样录入页的节奏是固定的五段，不会每加一个功能就在保存按钮下面再垒一层。
   */
  onOpenRecords: (cat: string) => void = () => {
  };

  @State category: string = Category.TRAVEL;
  @State factorId: string = '';
  @State amount: string = '';
  @State date: string = today();
  @State hint: string = '';
  @State hintOk: boolean = true;
  @State recent: BehaviorRecord[] = [];
  /** 记录总条数。不能拿 recent.length 充数 —— recent 被截断过，
   *  一旦记录超过 3 条，刊头就会永远显示「共 3 条」，与看板页的条数打架。 */
  @State count: number = 0;
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

  /** 拍照/选图（系统相册）→ 端侧识别 */
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
      await this.recognizePixelMap(pm);
    } catch (e) {
      this.aiReason = '识别失败，请手动选择';
    } finally {
      this.aiBusy = false;
    }
  }

  /**
   * 手机取图 → 端侧识别。
   *
   * 模拟器没有相机应用（com.huawei.hmos.camera 不存在），
   * 所以「拍照」这一步交给手机：手机在局域网页面里拍，
   * 电脑把照片推到本机固定路径，这里只做一次**本地文件读取**再推理。
   * 图片不经过网络、不上传，仍然是端侧推理。
   */
  private async doAiRecognizeFromPhone(): Promise<void> {
    if (this.aiBusy) {
      return;
    }
    this.aiBusy = true;
    this.aiReason = '正在读取手机照片…';
    this.aiApplied = false;
    try {
      const pm: image.PixelMap | undefined = await pickFromPhonePhoto();
      if (pm === undefined) {
        this.aiReason = '还没收到手机照片 —— 先在手机上的远程页面拍照送达';
        return;
      }
      await this.recognizePixelMap(pm);
    } catch (e) {
      this.aiReason = '手机照片识别失败，请手动选择';
    } finally {
      this.aiBusy = false;
    }
  }

  /** 统一的识别 + 预填后处理（相册、手机取图共用一条管线） */
  private async recognizePixelMap(pm: image.PixelMap): Promise<void> {
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

  /**
   * 解析输入框的数量。
   * 三个边界一起挡：非数 / Infinity（1e999 这类）/ 超过上限。
   * 原来只判 `amt > 0`，Infinity 能一路存进账本并同步到另一台设备，
   * 图表上表现为一根顶到天的柱子，且只能靠删记录找回。
   */
  private inputAmount(): number {
    const amt: number = Number.parseFloat(this.amount);
    if (!(amt > 0) || !Number.isFinite(amt) || amt > AMOUNT_MAX) {
      return 0;
    }
    return amt;
  }

  /** 实时预览：当前输入能减排多少 */
  private preview(): string {
    if (!this.hasFactor()) {
      return '—';
    }
    const amt: number = this.inputAmount();
    if (!(amt > 0)) {
      return '—';
    }
    return `${round2(amt * this.factor().savedPerUnit)}`;
  }

  /** 预览是否有有效数值（决定「本次减排」右侧的单位块要不要画） */
  private hasPreview(): boolean {
    return this.preview() !== '—';
  }

  /**
   * 今日目标的一句话提示。
   * 与看板页 todayLine() 同款 —— 两页刊头必须等高，否则切页签时顶部会跳一下。
   */
  private todayLine(): string {
    if (this.todayTotal >= DAILY_GOAL) {
      return '今日额度记满，明天继续。';
    }
    if (this.todayTotal <= 0) {
      return '今天还没开张 —— 记一笔，账上就有了。';
    }
    return `还差 ${(DAILY_GOAL - this.todayTotal).toFixed(2)} kg，再记一笔就够。`;
  }

  private async refresh(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    const list: BehaviorRecord[] = await repo.listBehaviors();
    // 只留 3 条：本页是「录入」，不是「翻阅」。全量明细在 RecordsPage。
    this.recent = list.slice(0, 3);
    this.count = list.length;
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
    const amt: number = this.inputAmount();
    if (!(amt > 0)) {
      this.hintOk = false;
      this.hint = `请输入 0 到 ${AMOUNT_MAX} 之间的数量`;
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

  /** 账目段标题：序号 + 宋体标题 + 双线 */
  @Builder
  secHead(no: string, title: string) {
    Row() {
      Text(no)
        .fontFamily(Serif.FAMILY)
        .fontSize(10)
        .fontColor(Seal.RED)
        .letterSpacing(1)
        .width(24)
      Text(title)
        .fontFamily(Serif.FAMILY)
        .fontSize(15)
        .fontColor(Ink.L1)
        .letterSpacing(2)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 7 })

    Column().width('100%').height(1).backgroundColor(Rule.STRONG)
    Column().width('100%').height(1).backgroundColor(Rule.HAIR).margin({ top: 2, bottom: 12 })
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // ===== 抬头：本期减排 =====
          HeroCard({ variant: 'brand', period: `${today()}`, stamp: '碳迹' }) {
            Column() {
              Text('累 计 减 排')
                .fontSize(10)
                .fontColor(Ink.ON_BRAND_3)
                .letterSpacing(3)
                .width('100%')

              Row() {
                Text(this.total.toFixed(2))
                  .fontFamily(Serif.FAMILY)
                  .fontSize(52)
                  .fontColor(Ink.ON_BRAND)
                  .fontFeature('"tnum" 1')
                  .letterSpacing(1)
                Column() {
                  Text('kg')
                    .fontSize(12)
                    .fontColor(Ink.ON_BRAND_2)
                  Text('CO₂e')
                    .fontSize(9)
                    .fontColor(Ink.ON_BRAND_3)
                    .margin({ top: 1 })
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 7, bottom: 12 })
              }
              .alignItems(VerticalAlign.Bottom)
              .width('100%')

              Text(`折合 ${(this.total / 18.3).toFixed(1)} 棵树·年`)
                .fontSize(11)
                .fontColor(Ink.ON_BRAND_3)
                .width('100%')
                .margin({ top: 2 })

              // 今日目标：一条 2vp 的墨色进度线，比圆环更「账」
              Stack({ alignContent: Alignment.Start }) {
                Column()
                  .width('100%')
                  .height(2)
                  .backgroundColor('#33F7F2E6')
                Column()
                  .width(`${this.goalPercent()}%`)
                  .height(2)
                  .backgroundColor(Seal.RED)
              }
              .width('100%')
              .height(2)
              .margin({ top: 18 })

              Row() {
                Text('今日目标')
                  .fontSize(10)
                  .fontColor(Ink.ON_BRAND_3)
                  .letterSpacing(1)
                Text(`${this.todayTotal.toFixed(2)} / ${DAILY_GOAL.toFixed(2)} kg`)
                  .fontSize(11)
                  .fontColor(Ink.ON_BRAND_2)
                  .fontFeature('"tnum" 1')
                  .margin({ left: 8 })
                Blank()
                Text(`共 ${this.count} 条`)
                  .fontSize(10)
                  .fontColor(Ink.ON_BRAND_3)
                  .fontFeature('"tnum" 1')
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: 8 })

              // 与看板页同款的一句提示：两页刊头等高，切页签时顶部不跳
              Text(this.todayLine())
                .fontSize(11)
                .fontColor(Ink.ON_BRAND_2)
                .lineHeight(18)
                .width('100%')
                .margin({ top: 10 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // ===== 02 端侧识图 =====
          Column() {
            this.secHead('02', '端 侧 识 图')

            Text('从相册选图，或用手机拍照送进来 —— 应用在本机识别低碳行为并自动预填，图片不会上传。')
              .fontSize(12)
              .fontColor(Ink.L3)
              .lineHeight(19)
              .width('100%')

            if (this.aiPreview !== undefined) {
              Image(this.aiPreview)
                .width('100%')
                .height(132)
                .objectFit(ImageFit.Cover)
                .borderRadius(Radius.XS)
                .margin({ top: 10 })
            }

            Row() {
              Text(this.aiBusy ? '识 别 中 …' : '拍 照 / 选 图')
                .fontSize(13)
                .letterSpacing(2)
                .fontColor(this.aiBusy ? Ink.L4 : Ink.L1)
              Blank()
              Text('→')
                .fontSize(14)
                .fontColor(this.aiBusy ? Ink.L4 : Ink.L1)
            }
            .width('100%')
            .height(44)
            .padding({ left: 14, right: 14 })
            .border({ width: 1, color: this.aiBusy ? Rule.HAIR : Ink.L1, radius: Radius.XS })
            .margin({ top: 12 })
            .onClick(() => {
              if (!this.aiBusy) {
                this.doAiRecognize();
              }
            })

            // 模拟器没有相机应用：拍照这一步交给手机，照片由电脑推到本机后本地读取
            Row() {
              Text('手 机 取 图')
                .fontSize(13)
                .letterSpacing(2)
                .fontColor(this.aiBusy ? Ink.L4 : Ink.L2)
              Blank()
              Text('⇢')
                .fontSize(14)
                .fontColor(this.aiBusy ? Ink.L4 : Ink.L2)
            }
            .width('100%')
            .height(44)
            .padding({ left: 14, right: 14 })
            .border({ width: 1, color: this.aiBusy ? Rule.HAIR : Rule.HAIR, radius: Radius.XS })
            .margin({ top: 8 })
            .onClick(() => {
              if (!this.aiBusy) {
                this.doAiRecognizeFromPhone();
              }
            })

            if (this.aiReason.length > 0) {
              Text(this.aiReason)
                .fontSize(11)
                .fontColor(this.aiApplied ? Seal.RED : Ink.L3)
                .lineHeight(17)
                .width('100%')
                .margin({ top: 8 })
            }
            if (this.aiApplied) {
              Text('已根据识别结果预填，可在下方修改')
                .fontSize(11)
                .fontColor(Seal.RED)
                .width('100%')
                .margin({ top: 4 })
            }
          }
          .width('100%')
          .padding({ left: Space.LG, right: Space.LG, top: 14, bottom: 14 })
          .backgroundColor(Bg.CARD)
          .borderRadius(Radius.MD)
          .margin({ bottom: Space.MD })

          // ===== 03 选择类目（账目行）=====
          Column() {
            this.secHead('03', '选 择 类 目')

            ForEach(ALL_CATEGORIES, (c: string) => {
              Row() {
                Column()
                  .width(2)
                  .height(22)
                  .backgroundColor(this.category === c ? Seal.RED : Color.Transparent)
                  .margin({ right: 12 })

                Image(this.categoryIcon(c))
                  .width(16)
                  .height(16)
                  .fillColor(this.category === c ? Ink.L1 : this.categoryColor(c))
                  .objectFit(ImageFit.Contain)
                  .margin({ right: 10 })

                Text(categoryLabel(c))
                  .fontSize(15)
                  .letterSpacing(1)
                  .fontWeight(this.category === c ? Weight.SUBTITLE : Weight.BODY)
                  .fontColor(this.category === c ? Ink.L1 : Ink.L2)
                  .layoutWeight(1)

                Text(`${factorsOf(c).length} 项`)
                  .fontSize(11)
                  .fontColor(Ink.L4)
                  .fontFeature('"tnum" 1')
                  .margin({ right: 10 })

                Text(this.category === c ? '●' : '○')
                  .fontSize(10)
                  .fontColor(this.category === c ? Seal.RED : Ink.L4)
              }
              .width('100%')
              .height(48)
              .alignItems(VerticalAlign.Center)
              .border({ width: { bottom: 1 }, color: Rule.HAIR })
              .onClick(() => {
                animateTo(Motion.QUICK, () => {
                  this.pickCategory(c);
                });
              })
            }, (c: string) => c)
          }
          .width('100%')
          .padding({ left: Space.LG, right: Space.LG, top: 14, bottom: 6 })
          .backgroundColor(Bg.CARD)
          .borderRadius(Radius.MD)
          .margin({ bottom: Space.MD })

          // ===== 04 选择行为 =====
          Column() {
            this.secHead('04', '选 择 行 为')

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(factorsOf(this.category), (f: Factor) => {
                Text(f.name)
                  .fontSize(13)
                  .letterSpacing(0.5)
                  .fontColor(this.factorId === f.id ? Ink.ON_BRAND : Ink.L2)
                  .backgroundColor(this.factorId === f.id ? Ink.L1 : Color.Transparent)
                  .borderRadius(Radius.XS)
                  .borderWidth(0.8)
                  .borderColor(this.factorId === f.id ? Ink.L1 : Rule.HAIR)
                  .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.factorId = f.id;
                  })
              }, (f: Factor) => f.id)
            }
            .width('100%')

            if (this.hasFactor()) {
              Column() {
                Row() {
                  Text('因子')
                    .fontSize(10)
                    .fontColor(Ink.L3)
                    .letterSpacing(1)
                  Blank()
                  Text(`${this.factor().savedPerUnit} kg CO₂e / ${this.factor().unit}`)
                    .fontSize(13)
                    .fontColor(Ink.L1)
                    .fontFeature('"tnum" 1')
                }
                .width('100%')

                Text(`基准 · ${this.factor().baseline}`)
                  .fontSize(11)
                  .fontColor(Ink.L2)
                  .width('100%')
                  .margin({ top: 6 })
                Text(`出处 · ${this.factor().source}`)
                  .fontSize(10)
                  .fontColor(Ink.L3)
                  .width('100%')
                  .margin({ top: 3 })
              }
              .width('100%')
              .padding({ top: 10, bottom: 10 })
              .margin({ top: 6 })
              .border({ width: { top: 1, bottom: 1 }, color: Rule.HAIR })
            }
          }
          .width('100%')
          .padding({ left: Space.LG, right: Space.LG, top: 14, bottom: 14 })
          .backgroundColor(Bg.CARD)
          .borderRadius(Radius.MD)
          .margin({ bottom: Space.MD })

          // ===== 05 数量与日期 =====
          Column() {
            this.secHead('05', '数 量 与 日 期')

            Row() {
              TextInput({ placeholder: '0.00', text: this.amount })
                .type(InputType.NUMBER_DECIMAL)
                .placeholderColor(Ink.L4)
                .layoutWeight(1)
                .height(40)
                .padding({ left: 0 })
                .backgroundColor(Color.Transparent)
                .borderRadius(0)
                .border({ width: { bottom: 1 }, color: Rule.STRONG })
                .fontSize(20)
                .fontFeature('"tnum" 1')
                .onChange((v: string) => {
                  this.amount = v;
                })
              Text(this.factor().unit)
                .fontSize(12)
                .fontColor(Ink.L3)
                .margin({ left: 10 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
            .margin({ top: 4 })

            Row() {
              TextInput({ placeholder: 'YYYY-MM-DD', text: this.date })
                .placeholderColor(Ink.L4)
                .layoutWeight(1)
                .height(40)
                .padding({ left: 0 })
                .backgroundColor(Color.Transparent)
                .borderRadius(0)
                .border({ width: { bottom: 1 }, color: Rule.HAIR })
                .fontSize(14)
                .fontFeature('"tnum" 1')
                .onChange((v: string) => {
                  this.date = v;
                })
              Text('今 天')
                .fontSize(11)
                .letterSpacing(1)
                .fontColor(Seal.RED)
                .padding({ left: 10, top: 6, bottom: 6 })
                .onClick(() => {
                  this.date = today();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
            .margin({ top: 14 })

            Row() {
              Text('本 次 减 排')
                .fontSize(11)
                .fontColor(Ink.L3)
                .letterSpacing(1)
              Blank()
              Text(this.preview())
                .fontFamily(Serif.FAMILY)
                .fontSize(24)
                .fontColor(Ink.L1)
                .fontFeature('"tnum" 1')
              // 单位只画一次。原来 preview() 自己就带「kg CO₂e」，这里又补了一个
              // 小号「kg」，渲染出来是「1.17 kg CO₂e kg」—— 截图里能直接看到。
              if (this.hasPreview()) {
                Column() {
                  Text('kg')
                    .fontSize(9)
                    .fontColor(Ink.L3)
                  Text('CO₂e')
                    .fontSize(8)
                    .fontColor(Ink.L4)
                    .margin({ top: 1 })
                }
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 4, bottom: 4 })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Bottom)
            .margin({ top: 20 })
          }
          .width('100%')
          .padding({ left: Space.LG, right: Space.LG, top: 14, bottom: 16 })
          .backgroundColor(Bg.CARD)
          .borderRadius(Radius.MD)
          .margin({ bottom: Space.MD })

          // ===== 保存 =====
          Button('保 存', { type: ButtonType.Normal })
            .width('100%')
            .height(50)
            .fontSize(15)
            .fontColor(Ink.ON_BRAND)
            .backgroundColor(Ink.L1)
            .borderRadius(Radius.XS)
            .onClick(() => {
              animateTo(Motion.QUICK, () => {
                this.save();
              });
            })

          if (this.hint.length > 0) {
            Text(this.hint)
              .fontSize(11)
              .fontColor(this.hintOk ? Brand.PRIMARY : Semantic.WARNING)
              .letterSpacing(0.5)
              .width('100%')
              .margin({ top: 10 })
          }

          // ===== 最近记录 =====
          // 只露 3 条 + 一个行内入口『全部 ›』。
          // 筛选与全量列表都搬去了独立的 RecordsPage —— 录入页保持「抬头 + 01~05 + 保存」
          // 这条固定节奏，不再往保存按钮下面一层层加功能。
          if (this.count > 0) {
            Column() {
              Row() {
                Text('06')
                  .fontFamily(Serif.FAMILY)
                  .fontSize(10)
                  .fontColor(Seal.RED)
                  .letterSpacing(1)
                  .width(24)
                Text('最 近 记 录')
                  .fontFamily(Serif.FAMILY)
                  .fontSize(15)
                  .fontColor(Ink.L1)
                  .letterSpacing(2)
                Text(`共 ${this.count} 条`)
                  .fontSize(9)
                  .fontColor(Ink.L4)
                  .fontFeature('"tnum" 1')
                  .margin({ left: 8 })
                  .layoutWeight(1)
                Text('全部 ›')
                  .fontSize(10)
                  .fontColor(Ink.L3)
                  .letterSpacing(0.5)
                  .padding({ left: 8, top: 4, bottom: 4 })
                  .onClick(() => {
                    this.onOpenRecords('');
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ bottom: 7 })

              Column().width('100%').height(1).backgroundColor(Rule.STRONG)
              Column().width('100%').height(1).backgroundColor(Rule.HAIR).margin({ top: 2, bottom: 12 })

              ForEach(this.recent, (r: BehaviorRecord) => {
                Row() {
                  Text(r.date.substring(5))
                    .fontSize(10)
                    .fontColor(Ink.L3)
                    .fontFeature('"tnum" 1')
                    .width(44)

                  Column() {
                    Text(r.name)
                      .fontSize(13)
                      .fontColor(Ink.L1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${r.amount}${r.unit} · ${categoryLabel(r.category)}`)
                      .fontSize(10)
                      .fontColor(Ink.L3)
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text(`−${r.saved}`)
                    .fontSize(14)
                    .fontColor(Ink.L1)
                    .fontFeature('"tnum" 1')
                  Text('kg')
                    .fontSize(9)
                    .fontColor(Ink.L3)
                    .margin({ left: 2 })

                  Text('删')
                    .fontSize(10)
                    .fontColor(Ink.L4)
                    .padding({ left: 10, top: 6, bottom: 6 })
                    .onClick(() => {
                      this.remove(r.id);
                    })
                }
                .width('100%')
                .padding({ top: 11, bottom: 11 })
                .alignItems(VerticalAlign.Center)
                .border({ width: { bottom: 1 }, color: Rule.HAIR })
              }, (r: BehaviorRecord) => r.id)
            }
            .width('100%')
            .padding({ left: Space.LG, right: Space.LG, top: 14, bottom: 6 })
            .backgroundColor(Bg.CARD)
            .borderRadius(Radius.MD)
            .margin({ top: Space.MD })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}
