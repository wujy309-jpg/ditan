/**
 * 图表组件 —— 主要功能 2 的可视化实现
 *
 * 基于 @ohos/mpchart（OpenHarmony-TPC 官方图表库，纯 ArkTS 源码 HAR，离线可用）。
 *
 * ⚠️ 使用约束（已在模拟器上实测验证，不是照抄 README）：
 *   1. `ColorTemplate.rgb(hex: string)` 收**一个十六进制字符串**；
 *      收三个数字的是另一个类 `ChartColor.rgb(r, g, b)`。两者都从 index.ets 导出，
 *      极易混用 —— 写错会报 `Expected 1 arguments, but got 3`。
 *   2. 图表组件的 model 是**普通成员变量**，且只在 Canvas.onReady 时被消费一次。
 *      **换数据不能重新 new 一个 model 再赋值**——必须 setData() →
 *      notifyDataSetChanged() → invalidate()，否则界面不刷新。
 *   3. 数据集合必须用 JArrayList，不能用原生 Array。
 *   4. `PieDataSet` 没有 `setColors()`（README 饼图示例已过期），
 *      正确方法是 `setColorsByArr(number[])`。
 *   5. 默认会画一个 "Description Label" 水印，必须显式关掉。
 *
 * 另外：图表数据统一通过一个 ChartPayload 对象传入，而不是拆成
 * 「version + labels + values」三个 @Prop。三个 @Prop 的更新与 @Watch 回调
 * 之间存在时序不确定性，合成一个对象可以保证 Watch 触发时数据已就绪。
 */
import {
  AxisBase,
  BarChart,
  BarChartModel,
  BarData,
  BarDataSet,
  BarEntry,
  ChartColor,
  ChartColorStop,
  EntryOhos,
  Fill,
  IAxisValueFormatter,
  IValueFormatter,
  IBarDataSet,
  ILineDataSet,
  IPieDataSet,
  JArrayList,
  LineChart,
  LineChartModel,
  LineData,
  LineDataSet,
  Mode,
  PieChart,
  PieChartModel,
  PieData,
  PieDataSet,
  PieEntry,
  ViewPortHandler
} from '@ohos/mpchart';
import {
  Bg, Brand, CatColor, FontSize, Ink, Radius, Semantic, Space, Weight,
  Motion, shadowCard, shadowRaised, shadowSubtle, heroGradient, softGradient
} from '../common/Theme';

/** 主题绿 */
const GREEN: number = 0x1F9A4E;
/**
 * 图表辅助文字：0x66 是官方文本三级的 40% 黑。
 * 注意 mpchart 的 setTextColor / setGridColor 收的是 ARGB 数值而不是 '#RRGGBB' 字符串。
 */
const AXIS_TEXT: number = 0x66000000;
/** 网格与轴线——刻意做得极淡，只在需要时保留 */
const GRID: number = 0x14000000;
/**
 * 幽灵线（上期）的颜色：中性灰、刻意比主线弱。
 * 它必须「看得见但不抢戏」—— 一旦用彩色，读者会以为那是第二条真实数据。
 */
const GHOST_LINE: number = 0x33000000;

/**
 * 统一清理坐标轴装饰。
 *
 * 依据官方数据可视化规范：图表应当让「数据本身」成为视觉主体，
 * 网格线、坐标轴框、重复的右轴都是噪音。改造前满屏网格线 + 左右两套
 * 相同的 Y 轴刻度，是看板显得「旧」的主要原因。
 *
 * @param axis        坐标轴对象
 * @param showLabels  是否显示刻度文字
 */
function cleanAxis(axis: AxisBase | null, showLabels: boolean): void {
  if (axis === null) {
    return;
  }
  axis.setDrawGridLines(false);
  axis.setDrawAxisLine(false);
  axis.setDrawLabels(showLabels);
  axis.setTextColor(AXIS_TEXT);
  axis.setTextSize(10);
}

/**
 * 只保留极淡的水平参考线，帮助读数但不抢戏。
 * 竖直网格线一律去掉——横轴已有业务标签，再画竖线就是重复信息。
 */
function softHorizontalGrid(axis: AxisBase | null): void {
  if (axis === null) {
    return;
  }
  axis.setDrawGridLines(true);
  axis.setGridColor(GRID);
  axis.setGridLineWidth(0.8);
  axis.setDrawAxisLine(false);
  axis.setTextColor(AXIS_TEXT);
  axis.setTextSize(10);
  axis.setLabelCount(4, false);
}

/**
 * 柱状图数值格式化器：**值为 0 的分类不画数值**。
 *
 * 为什么需要：0 值柱子的高度是 0，数值标签会全部贴在 X 轴上叠成一排，
 * 既难看又读不出来。对 0 值返回空串让它彻底消失。
 */
