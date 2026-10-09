/**
 * 看板 —— 主要功能 2：数据可视化看板
 *
 * 三种视图对应赛题原文要求：
 *   折线图 → 日/周/月/年减排趋势
 *   柱状图 → 分类对比
 *   饼图   → 分类占比
 * 数据来自 CarbonRepository，图表用 @ohos/mpchart 渲染。
 *
 * ── 本次美化改动 ────────────────────────────────────────────────────────
 * v1 的问题是「三个白卡 + 三个图」，没有任何视觉锚点，且顶部三宫格与「我的」
 * 页完全雷同（两个页面第一眼分不出来）。本次：
 *   1. 新增深色英雄区（heroGradientDeep）—— 与记一笔/积分的亮绿英雄区同语言、
 *      不同气质，看板偏「沉稳的数据感」；
 *   2. 英雄区右侧放**本周目标环**，把「3.52 kg」这个孤立数字变成「完成了多少」；
 *   3. 三宫格降级为英雄区底部的两行小指标，不再单独占一张白卡；
 *   4. 所有卡片改用 SectionCard（统一阴影 + 图标标题）；
 *   5. 分类占比下方补**原生图例**（色点 + 百分比 + 进度条），
 *      替代 mpchart 默认的方形图例，并顺手把「分类明细」合并进来。
 */
import { CarbonRepository, CategoryTotal } from '../data/CarbonRepository';
import { BehaviorRecord, categoryLabel, formatDate, round2, today } from '../model/Models';
import { CategoryBarChart, CategoryPieChart, ChartPayload, TrendLineChart } from './Charts';
import { SmartService } from './SmartService';
import { catColor, CardTitle, Chip, EmptyHint, HeroCard, RankRow, RingStat, SectionCard } from './Common';
import {
  Bg, Brand, Edge, FontSize, Heat, Ink, Motion, Radius, Semantic, Space, Weight,
  shadowCard
} from '../common/Theme';

/** 时间粒度 */
enum Grain {
  DAY = 'day',
  WEEK = 'week',
  MONTH = 'month',
  YEAR = 'year'
}

const GRAINS: string[] = [Grain.DAY, Grain.WEEK, Grain.MONTH, Grain.YEAR];

/** 日历热力图的周数（12 周 ≈ 一个季度，是"看得见习惯"的最小窗口） */
const HEAT_WEEKS: number = 12;
/** 热力图格子边长（vp）。12 列 × 22 + 11 个间隙 = 300 左右，能塞进卡片内边距 */
const HEAT_CELL: number = 26;
/** 格子之间的间隙 */
const HEAT_GAP: number = 4;

/** 每日目标：与「记一笔」页保持一致的口径（3 kg/天） */
const DAILY_GOAL: number = 3.0;
/** 一棵树一年约吸收 18 kg CO₂（与 SmartService 同口径） */
const KG_PER_TREE_PER_YEAR: number = 18;
/** 英雄区里的「胶囊」底色：半透明白，压在渐变上自然分层。属于装饰色，故就近定义。 */
const DECO_PILL: string = '#26FFFFFF';

