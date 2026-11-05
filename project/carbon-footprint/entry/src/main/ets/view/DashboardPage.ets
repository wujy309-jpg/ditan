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
  Bg, Brand, Edge, FontSize, Heat, Ink, Motion, Radius, Rule, Seal, Semantic, Serif, Space, Weight,
  shadowCard
} from '../common/Theme';

/** 线描树的一段枝条（绝对坐标，交给 Path 画） */
interface TreeSegment {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  w: number;
  /** 层级：0 = 末梢（叶子长在这里） */
  d: number;
}

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
  @State @Watch('onTotalChanged') total: number = 0;
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

  /** 距离下一棵树还差多少 kg —— 比把总量再念一遍更有用 */
  private nextTreeGap(): number {
    const rem: number = this.total % KG_PER_TREE_PER_YEAR;
    return Math.round((KG_PER_TREE_PER_YEAR - rem) * 10) / 10;
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

  /** Canvas 绘制上下文（树的坐标用 vp，和布局单位一致） */
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private treePainted: boolean = false;

  onTotalChanged(): void {
    this.paintTree();
  }

  /**
   * 画树：骨架是线，树冠是点。
   *
   * 只画枝条时，一棵树在暗底上会退化成「几根抽象的线」——远看什么都认不出。
   * 让叶子成为**面积**（一堆点聚成树冠）之后，剪影才闭合，一眼就是一棵树；
   * 而每一片叶子的数量由「累计减排」决定，繁茂程度本身就是数据。
   */
  private paintTree(): void {
    if (!this.treePainted) {
      return;
    }
    const W: number = 288;
    const H: number = 232;
    const segs: TreeSegment[] = this.treeSegs();
    this.ctx.clearRect(0, 0, W, H);

    // 枝条：数据越多越实
    const g: number = Math.min(1, this.total / 15);
    const inkA: number = 0.40 + 0.28 * g;
    this.ctx.lineCap = 'round';
    this.ctx.strokeStyle = `rgba(32,29,23,${inkA.toFixed(3)})`;
    const cx0: number = 144;
    const cy0: number = 106;
    const rx0: number = 34 + g * 56;
    const ry0: number = 24 + g * 38;
    for (let i = 0; i < segs.length; i++) {
      // 外层枝条若整段落在树冠之外，就不画 —— 否则会留下一圈「枯枝」戳出轮廓
      if (segs[i].d <= 1) {
        // 端点出冠就整段丢掉：只判「两端都在外」会留下一截截戳出轮廓的枯枝
        const inB: boolean = this.inCrown(segs[i].x1, segs[i].y1, cx0, cy0, rx0, ry0);
        if (!inB) {
          continue;
        }
      }
      this.ctx.beginPath();
      this.ctx.lineWidth = segs[i].w;
      this.ctx.moveTo(segs[i].x0, segs[i].y0);
      this.ctx.lineTo(segs[i].x1, segs[i].y1);
      this.ctx.stroke();
    }

    // 树冠：一团叶。锚点沿枝条撒会变成「枝上挂葡萄」，剪影不闭合；
    // 真正让树一眼可辨的是**一团连续的面**，所以叶子按椭圆区域撒点，
    // 枝条只负责在冠内做骨架。
    const cx: number = cx0;
    const cy: number = cy0;
    const rx: number = rx0;
    const ry: number = ry0;
    // 0 记录时不长树冠：只留一根芽
    const leaves: number = this.total <= 0 ? 0 : Math.min(320, Math.round(20 + this.total * 17));
    for (let i = 0; i < leaves; i++) {
      const a: number = this.hash(i * 3 + 0.7) * Math.PI * 2;
      const rr: number = Math.sqrt(this.hash(i * 3 + 1.7));
      const h: number = this.hash(i * 3 + 2.7);
      // 边缘稍微稀疏一点：rr^0.85 让粒子更靠外，冠的轮廓才明显
      const rr2: number = Math.pow(rr, 0.85);
      const x: number = cx + Math.cos(a) * rr2 * rx;
      const y: number = cy + Math.sin(a) * rr2 * ry * 0.92;
      const r: number = 1.7 + h * 1.6;
      if (i % 64 === 0) {
        this.ctx.fillStyle = 'rgba(171,58,40,0.85)';
      } else if (h > 0.62) {
        this.ctx.fillStyle = 'rgba(94,156,124,0.42)';
      } else if (h > 0.30) {
        this.ctx.fillStyle = 'rgba(46,122,87,0.50)';
      } else {
        this.ctx.fillStyle = 'rgba(29,92,67,0.55)';
      }
      this.ctx.beginPath();
      this.ctx.arc(x, y, r, 0, Math.PI * 2);
      this.ctx.fill();
    }

    // 一道地平线，让树「站住」——没有它，树是浮在深色里的
    this.ctx.strokeStyle = 'rgba(32,29,23,0.20)';
    this.ctx.lineWidth = 1;
    this.ctx.beginPath();
    this.ctx.moveTo(44, 218);
    this.ctx.lineTo(244, 218);
    this.ctx.stroke();
  }

  /** 点是否落在树冠椭圆内（稍微放宽 8%，避免边缘被裁得太硬） */
  private inCrown(x: number, y: number, cx: number, cy: number, rx: number, ry: number): boolean {
    const dx: number = (x - cx) / (rx * 1.08);
    const dy: number = (y - cy) / (ry * 1.08);
    return dx * dx + dy * dy <= 1;
  }

  /** 确定性伪随机：同一份数据每次画出来完全一样 */
  private hash(n: number): number {
    const r: number = Math.sin(n * 127.1) * 43758.5453;
    return r - Math.floor(r);
  }

  /**
   * 线描树：把「累计减排」画成一棵会长大的树。
   * 枝的层数 = 生长阶段（0 记录时只有一根芽），主枝长度 = 累计量。
   * 用 Path 的绝对坐标画，不用「矩形 + rotate」——后者的旋转/定位在 Stack 里
   * 会互相干扰（第一版就是这么把一棵树渲染成了三棵），Path 一次成型、还更清晰。
   */
  private treeSegs(): TreeSegment[] {
    const out: TreeSegment[] = [];
    const g: number = Math.min(1, this.total / 15);
    const trunk: number = 40 + g * 40;
    const depth: number = this.total <= 0 ? 1 : (this.total < 3 ? 2 : (this.total < 10 ? 3 : 4));
    this.grow(out, 144, 216, trunk, 0, 3.6, depth);
    return out;
  }

  private grow(out: TreeSegment[], x: number, y: number, len: number,
    ang: number, w: number, depth: number): void {
    const rad: number = ang * Math.PI / 180;
    const ex: number = x + Math.sin(rad) * len;
    const ey: number = y - Math.cos(rad) * len;
    out.push({ x0: x, y0: y, x1: ex, y1: ey, w: w, d: depth });
    if (depth <= 0) {
      return;
    }
    const spread: number = 24 + depth * 6;
    this.grow(out, ex, ey, len * 0.70, ang - spread, Math.max(0.7, w * 0.62), depth - 1);
    this.grow(out, ex, ey, len * 0.70, ang + spread, Math.max(0.7, w * 0.62), depth - 1);
  }

  /**
   * 一句话：数字告诉人「发生了什么」，句子告诉人「现在该干什么」。
   * 不引因子库做换算，避免为了造句在页面里塞业务耦合。
   */
  private todayLine(): string {
    if (this.todaySaved >= DAILY_GOAL) {
      return '今日额度记满，明天继续。';
    }
    if (this.todaySaved <= 0) {
      return '今天还没开张 —— 记一笔，账上就有了。';
    }
    return `还差 ${(DAILY_GOAL - this.todaySaved).toFixed(2)} kg，再记一笔就够。`;
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // ============ 英雄区：累计减排 + 今日目标环 ============
          HeroCard({ variant: 'deep', period: today(), stamp: '碳迹', days: this.streak }) {
            Column() {
              Text('累 计 减 排')
                .fontSize(10)
                .fontColor(Ink.ON_BRAND_3)
                .letterSpacing(3)
                .width('100%')

              Row() {
                Text(`${this.total}`)
                  .fontFamily(Serif.FAMILY)
                  .fontSize(52)
                  .fontColor(Ink.ON_BRAND)
                  .fontFeature('"tnum" 1')
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

              Text(`折合 ${this.trees()} 棵树·年`)
                .fontSize(11)
                .fontColor(Ink.ON_BRAND_3)
                .width('100%')
                .margin({ top: 2 })

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
              .margin({ top: 16 })

              Row() {
                Text('今 日 目 标')
                  .fontSize(10)
                  .fontColor(Ink.ON_BRAND_3)
                  .letterSpacing(1)
                Text(`${this.todaySaved.toFixed(2)} / ${DAILY_GOAL.toFixed(2)} kg`)
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

          // ============ 我的树 ============
          // 一棵会长的树，画在**纸上**而不是深墨底上：墨线 + 绿叶，
          // 对比度立刻上来，远看就是一棵树 —— 深底上的浅线永远只是「几根线」。
          Column() {
            Row() {
              Text('我 的 树')
                .fontFamily(Serif.FAMILY)
                .fontSize(15)
                .letterSpacing(2)
                .fontColor(Ink.L1)
                .layoutWeight(1)
              Text('树冠越密，减得越多')
                .fontSize(9)
                .fontColor(Ink.L3)
                .letterSpacing(0.5)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Column().width('100%').height(1).backgroundColor(Rule.STRONG).margin({ top: 7 })
            Column().width('100%').height(1).backgroundColor(Rule.HAIR).margin({ top: 2.5 })

            Row() {
              Canvas(this.ctx)
                .width(288)
                .height(232)
                .onReady(() => {
                  this.treePainted = true;
                  this.paintTree();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)

            // 原来这里写「累计 20.58 kg · 折合 1.1 棵树·年」，与刊头一字不差地重复。
            // 换成「距下一棵树还差多少」—— 同一个事实的可行动版本。
            Text(`距下一棵树还差 ${this.nextTreeGap()} kg`)
              .fontSize(10)
              .fontColor(Ink.L3)
              .fontFeature('"tnum" 1')
              .width('100%')
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding({ left: Space.LG, right: Space.LG, top: 14, bottom: 12 })
          .backgroundColor(Bg.CARD)
          .backgroundImage($r('app.media.paper_card'), ImageRepeat.XY)
          .borderRadius(Radius.MD)
          .margin({ bottom: Space.MD })

          // ============ 年度报告入口 ============
          // 一张"看起来不像普通卡片"的横幅：浅色渐变底 + 图标块 + 右侧箭头。
          // 放在英雄区正下方，是因为它是整个应用里**最适合在答辩现场展示**的一屏
          // （本质是把已有数字重新排版，但情绪价值最高）。
          // ============ 年度报告入口（账页索引行）============
          Row() {
            Text('年 度 报 告')
              .fontFamily(Serif.FAMILY)
              .fontSize(13)
              .letterSpacing(1.5)
              .fontColor(Ink.L1)
              .layoutWeight(1)
            Text('把这一年的减排汇成一页')
              .fontSize(10)
              .fontColor(Ink.L3)
              .margin({ right: 10 })
            Text('→')
              .fontSize(13)
              .fontColor(Seal.RED)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ top: 13, bottom: 13 })
          .border({ width: { top: 1, bottom: 1 }, color: Rule.HAIR })
          .margin({ bottom: Space.LG })
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
                  .fillColor(Seal.RED)
                  .objectFit(ImageFit.Contain)
                  .margin({ right: 5 })
                Text(`连续 ${this.streak} 天`)
                  .fontSize(FontSize.BODY_M)
                  .fontColor(Ink.L1)
                  .fontFeature('"tnum" 1')
              }
              .alignItems(VerticalAlign.Center)

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
    // 纸纹兼作底色（backgroundColor 会盖住 backgroundImage）
    .backgroundImage($r('app.media.paper_page'), ImageRepeat.XY)
  }
}