class BarValueFormatter implements IValueFormatter {
  getFormattedValue(value: number, entry: EntryOhos, dataSetIndex: number,
    viewPortHandler: ViewPortHandler): string {
    if (value <= 0) {
      return '';
    }
    return `${value}`;
  }
}

/** 图表数据负载：整体替换即触发重建 */
export class ChartPayload {
  version: number = 0;
  labels: string[] = [];
  values: number[] = [];
  /**
   * 「上期」数据（同比/环比），用于折线图上的**幽灵线**。
   *
   * 为什么要有它：一条孤零零的折线只能回答"这个数是多少"，
   * 回答不了用户真正关心的"我是不是在进步"。叠一条上一周期的灰色虚线，
   * 一屏之内就能看出趋势 —— 这是 Commons（原 Joro）等成熟产品的核心手法，
   * 也是本次调研里最值得抄的一条。
   *
   * 长度约定：与 values 等长时才会绘制；空数组表示不画。
   */
  prevValues: number[] = [];
}

/**
 * 四个类目的配色（出行 / 节水节电 / 旧物回收 / 光盘行动）
 *
 * 注意：mpchart 里有两个 rgb：
 *   ChartColor.rgb(r, g, b)      —— 三个数字（本项目用这个）
 *   ColorTemplate.rgb(hex)       —— 一个十六进制字符串
 * 传错会编译报 "Expected 1 arguments, but got 3"。
 */
function pieColors(): number[] {
  // 取值与 Theme.CatColor 严格一一对应 —— 图例的色点、进度条的颜色都取自
  // 同一套值，这样「绿色 = 出行」在整屏里是自洽的。
  return [
    ChartColor.rgb(31, 154, 78), // CatColor.TRAVEL  #1F9A4E
    ChartColor.rgb(10, 89, 247), // CatColor.ENERGY  #0A59F7
    ChartColor.rgb(237, 111, 33), // CatColor.RECYCLE #ED6F21
    ChartColor.rgb(123, 91, 214) // CatColor.FOOD    #7B5BD6
  ];
}

/** 把 X 轴的数字索引翻译成业务标签（日期 / 类目名） */
class AxisLabelFormatter implements IAxisValueFormatter {
  private labels: string[];

  constructor(labels: string[]) {
    this.labels = labels;
  }

  getFormattedValue(value: number, axis: AxisBase): string {
    const i: number = Math.round(value);
    if (i >= 0 && i < this.labels.length) {
      return this.labels[i];
    }
    return '';
  }
}

// ---------------------------------------------------------------------------
// 折线图：减排趋势
// ---------------------------------------------------------------------------

@Component
export struct TrendLineChart {
  @Prop @Watch('rebuild') payload: ChartPayload = new ChartPayload();

  private model: LineChartModel = new LineChartModel();

  aboutToAppear(): void {
    this.rebuild();
  }

  /** 上期数据是否「有内容」——全 0 就不画幽灵线，避免出现一条贴底的假线 */
  private hasPrevData(): boolean {
    for (let i = 0; i < this.payload.prevValues.length; i++) {
      if (this.payload.prevValues[i] > 0) {
        return true;
      }
    }
    return false;
  }