function grainLabel(g: string): string {
  if (g === Grain.DAY) {
    return '日';
  }
  if (g === Grain.WEEK) {
    return '周';
  }
  if (g === Grain.MONTH) {
    return '月';
  }
  return '年';
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

@Component
export struct DashboardPage {
  /** 数据版本号，页签切换时由 Index 递增，用于刷新（原因见 SmartService 注释） */
  @Prop @Watch('onVersion') version: number = 0;
  /**
   * 打开「我的年度碳迹」报告。
   * 报告是全屏的（要盖住页签栏），所以真正的渲染在 Index 里，这里只负责触发。
   */
  onOpenReport: () => void = () => {
  };

  @State grain: string = Grain.WEEK;
  @State rangeSaved: number = 0;
  @State total: number = 0;
  @State count: number = 0;
  @State byCat: CategoryTotal[] = [];
  @State rangeCount: number = 0;
  /** 今日已减排，用于算目标环 */
  @State todaySaved: number = 0;
  /**
   * 日历热力图：最近 HEAT_WEEKS 周、按天聚合的减排量（kg）。
   * 索引 0 是「最早的一天」，末位是今天；不足的格子用 -1 表示「不属于统计窗口」。
   */
  @State heat: number[] = [];
  /** 有记录的天数 */
  @State activeDays: number = 0;
  /** 最长连续记录天数 */
  @State streak: number = 0;

  /** 图表数据负载（整体替换以触发图表重建） */
  @State trend: ChartPayload = new ChartPayload();
  @State barPayload: ChartPayload = new ChartPayload();
  @State piePayload: ChartPayload = new ChartPayload();

  aboutToAppear(): void {
    this.refresh();
  }

  onVersion(): void {
    this.refresh();
  }

  /** 按当前粒度算出区间起点（YYYY-MM-DD） */
  private rangeStart(): string {
    const d: Date = new Date();
    if (this.grain === Grain.DAY) {
      return formatDate(d);
    }
    if (this.grain === Grain.WEEK) {
      const dow: number = d.getDay();
      const back: number = dow === 0 ? 6 : dow - 1;
      d.setDate(d.getDate() - back);
      return formatDate(d);
    }
    if (this.grain === Grain.MONTH) {
      return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-01`;
    }
    return `${d.getFullYear()}-01-01`;
  }

  /**
   * 一次性把所有记录读进内存，之后所有统计都在内存里做。
   *
   * 为什么这么改：原来算折线图要对「每一天」调一次 `behaviorsBetween`，
   * 月视图就是 30 次、年视图 12 次，而每次调用底层都会全量扫一遍 KV。
   * 加上"上期幽灵线"和"12 周日历热力图"之后，调用次数会翻到 90+ 次 ——
   * 那既慢又没必要。改成读一次、在内存里分桶，复杂度从 O(天数 × 记录数) 降到 O(记录数)。
   */
  private async refresh(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    const all: BehaviorRecord[] = await repo.listBehaviors();
    this.count = all.length;

    // 按日期分桶 —— 折线图、幽灵线、热力图、目标环全都从这里取数
    const byDate: Map<string, number> = new Map<string, number>();
    let total: number = 0;
    for (let i = 0; i < all.length; i++) {
      const r: BehaviorRecord = all[i];
      const prev: number | undefined = byDate.get(r.date);
      byDate.set(r.date, (prev === undefined ? 0 : prev) + r.saved);
      total += r.saved;
    }
    this.total = round2(total);

    const from: string = this.rangeStart();
    const to: string = today();
    this.rangeSaved = round2(this.sumRange(byDate, from, to));
    this.rangeCount = this.countRange(all, from, to);
    this.todaySaved = round2(this.sumRange(byDate, to, to));

    this.buildHeat(byDate);
    await this.buildTrend(byDate);

    const cats: CategoryTotal[] = await repo.savedByCategory();
    this.byCat = cats;

    const labels: string[] = [];
    const values: number[] = [];
    for (let i = 0; i < cats.length; i++) {
      labels.push(cats[i].label);
      values.push(cats[i].total);
    }
    const pie: ChartPayload = new ChartPayload();
    pie.version = this.piePayload.version + 1;
    pie.labels = labels;
    pie.values = values;
    this.piePayload = pie;

    const bar: ChartPayload = new ChartPayload();
    bar.version = this.barPayload.version + 1;
    bar.labels = labels;
    bar.values = values;
    this.barPayload = bar;
  }

  // -------------------------------------------------------------------------
  // 内存统计辅助（数据已经从 KV 一次性读进 byDate，这里全是纯计算）
  // -------------------------------------------------------------------------

  /** 某一天的减排量 */
  private daySaved(byDate: Map<string, number>, ds: string): number {
    const v: number | undefined = byDate.get(ds);
    return v === undefined ? 0 : v;
  }

  /** 闭区间 [from, to] 的减排量合计 */
  private sumRange(byDate: Map<string, number>, from: string, to: string): number {
    // 字符串比较即可 —— 格式固定为 YYYY-MM-DD，字典序与时间序一致
    let sum: number = 0;
    byDate.forEach((v: number, k: string) => {
      if (k >= from && k <= to) {
        sum += v;
      }
    });
    return sum;
  }

  /** 闭区间 [from, to] 的记录条数 */
  private countRange(all: BehaviorRecord[], from: string, to: string): number {
    let n: number = 0;
    for (let i = 0; i < all.length; i++) {
      const d: string = all[i].date;
      if (d >= from && d <= to) {
        n++;
      }
    }
    return n;
  }

  /** 相对今天偏移 n 天并格式化成 YYYY-MM-DD（n 为负 = 往前） */
  private dayOffset(n: number): string {
    const d: Date = new Date();
    d.setDate(d.getDate() + n);
    return formatDate(d);
  }

  // -------------------------------------------------------------------------
  // 日历热力图：最近 HEAT_WEEKS 周，按「周」分列、每列 7 天
  // -------------------------------------------------------------------------

  /**
   * 生成热力图数据。
   *
   * 排布规则：最后一列是本周（从周一到周日），往前推 HEAT_WEEKS 列。
   * 未来的日期（本周里还没到的那几天）标记为 -1，渲染成"空位"而不是"0 减排"——
   * 这两者的语义完全不同，混在一起会让人以为自己漏记了。
   */
  private buildHeat(byDate: Map<string, number>): void {
    const todayStr: string = today();
    const now: Date = new Date();
    // 本周周一距今天几天（getDay(): 周日=0）
    const dow: number = now.getDay();
    const toMonday: number = dow === 0 ? 6 : dow - 1;

    const cells: number[] = [];
    let active: number = 0;
    for (let i = 0; i < HEAT_WEEKS * 7; i++) {
      // 从"最早的一天"顺序补齐：起点 = 本周一 - (HEAT_WEEKS-1) 周
      const offset: number = -(toMonday + (HEAT_WEEKS - 1) * 7) + i;
      const ds: string = this.dayOffset(offset);
      if (ds > todayStr) {
        cells.push(-1);
        continue;
      }
      const v: number = this.daySaved(byDate, ds);
      if (v > 0) {
        active++;
      }
      cells.push(v);
    }
    this.heat = cells;
    this.activeDays = active;
    this.streak = this.longestStreak(byDate);
  }

  /** 最长连续记录天数（按日期是否有记录计算，不要求连续自然日之间的量） */
  private longestStreak(byDate: Map<string, number>): number {
    let best: number = 0;
    let cur: number = 0;
    for (let back = 400; back >= 0; back--) {
      const v: number = this.daySaved(byDate, this.dayOffset(-back));
      if (v > 0) {
        cur++;
        if (cur > best) {
          best = cur;
        }
      } else {
        cur = 0;
      }
    }
    return best;
  }

  /** 热力图的色阶：把当天的减排量映射到 4 档（0 值单独用中性灰） */
  private heatColor(v: number): ResourceColor {
    if (v < 0) {
      // ⚠️ 这里必须用 Color.Transparent，不能写 8 位全零的 '#00000000'
      //    —— 后者在 ArkUI 里不是合法色值，会渲染成黑色方块。
      return Color.Transparent;
    }
    if (v <= 0) {
      return Heat.EMPTY;
    }
    const max: number = this.heatMax();
    if (max <= 0) {
      return Heat.L1;
    }
    const r: number = v / max;
    if (r <= 0.25) {
      return Heat.L1;
    }
    if (r <= 0.5) {
      return Heat.L2;
    }
    if (r <= 0.75) {
      return Heat.L3;
    }
    return Heat.L4;
  }

  /** [0..HEAT_WEEKS-1] —— ForEach 需要一个数组才能渲染（ArkTS 里不能直接 for 循环建 UI） */
  private weekIndexes(): number[] {
    const out: number[] = [];
    for (let i = 0; i < HEAT_WEEKS; i++) {
      out.push(i);
    }
    return out;
  }

  /** [0..6] —— 一列 7 天 */
  private dayIndexes(): number[] {
    const out: number[] = [];
    for (let i = 0; i < 7; i++) {
      out.push(i);
    }
    return out;
  }

  /** 取第 i 个格子的颜色（越界返回全透明，避免渲染出多余的格子） */
  private cellColor(i: number): ResourceColor {
    if (i < 0 || i >= this.heat.length) {
      // ⚠️ 这里必须用 Color.Transparent，不能写 8 位全零的 '#00000000'
      //    —— 后者在 ArkUI 里不是合法色值，会渲染成黑色方块。
      return Color.Transparent;
    }
    return this.heatColor(this.heat[i]);
  }

  /** 图例的 4 个色块 */
  private legendColors(): string[] {
    return [Heat.L1, Heat.L2, Heat.L3, Heat.L4];
  }

  private heatMax(): number {
    let m: number = 0;
    for (let i = 0; i < this.heat.length; i++) {
      if (this.heat[i] > m) {
        m = this.heat[i];
      }
    }
    return m;
  }

  /**
   * 按粒度组装折线图 + 幽灵线的 X 轴分桶。
   *
   * 幽灵线的口径：「把整个窗口往前平移一个窗口长度」。
   *   周视图 → 上周同期；月视图 → 前 30 天；年视图 → 去年同月。
   * 这样两条线逐点可比，读者不用换算。
   */
  private async buildTrend(byDate: Map<string, number>): Promise<void> {
    const labels: string[] = [];
    const values: number[] = [];
    const prev: number[] = [];

    if (this.grain === Grain.YEAR) {
      const y: number = new Date().getFullYear();
      for (let m = 0; m < 12; m++) {
        const mm: string = pad2(m + 1);
        labels.push(`${m + 1}月`);
        values.push(round2(this.sumRange(byDate, `${y}-${mm}-01`, `${y}-${mm}-31`)));
        prev.push(round2(this.sumRange(byDate, `${y - 1}-${mm}-01`, `${y - 1}-${mm}-31`)));
      }
    } else {
      let days: number = 7;
      if (this.grain === Grain.MONTH) {
        days = 30;
      }
      for (let back = days - 1; back >= 0; back--) {
        const d: Date = new Date();
        d.setDate(d.getDate() - back);
        labels.push(`${d.getMonth() + 1}/${d.getDate()}`);
        values.push(round2(this.daySaved(byDate, formatDate(d))));
        // 上期 = 同一个点往前平移 days 天
        const pd: Date = new Date();
        pd.setDate(pd.getDate() - back - days);
        prev.push(round2(this.daySaved(byDate, formatDate(pd))));
      }
    }

    const p: ChartPayload = new ChartPayload();
    p.version = this.trend.version + 1;
    p.labels = labels;
    p.values = values;
    p.prevValues = prev;
    this.trend = p;
  }

  private hasData(): boolean {
    return this.total > 0;
  }

  /** 今日目标完成度（0–100） */
  private goalPercent(): number {
    const p: number = Math.round(this.todaySaved / DAILY_GOAL * 100);
    return p > 100 ? 100 : p;
  }

  /** 累计减排折合「几棵树一年」 */
  private trees(): number {
    return Math.round((this.total / KG_PER_TREE_PER_YEAR) * 10) / 10;
  }

  /** 分类总量，用于算占比 */
  private catSum(): number {
    let s: number = 0;
    for (let i = 0; i < this.byCat.length; i++) {
      s += this.byCat[i].total;
    }
    return s;
  }

  private catPercent(total: number): number {
    const sum: number = this.catSum();
    if (sum <= 0) {
      return 0;
    }
    return Math.round(total / sum * 100);
  }

  /** 趋势小结：把图读成一句话，评委不用自己看图 */
  private trendSummary(): string {
    if (this.rangeCount === 0) {
      return `本${grainLabel(this.grain)}还没有记录`;
    }
    return `本${grainLabel(this.grain)}已减排 ${this.rangeSaved} kg CO₂e，共 ${this.rangeCount} 条记录`;
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // ============ 英雄区：累计减排 + 今日目标环 ============
          HeroCard({ variant: 'deep' }) {
            Row() {
              Column() {
                Text('累计减排')
                  .fontSize(FontSize.BODY_S)
                  .fontColor(Ink.ON_BRAND_3)

                Row() {
                  Text(`${this.total}`)
                    .fontSize(FontSize.DISPLAY_M)
                    .fontWeight(Weight.DISPLAY)
                    .fontColor(Ink.ON_BRAND)
                    // 数字等宽：让「352」变成「353」时每个字形宽度不变，数字动效不左右抖。
                    // ss01 是官方文档给出的示例标签；OpenType 标准的 tnum 未在文档列出，
                    // 二者都试过，本机（HarmonyOS 7.0 / API 26 模拟器）都渲染正常。
                    .fontFeature('"ss01" on')
                  Text('kg')
                    .fontSize(FontSize.SUB_M)
                    .fontColor(Ink.ON_BRAND_2)
                    .margin({ left: 5, bottom: 7 })
                }
                .alignItems(VerticalAlign.Bottom)

                Text(`CO₂e · 折合 ${this.trees()} 棵树·年`)
                  .fontSize(FontSize.BODY_S)
                  .fontColor(Ink.ON_BRAND_3)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              RingStat({ percent: this.goalPercent(), diameter: 88, ringWidth: 7 }) {
                Text(`${this.goalPercent()}%`)
                  .fontSize(FontSize.TITLE_S)
                  .fontWeight(Weight.SUBTITLE)
                  .fontColor(Ink.ON_BRAND)
                Text('今日目标')
                  .fontSize(FontSize.CAPTION)
                  .fontColor(Ink.ON_BRAND_2)
                  .margin({ top: 1 })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 英雄区底部的两条小指标：把原来单独占一张白卡的三宫格收进来
            Row() {
              Text(`本${grainLabel(this.grain)} ${this.rangeSaved} kg`)
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.ON_BRAND)
                .backgroundColor(DECO_PILL)
                .borderRadius(Radius.FULL)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
              Text(`${this.count} 条记录`)
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.ON_BRAND)
                .backgroundColor(DECO_PILL)
                .borderRadius(Radius.FULL)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                .margin({ left: Space.SM })
            }
            .width('100%')
            .margin({ top: Space.XL })
          }

          // ============ 年度报告入口 ============
          // 一张"看起来不像普通卡片"的横幅：浅色渐变底 + 图标块 + 右侧箭头。
          // 放在英雄区正下方，是因为它是整个应用里**最适合在答辩现场展示**的一屏
          // （本质是把已有数字重新排版，但情绪价值最高）。
          Row() {
            Column() {
              Image($r('app.media.ic_export'))
                .width(19)
                .height(19)
                .fillColor(Brand.PRIMARY)
                .objectFit(ImageFit.Contain)
            }
            .width(40)
            .height(40)
            .borderRadius(Radius.SM)
            .backgroundColor(Bg.CARD)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ right: Space.MD })

            Column() {
              Row() {
                Text('我的年度碳迹')
                  .fontSize(FontSize.SUB_M)
                  .fontWeight(Weight.SUBTITLE)
                  .fontColor(Ink.L1)
                Text('报告')
                  .fontSize(FontSize.CAPTION)
                  .fontColor(Brand.PRIMARY)
                  .backgroundColor(Bg.CARD)
                  .borderRadius(Radius.XS)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .margin({ left: 6 })
              }
              .alignItems(VerticalAlign.Center)

              Text('把这一年的减排汇成一页，含最长连续记录与主力贡献')
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.L2)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 3 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Image($r('app.media.ic_arrow'))
              .width(15)
              .height(15)
              .fillColor(Ink.L3)
              .objectFit(ImageFit.Contain)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding(Space.MD)
          .linearGradient({
            angle: 135,
            colors: [[Brand.MIST, 0.0], [Brand.SOFT, 1.0]]
          })
          .borderRadius(Radius.MD)
          // 渐变描边：ArkUI 的 borderImage 原生接受 LinearGradient 作为 source
          //（官方《边框设置》里写的是「图片边框或者渐变色边框设置接口」）。
          // 比 `border({color})` 强的地方是：描边本身可以有明暗变化，
          // 一条从上到下由浅入深的 1.5vp 细边，就是"这张卡被设计过"的信号。
          .borderImage({
            source: {
              angle: 135,
              colors: [[Brand.LIGHT, 0.0], [Brand.PRIMARY, 1.0]]
            },
            slice: { top: 1, bottom: 1, left: 1, right: 1 },
            width: { top: 1, bottom: 1, left: 1, right: 1 },
            repeat: RepeatMode.Stretch
          })
          .shadow(shadowCard())
          .margin({ bottom: Space.MD })
          .onClick(() => {
            animateTo(Motion.QUICK, () => {
              this.onOpenReport();
            });
          })

          // ============ 统计粒度 ============
          SectionCard({ title: '统计粒度', icon: $r('app.media.ic_target'), showIcon: true }) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(GRAINS, (g: string) => {
                Chip({
                  label: grainLabel(g),
                  selected: this.grain === g,
                  onTap: () => {
                    this.grain = g;
                    this.refresh();
                  }
                })
              }, (g: string) => g)
            }
            .width('100%')

            Text(`区间 ${this.rangeStart()} ~ ${today()} · 共 ${this.rangeCount} 条`)
              .fontSize(FontSize.BODY_S)
              .fontColor(Ink.L3)
              .width('100%')
              .margin({ top: 2 })
          }

          // ============ 日历热力图：最近 12 周 ============
          // 三条"打卡类标准三件套"里我们最后补上的一件（进度环、勋章墙此前已做）。
          // 它回答的是折线图回答不了的问题：**我到底有没有在坚持**。
          SectionCard({
            title: '减排日历',
            icon: $r('app.media.ic_flame'),
            showIcon: true,
            badge: `最近 ${HEAT_WEEKS} 周`,
            badgeColor: Brand.PRIMARY,
            badgeSoft: Brand.SOFT
          }) {
            // 两个情绪指标放在最上面 —— 热力图是"看"，这两个数字是"读"
            Row() {
              Row() {
                Image($r('app.media.ic_flame'))
                  .width(15)
                  .height(15)
                  .fillColor(Semantic.ALERT)
                  .objectFit(ImageFit.Contain)
                  .margin({ right: 5 })
                Text(`连续 ${this.streak} 天`)
                  .fontSize(FontSize.BODY_M)
                  .fontWeight(Weight.SUBTITLE)
                  .fontColor(Ink.L1)
              }
              .alignItems(VerticalAlign.Center)
              .backgroundColor(Semantic.ALERT_SOFT)
              .borderRadius(Radius.FULL)
              .padding({ left: 11, right: 12, top: 5, bottom: 5 })

              Text(`共 ${this.activeDays} 天有记录`)
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.L3)
                .margin({ left: Space.MD })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ bottom: Space.MD })

            // 12 列 × 7 天。列 = 周，行 = 周一..周日
            Row() {
              ForEach(this.weekIndexes(), (w: number) => {
                Column() {
                  ForEach(this.dayIndexes(), (d: number) => {
                    Column()
                      .width(HEAT_CELL)
                      .height(HEAT_CELL)
                      .borderRadius(Radius.XS)
                      .backgroundColor(this.cellColor(w * 7 + d))
                      .margin({ bottom: d === 6 ? 0 : HEAT_GAP })
                  }, (d: number) => `${w}-${d}`)
                }
              }, (w: number) => `w${w}`)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            // 图例：少 ▢▢▢▢ 多
            Row() {
              Text('少')
                .fontSize(FontSize.CAPTION)
                .fontColor(Ink.L3)
                .margin({ right: 5 })
              ForEach(this.legendColors(), (c: string, i: number) => {
                Column()
                  .width(12)
                  .height(12)
                  .borderRadius(Radius.XS)
                  .backgroundColor(c)
                  .margin({ right: 3 })
              }, (c: string, i: number) => `lg${i}`)
              Text('多')
                .fontSize(FontSize.CAPTION)
                .fontColor(Ink.L3)
                .margin({ left: 3 })
              Blank()
              Text('每格 = 一天')
                .fontSize(FontSize.CAPTION)
                .fontColor(Ink.L4)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: Space.MD })
          }

          if (!this.hasData()) {
            EmptyHint({
              title: '还没有数据',
              desc: '先去「记一笔」记录一条低碳行为，这里就会出现图表。',
              icon: $r('app.media.ic_tab_chart')
            })
          } else {
            // ============ 折线图 ============
            SectionCard({ title: `减排趋势（本${grainLabel(this.grain)}）`, icon: $r('app.media.ic_tab_chart'), showIcon: true }) {
              Row() {
                Text(this.trendSummary())
                  .fontSize(FontSize.BODY_S)
                  .fontColor(Ink.L3)
                  .layoutWeight(1)
                // 幽灵线必须有说明 —— 否则读者会把它当成"第二条真实数据"
                Column()
                  .width(16)
                  .height(0)
                  .borderWidth({ top: 2 })
                  .borderColor(Ink.L4)
                  .margin({ right: 4 })
                Text('上期')
                  .fontSize(FontSize.CAPTION)
                  .fontColor(Ink.L3)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ bottom: Space.SM })
              TrendLineChart({ payload: this.trend })
                .width('100%')
                .height(200)
            }

            // ============ 柱状图 ============
            SectionCard({ title: '分类减排对比', icon: $r('app.media.ic_tab_chart'), showIcon: true }) {
              Text('单位：kg CO₂e')
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.L3)
                .width('100%')
                .margin({ bottom: Space.SM })
              CategoryBarChart({ payload: this.barPayload })
                .width('100%')
                .height(190)
            }

            // ============ 饼图 + 原生图例 ============
            SectionCard({ title: '分类占比', icon: $r('app.media.ic_recycle'), showIcon: true }) {
              CategoryPieChart({ payload: this.piePayload })
                .width('100%')
                .height(190)

              Divider()
                .color(Edge.HAIR)
                .strokeWidth(1)
                .margin({ top: Space.SM, bottom: Space.MD })

              ForEach(this.byCat, (c: CategoryTotal) => {
                RankRow({
                  label: c.label,
                  value: `${c.total} kg`,
                  percent: this.catPercent(c.total),
                  color: catColor(c.category)
                })
              }, (c: CategoryTotal) => c.category)
            }
          }

          // 创新点 4：智能服务（任务 / 建议 / 分享）
          SmartService({ version: this.version })
        }
        .width('100%')
        .padding(Space.LG)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Bg.PAGE)
  }
}