  rebuild(): void {
    if (this.payload.values.length === 0) {
      return;
    }
    const entries: JArrayList<EntryOhos> = new JArrayList<EntryOhos>();
    for (let i = 0; i < this.payload.values.length; i++) {
      entries.add(new EntryOhos(i, this.payload.values[i]));
    }

    const sets: JArrayList<ILineDataSet> = new JArrayList<ILineDataSet>();

    // ---- 幽灵线（上期）先加入，因此画在主线之下 ----
    // 只在「长度对齐且确实有数据」时画，否则会出现一条贴着 0 的假线，
    // 反而误导读者。
    if (this.payload.prevValues.length === this.payload.values.length && this.hasPrevData()) {
      const prevEntries: JArrayList<EntryOhos> = new JArrayList<EntryOhos>();
      for (let i = 0; i < this.payload.prevValues.length; i++) {
        prevEntries.add(new EntryOhos(i, this.payload.prevValues[i]));
      }
      const ghost: LineDataSet = new LineDataSet(prevEntries, '上期');
      ghost.setMode(Mode.CUBIC_BEZIER);
      ghost.setDrawCircles(false);
      ghost.setColorByColor(GHOST_LINE);
      ghost.setLineWidth(1.6);
      // 虚线是「这是参考值，不是主数据」最省字的表达
      ghost.enableDashedLine(6, 5, 0);
      ghost.setDrawValues(false);
      ghost.setDrawFilled(false);
      ghost.setHighLightColor(GHOST_LINE);
      sets.add(ghost);
    }

    const set: LineDataSet = new LineDataSet(entries, '减排量');
    set.setMode(Mode.CUBIC_BEZIER);
    set.setDrawCircles(true);
    set.setDrawCircleHole(false);
    set.setCircleColor(GREEN);
    set.setCircleRadius(3.5);
    set.setColorByColor(GREEN);
    set.setLineWidth(2.5);
    set.setDrawValues(false);
    set.setHighLightColor(GREEN);

    // 渐变面积填充：从 30% 绿渐隐到全透明。
    // 官方数据可视化规范鼓励「用渐变增强数据的可读性与色彩的细腻程度」，
    // 同时纯折线在大屏上显得空，填充后整体更饱满。
    set.setDrawFilled(true);
    const fillStops: JArrayList<ChartColorStop> = new JArrayList<ChartColorStop>();
    // 面积填充：主色 30% → 全透明。色值从 Brand.PRIMARY 推导，
    // 避免在图表里再写一份绿色（改主色时这里会自动跟着变）。
    fillStops.add([`#4D${Brand.PRIMARY.substring(1)}`, 0.0]);
    fillStops.add([`#00${Brand.PRIMARY.substring(1)}`, 1.0]);
    set.setGradientFillColor(fillStops);

    sets.add(set);
    const data: LineData = new LineData(sets);

    this.model.setData(data);

    // 关掉默认水印
    const desc = this.model.getDescription();
    if (desc !== null) {
      desc.setEnabled(false);
    }

    // 关掉图例（单条数据不需要图例说明）
    const legend = this.model.getLegend();
    if (legend !== null) {
      legend.setEnabled(false);
    }
    // 这三点让图表从「可交互控件」变成「信息图」：固定视野、不可拖拽缩放
    this.model.setScaleEnabled(false);
    this.model.setTouchEnabled(false);
    this.model.setDrawGridBackground(false);

    // X 轴显示业务标签而不是索引；竖网格线与轴线一律不画
    const xAxis = this.model.getXAxis();
    if (xAxis !== null) {
      xAxis.setValueFormatter(new AxisLabelFormatter(this.payload.labels));
      xAxis.setGranularity(1);
      xAxis.setLabelRotationAngle(this.payload.labels.length > 10 ? -45 : 0);
      cleanAxis(xAxis, true);
    }
    // 右轴与左轴刻度完全相同，属于纯噪音，直接关掉
    const axisRight = this.model.getAxisRight();
    if (axisRight !== null) {
      axisRight.setEnabled(false);
    }
    // 左轴只留几档淡淡的水位线
    softHorizontalGrid(this.model.getAxisLeft());

    this.model.notifyDataSetChanged();
    this.model.invalidate();
  }

  build() {
    LineChart({ model: this.model })
      .width('100%')
      .height('100%')
  }
}

// ---------------------------------------------------------------------------
// 柱状图：分类对比
// ---------------------------------------------------------------------------

@Component
export struct CategoryBarChart {
  @Prop @Watch('rebuild') payload: ChartPayload = new ChartPayload();

  private model: BarChartModel = new BarChartModel();

  aboutToAppear(): void {
    this.rebuild();
  }

  rebuild(): void {
    if (this.payload.values.length === 0) {
      return;
    }
    const entries: JArrayList<BarEntry> = new JArrayList<BarEntry>();
    for (let i = 0; i < this.payload.values.length; i++) {
      entries.add(new BarEntry(i, this.payload.values[i]));
    }

    const set: BarDataSet = new BarDataSet(entries, '减排量');
    // 柱顶标数值：图上没有数字，读者就得自己去对 Y 轴刻度，这是信息损耗
    set.setDrawValues(true);
    set.setValueFormatter(new BarValueFormatter());
    set.setValueTextColor(0x99000000);
    set.setValueTextSize(10);
    set.setBarShadowColor(0x00000000);
    set.setHighLightColor(GREEN);

    // 柱子用竖向渐变：顶部饱和、底部渐浅，比纯色更有体积感
    const barFills: JArrayList<Fill> = new JArrayList<Fill>();
    for (let i = 0; i < this.payload.values.length; i++) {
      barFills.add(new Fill([Brand.PRIMARY, Brand.LIGHT]));
    }
    set.setGradientColors(barFills);

    const sets: JArrayList<IBarDataSet> = new JArrayList<IBarDataSet>();
    sets.add(set);
    const data: BarData = new BarData(sets);
    // mpchart 的柱子画不出圆角（BarDataSet 没有圆角 API），
    // 那就把柱宽收窄到 0.42 —— 细柱子本身就显得轻盈，是这里能做的最优解。
    data.setBarWidth(0.42);

    this.model.setData(data);

    const desc = this.model.getDescription();
    if (desc !== null) {
      desc.setEnabled(false);
    }

    const legend = this.model.getLegend();
    if (legend !== null) {
      legend.setEnabled(false);
    }
    this.model.setScaleEnabled(false);
    this.model.setTouchEnabled(false);
    this.model.setDrawGridBackground(false);

    const xAxis = this.model.getXAxis();
    if (xAxis !== null) {
      xAxis.setValueFormatter(new AxisLabelFormatter(this.payload.labels));
      xAxis.setGranularity(1);
      cleanAxis(xAxis, true);
    }
    const axisRight = this.model.getAxisRight();
    if (axisRight !== null) {
      axisRight.setEnabled(false);
    }
    // 柱状图从 0 起才有可比性，并留出顶部空间
    const axisLeft = this.model.getAxisLeft();
    if (axisLeft !== null) {
      axisLeft.setAxisMinimum(0);
      axisLeft.setSpaceTop(18);
      softHorizontalGrid(axisLeft);
    }

    this.model.notifyDataSetChanged();
    this.model.invalidate();
  }

  build() {
    BarChart({ model: this.model })
      .width('100%')
      .height('100%')
  }
}

// ---------------------------------------------------------------------------
// 饼图：分类占比
// ---------------------------------------------------------------------------

@Component
export struct CategoryPieChart {
  @Prop @Watch('rebuild') payload: ChartPayload = new ChartPayload();

  private model: PieChartModel = new PieChartModel();

  aboutToAppear(): void {
    this.rebuild();
  }

  rebuild(): void {
    if (this.payload.values.length === 0) {
      return;
    }
    const entries: JArrayList<PieEntry> = new JArrayList<PieEntry>();
    let hasPositive: boolean = false;
    for (let i = 0; i < this.payload.values.length; i++) {
      const v: number = this.payload.values[i];
      if (v > 0) {
        hasPositive = true;
      }
      // 扇区的 entry label 传空串：占比信息由卡片下方的原生图例承担，
      // 再在扇区上写一遍类目名就成了重复信息（实测那行白字压在色环上很脏）。
      entries.add(new PieEntry(v, ''));
    }
    // 全 0 数据不设置，避免饼图出现除零或空扇区异常
    if (!hasPositive) {
      return;
    }

    const set: PieDataSet = new PieDataSet(entries, '');
    set.setColorsByArr(pieColors());
    /**
     * ⚠️ 这里关掉扇区内的数值标签，是修掉一个**真 bug**。
     *
     * v1 的写法是：setDrawValues(true) + 自定义 formatter(value / total * 100)，
     * 同时又打开 setUsePercentValues(true)。mpchart 在 percent 模式下传给
     * formatter 的 value **已经是百分数**，于是发生双重换算：
     *     100 / 3.52 * 100 = 2841%
     * 实测截图里饼图上就写着「2841%」。而且扇区标签和数值标签都画在
     * INSIDE_SLICE 的同一位置，两串文字直接叠在一起糊成一团。
     *
     * 修复方式：扇区上不写字，把「占比」交给卡片下方由 ArkUI 原生绘制的
     * 图例（色点 + 数值 + 百分比 + 进度条）—— 可控、好看、还能顺便做动效。
     */
    set.setDrawValues(false);
    set.setSliceSpace(2);

    const data: PieData = new PieData(set as IPieDataSet);

    // 中心区不再写死「分类占比」（卡片标题已经写了），改显示最有价值的信息：总量。
    // ⚠️ mpchart 的中心文字是单行 fillText，不支持 \n 换行，所以只能放一行。
    let sum: number = 0;
    for (let i = 0; i < this.payload.values.length; i++) {
      if (this.payload.values[i] > 0) {
        sum += this.payload.values[i];
      }
    }

    this.model.setUsePercentValues(true);
    this.model.setDrawHoleEnabled(true);
    this.model.setHoleRadius(62);
    this.model.setTransparentCircleRadius(0);
    this.model.setDrawCenterText(true);
    this.model.setCenterText(`${Math.round(sum * 100) / 100} kg`);
    this.model.setCenterTextSize(15);
    this.model.setCenterTextColor(0xE5000000);

    // 扇区之间留一点缝，让"几块"这件事看得出来
    const desc = this.model.getDescription();
    if (desc !== null) {
      desc.setEnabled(false);
    }
    // mpchart 默认图例是小方块，与本应用的圆角语言不符，关掉后用 ArkUI 自绘
    const legend = this.model.getLegend();
    if (legend !== null) {
      legend.setEnabled(false);
    }

    this.model.setData(data);
    this.model.notifyDataSetChanged();
    this.model.invalidate();
  }

  build() {
    PieChart({ model: this.model })
      .width('100%')
      .height('100%')
  }
}
