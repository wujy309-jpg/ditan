/**
 * 我的年度碳迹 —— 年度报告页（全屏）
 *
 * 参考「网易云音乐年度报告」的本质：**大数字卡片的分页串烧**。
 * 所以这一页刻意不做图表 —— 图表是「看板」页的职责；年度报告要的是
 * 「超大数字 + 小标签 + 一句话结论」的情绪冲击，一屏只讲一件事。
 *
 * 页面结构（自上而下）：
 *   1. 渐变英雄区：左上角关闭按钮 + 「我的年度碳迹 / 2026 年度」+ 昵称
 *      + 一句总结语 + 底部两枚小胶囊（活跃天数 / 记录条数）；
 *   2. 七张数字卡：全年累计减排 / 相当于种下 / 低碳记录 / 最长连续记录 /
 *      主力贡献 / 最常做的一件事 / 碳积分 —— 每张卡左侧一个 40×40 图标块
 *      （本工程统一的「卡片有图形」语言），数字用 Weight.DISPLAY（Normal），
 *      单位小两档 + Ink.L3 且与数字**底部对齐**；
 *   3. 减排构成：四个类目各一行 RankRow（色点 + 数值 + 百分比 + 渐变条）；
 *   4. 结尾：一句话 + 隐私说明 + 折算口径 + 胶囊「完成」按钮。
 *
 * 数据：**只读**。`listBehaviors()` 一次取全量，活跃天数 / 最长连续 / 类目占比 /
 *      行为名频次全部在内存里算完，不循环调用 behaviorsBetween。
 *
 * 严格模式备忘：无 any / 无展开 / 无解构；回调一律 `() => {}`；
 *      成员变量名避开 ArkUI 通用属性名（padding / size / width / height / color ...）；
 *      颜色全部走 Theme 令牌，只有压在绿渐变上的**装饰性反白**就近定义（见 DECO_*）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CarbonRepository, POINTS_PER_KG } from '../data/CarbonRepository';
import {
  ALL_CATEGORIES,
  BehaviorRecord,
  Category,
  categoryLabel,
  Profile,
  round2,
  today
} from '../model/Models';
import { catColor, catSoft, EmptyHint, HeroCard, RankRow, SectionCard } from './Common';
import {
  Bg, Brand, CatColor, Edge, ENTER_OFFSET, FontSize, Ink, LineHeight, Motion, Radius,
  Semantic, Space, Weight, buttonGradient, shadowCard
} from '../common/Theme';

const DOMAIN: number = 0x0001;
const TAG: string = 'YearReport';

/** 一棵树一年约吸收 18 kg CO₂e（与看板页 / SmartService 同口径，答辩口径要一致） */
const KG_PER_TREE_PER_YEAR: number = 18;

/**
 * 压在绿渐变上的**装饰性**半透明白。
 * 它们不是语义色（不表达任何状态），只做「玻璃厚度」的反白分层，
 * 与看板 / 积分 / 科普三页的英雄区同语言，属于局部装饰，故就近定义、不进 Theme 令牌。
 */
const DECO_PILL: string = '#26FFFFFF';
const DECO_ART: string = '#33FFFFFF';

// ---------------------------------------------------------------------------
// 报告用到的两种数据形状
// ---------------------------------------------------------------------------

/** 一张「超大数字」卡：左侧 40×40 图标块，右侧小标签 + 大数字 + 一句话结论 */
interface StatCard {
  /** ForEach 的 key，必须唯一 */
  key: string;
  /** 小标签：这张卡在说什么 */
  label: string;
  /** 超大数字（已格式化为字符串） */
  value: string;
  /** 单位，与数字底部对齐 */
  unit: string;
  /** 一句话结论 */
  note: string;
  icon: Resource;
  /** 图标颜色 */
  iconInk: string;
  /** 图标块底色（浅色底，与 iconInk 成对使用） */
  iconSoft: string;
  /** 数字颜色 */
  numInk: string;
  /** 是否用最大的一档字号：全页只有「全年累计减排」一张，保证主次分明 */
  strong: boolean;
}

/** 分类条形行：字段与 Common 的 RankRow 参数一一对应 */
interface CatRow {
  key: string;
  label: string;
  value: string;
  percent: number;
  color: string;
}

// ---------------------------------------------------------------------------
// 纯计算辅助（不碰 UI、不碰存储，便于单独校对）
// ---------------------------------------------------------------------------

/** 千分位整数。本页数据都是非负量，不做负号特判 */
function thousands(n: number): string {
  const s: string = `${Math.round(n)}`;
  let out: string = '';
  let seen: number = 0;
  for (let i = s.length - 1; i >= 0; i--) {
    out = s.charAt(i) + out;
    seen = seen + 1;
    if (seen % 3 === 0 && i > 0) {
      out = ',' + out;
    }
  }
  return out;
}

/** kg 数值的展示口径：≥1000 走千分位整数，否则保留两位小数内的原值 */
function fmtKg(n: number): string {
  if (n >= 1000) {
    return thousands(n);
  }
  return `${round2(n)}`;
}

/**
 * 'YYYY-MM-DD' → 距 1970-01-01 的天序号。
 * 用 Date.UTC 归一，避免夏令时 / 时区把相邻两天算成 23 或 25 小时；
 * 闰年与大小月全部交给 Date 自己处理，不手写日历。
 * 解析失败（脏数据）时返回 NaN —— 下方比较全部为 false，只会打断连续，不会抛错。
 */
function dayNumber(dateStr: string): number {
  const y: number = Number.parseInt(dateStr.substring(0, 4), 10);
  const m: number = Number.parseInt(dateStr.substring(5, 7), 10);
  const d: number = Number.parseInt(dateStr.substring(8, 10), 10);
  return Math.round(Date.UTC(y, m - 1, d) / 86400000);
}

/**
 * 最长连续记录天数。入参必须是**已去重、已按字典序升序**的日期数组
 * （'YYYY-MM-DD' 定长零填充，字典序即时间序）。
 */
function longestStreak(sortedDates: string[]): number {
  if (sortedDates.length === 0) {
    return 0;
  }
  let best: number = 1;
  let cur: number = 1;
  let prev: number = dayNumber(sortedDates[0]);
  for (let i = 1; i < sortedDates.length; i++) {
    const now: number = dayNumber(sortedDates[i]);
    if (now - prev === 1) {
      cur = cur + 1;
    } else if (now - prev > 1) {
      cur = 1;
    }
    if (cur > best) {
      best = cur;
    }
    prev = now;
  }
  return best;
}

// ---------------------------------------------------------------------------
// 年度报告页
// ---------------------------------------------------------------------------

@Component
export struct YearReportPage {
  /** 数据版本号，父组件刷新时递增（与其余四个页面同一机制） */
  @Prop @Watch('onVersion') version: number = 0;
  /** 关闭回调，由父组件传入 */
  onClose: () => void = () => {
  };

  /** 取完数才渲染，避免大数字先出现 0 再跳变 */
  @State ready: boolean = false;
  /**
   * 报告年份：按打开报告的当年计算。
   * 本页统计的是**全量**历史数据（仓储没有按年切分的接口），所以年份只出现在标题里，
   * 结尾卡会另标「统计截止日期」，两处口径合起来不产生歧义。
   */
  @State reportYear: number = 0;
  /** 报告生成日期（截至今天） */
  @State generatedAt: string = '';
  /** 入场动画开关：只置 true、不回退。刷新时不重播，避免内容二次淡入 */
  @State entered: boolean = false;

  @State nickname: string = '低碳生活家';
  /** 全年累计减排 kg CO₂e */
  @State totalSaved: number = 0;
  /** 记录条数 */
  @State recordCount: number = 0;
  /** 活跃天数（不同日期数） */
  @State activeDays: number = 0;
  /** 最长连续记录天数 */
  @State streakDays: number = 0;
  /** 碳积分余额 */
  @State points: number = 0;

  /** 七张数字卡（取数后一次性整体赋值，只触发一次刷新） */
  @State cards: StatCard[] = [];
  /** 四个类目的条形数据 */
  @State catRows: CatRow[] = [];

  aboutToAppear(): void {
    this.reportYear = new Date().getFullYear();
    this.generatedAt = today();
    this.refresh();
  }

  onVersion(): void {
    this.refresh();
  }

  // ------------------------------------------------------------------
  // 取数 + 统计（只读）
  // ------------------------------------------------------------------

  private async refresh(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      // 数据层尚未初始化：不把全屏页卡在加载态，直接渲染一份空报告（全是 0）
      this.ready = true;
      return;
    }
    try {
      // 一次取全量，后续统计全部在内存里做
      const list: BehaviorRecord[] = await repo.listBehaviors();

      // ---- 累计减排 + 记录条数 ----
      let sum: number = 0;
      for (let i = 0; i < list.length; i++) {
        sum += list[i].saved;
      }
      this.totalSaved = round2(sum);
      this.recordCount = list.length;

      // ---- 活跃天数 ----
      // 用「数组去重」而不是 Set，与工程其余部分的写法保持一致
      const dates: string[] = [];
      for (let i = 0; i < list.length; i++) {
        const d: string = list[i].date;
        if (d.length > 0 && dates.indexOf(d) < 0) {
          dates.push(d);
        }
      }
      // 'YYYY-MM-DD' 定长零填充，字典序即时间序（比较器写法与仓储层的排序保持一致）
      dates.sort((a: string, b: string): number => {
        if (a < b) {
          return -1;
        }
        if (a > b) {
          return 1;
        }
        return 0;
      });
      this.activeDays = dates.length;
      this.streakDays = longestStreak(dates);

      // ---- 四个类目的减排量小计 ----
      const sums: number[] = [];
      for (let c = 0; c < ALL_CATEGORIES.length; c++) {
        let s: number = 0;
        for (let i = 0; i < list.length; i++) {
          if (list[i].category === ALL_CATEGORIES[c]) {
            s += list[i].saved;
          }
        }
        sums.push(round2(s));
      }
      let catSum: number = 0;
      for (let c = 0; c < sums.length; c++) {
        catSum += sums[c];
      }
      catSum = round2(catSum);

      const rows: CatRow[] = [];
      let topKey: string = '';
      let topKg: number = 0;
      for (let c = 0; c < ALL_CATEGORIES.length; c++) {
        if (sums[c] > topKg) {
          topKg = sums[c];
          topKey = ALL_CATEGORIES[c];
        }
        const row: CatRow = {
          key: ALL_CATEGORIES[c],
          label: categoryLabel(ALL_CATEGORIES[c]),
          value: `${sums[c]} kg`,
          percent: catSum > 0 ? Math.round(sums[c] / catSum * 100) : 0,
          color: catColor(ALL_CATEGORIES[c])
        };
        rows.push(row);
      }
      this.catRows = rows;
      const topPercent: number = catSum > 0 ? Math.round(topKg / catSum * 100) : 0;

      // ---- 最常做的一件事：按行为名（快照名）统计出现次数 ----
      const names: string[] = [];
      const counts: number[] = [];
      for (let i = 0; i < list.length; i++) {
        const n: string = list[i].name;
        const idx: number = names.indexOf(n);
        if (idx < 0) {
          names.push(n);
          counts.push(1);
        } else {
          counts[idx] = counts[idx] + 1;
        }
      }
      let topName: string = '';
      let topCount: number = 0;
      for (let i = 0; i < counts.length; i++) {
        if (counts[i] > topCount) {
          topCount = counts[i];
          topName = names[i];
        }
      }

      // ---- 积分与档案 ----
      this.points = await repo.pointsBalance();
      const profile: Profile = await repo.getProfile();
      this.nickname = profile.nickname.length > 0 ? profile.nickname : '低碳生活家';

      this.buildCards(topKey, topKg, topPercent, topName, topCount);
      this.ready = true;
    } catch (e) {
      // 读失败也要让页面出来：全屏页停在加载态比数字不准更糟
      hilog.error(DOMAIN, TAG, 'load year report failed: %{public}s', JSON.stringify(e));
      this.ready = true;
    }
  }

  /** 组装七张数字卡。顺序即阅读顺序：先总量，再情绪，最后落到积分 */
  private buildCards(topKey: string, topKg: number, topPercent: number,
    topName: string, topCount: number): void {
    const out: StatCard[] = [];

    // 1) 全年累计减排 —— 全页最大的一个数字
    const savedCard: StatCard = {
      key: 'saved',
      label: '全年累计减排',
      value: fmtKg(this.totalSaved),
      unit: 'kg CO₂e',
      note: this.totalSaved > 0 ? '这是你这一年来为地球减下的碳排放' : '还没有数据，去「记一笔」写下第一条',
      icon: $r('app.media.ic_leaf'),
      iconInk: Brand.PRIMARY,
      iconSoft: Brand.SOFT,
      numInk: Brand.PRIMARY,
      strong: true
    };
    out.push(savedCard);

    // 2) 相当于种树
    const trees: number = Math.round(this.totalSaved / KG_PER_TREE_PER_YEAR * 10) / 10;
    const treeCard: StatCard = {
      key: 'trees',
      label: '相当于种下',
      value: `${trees.toFixed(1)}`,
      unit: '棵树·年',
      note: `按一棵树每年吸收 ${KG_PER_TREE_PER_YEAR} kg CO₂e 折算`,
      icon: $r('app.media.ic_tree'),
      iconInk: Semantic.CONFIRM,
      iconSoft: Semantic.CONFIRM_SOFT,
      numInk: Ink.L1,
      strong: false
    };
    out.push(treeCard);

    // 3) 低碳记录：条数 + 活跃天数
    const avg: number = this.activeDays > 0 ? round2(this.totalSaved / this.activeDays) : 0;
    const recordCard: StatCard = {
      key: 'records',
      label: '低碳记录',
      value: thousands(this.recordCount),
      unit: '条',
      note: this.recordCount > 0
        ? `分布在 ${this.activeDays} 天，有记录的日子平均 ${avg} kg`
        : '还没有任何记录',
      icon: $r('app.media.ic_tab_book'),
      iconInk: Semantic.INFO,
      iconSoft: Semantic.INFO_SOFT,
      numInk: Ink.L1,
      strong: false
    };
    out.push(recordCard);

    // 4) 最长连续记录 —— 最有情绪价值的一项，与累计减排同用最大字号
    const streakCard: StatCard = {
      key: 'streak',
      label: '最长连续记录',
      value: `${this.streakDays}`,
      unit: '天',
      note: this.streakNote(),
      icon: $r('app.media.ic_flame'),
      iconInk: Semantic.ALERT,
      iconSoft: Semantic.ALERT_SOFT,
      numInk: Semantic.ALERT,
      // 不做「最大的一张」：全页只有「全年累计减排」用 DISPLAY_S，
      // 这一张靠火苗图标 + 橙色数字拿情绪价值，字号更高反而会稀释主次
      strong: false
    };
    out.push(streakCard);

    // 5) 主力贡献：减排量最高的类目
    const hasCat: boolean = topKg > 0;
    const topCatCard: StatCard = {
      key: 'topcat',
      label: hasCat ? `主力贡献 · ${categoryLabel(topKey)}` : '主力贡献',
      value: hasCat ? fmtKg(topKg) : '0',
      unit: 'kg CO₂e',
      note: hasCat ? `占全年减排的 ${topPercent}%` : '还没有可以统计的类目',
      icon: hasCat ? this.catIcon(topKey) : $r('app.media.ic_leaf'),
      iconInk: hasCat ? catColor(topKey) : Brand.PRIMARY,
      iconSoft: hasCat ? catSoft(topKey) : Brand.SOFT,
      numInk: Ink.L1,
      strong: false
    };
    out.push(topCatCard);

    // 6) 最常做的一件事：按行为名统计的众数
    const hasAction: boolean = topCount > 0;
    const actionCard: StatCard = {
      key: 'action',
      label: '最常做的一件事',
      value: thousands(topCount),
      unit: '次',
      note: hasAction ? `「${topName}」是你重复最多的一次低碳行为` : '还没有可以统计的行为',
      icon: $r('app.media.ic_check'),
      iconInk: CatColor.FOOD,
      iconSoft: CatColor.FOOD_SOFT,
      numInk: Ink.L1,
      strong: false
    };
    out.push(actionCard);

    // 7) 碳积分
    const pointsCard: StatCard = {
      key: 'points',
      label: '碳积分',
      value: thousands(this.points),
      unit: '分',
      note: `每减排 1 kg CO₂e 得 ${POINTS_PER_KG} 积分，可在「积分」页兑换权益`,
      icon: $r('app.media.ic_tab_medal'),
      iconInk: Brand.PRIMARY,
      iconSoft: Brand.SOFT,
      numInk: Ink.L1,
      strong: false
    };
    out.push(pointsCard);

    this.cards = out;
  }

  /** 英雄区的一句总结语：随累计减排量换口吻 */
  private heroLine(): string {
    if (this.recordCount === 0) {
      return '新的一年，从第一条低碳记录开始';
    }
    if (this.totalSaved >= 100) {
      return '这一年，你为地球做了一件了不起的小事';
    }
    if (this.totalSaved >= 30) {
      return '这一年，你让地球轻松了一点';
    }
    if (this.totalSaved >= 5) {
      return '这一年，你已经开始改变';
    }
    return '涓滴成河，你已经出发了';
  }

  /** 连续记录天数的情绪化注解 */
  private streakNote(): string {
    if (this.streakDays >= 7) {
      return '连续一周以上，低碳已经成了习惯';
    }
    if (this.streakDays >= 3) {
      return '连续三天以上，节奏已经稳了';
    }
    if (this.streakDays >= 1) {
      return '连续记录刚刚起步，再坚持两天试试';
    }
    return '还没有连续记录，从今天开始也不晚';
  }

  /** 类目 → 图标（只用 app.media 下确实存在的图标） */
  private catIcon(c: string): Resource {
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

  build() {
    Column() {
      Scroll() {
        Column() {
          if (!this.ready) {
            // 取数期间的占位。不放骨架屏：数据在本地 KV，通常一帧内就回来了
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(Brand.PRIMARY)
              Text('正在生成你的年度碳迹…')
                .fontSize(FontSize.BODY_M)
                .fontColor(Ink.L2)
                .margin({ top: Space.MD })
            }
            .width('100%')
            .height(260)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            Column() {
              // ============ 1. 英雄区 ============
              HeroCard({ variant: 'brand' }) {
                // 关闭按钮：ic_arrow 默认朝右，转 180° 即「返回 / 关闭」
                Row() {
                  Column() {
                    Image($r('app.media.ic_arrow'))
                      .width(18)
                      .height(18)
                      .fillColor(Ink.ON_BRAND)
                      .objectFit(ImageFit.Contain)
                      .rotate({ angle: 180 })
                  }
                  .width(36)
                  .height(36)
                  .borderRadius(Radius.FULL)
                  .backgroundColor(DECO_PILL)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .onClick(() => {
                    this.onClose();
                  })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                Row() {
                  Column() {
                    Text('我的年度碳迹')
                      .fontSize(FontSize.BODY_S)
                      .fontColor(Ink.ON_BRAND_2)

                    Row() {
                      Text(`${this.reportYear}`)
                        .fontSize(FontSize.DISPLAY_M)
                        .fontWeight(Weight.DISPLAY)
                        .fontColor(Ink.ON_BRAND)
                      Text('年度')
                        .fontSize(FontSize.SUB_M)
                        .fontColor(Ink.ON_BRAND_2)
                        .margin({ left: 5, bottom: 8 })
                    }
                    .alignItems(VerticalAlign.Bottom)
                    .margin({ top: 2 })

                    Text(this.nickname)
                      .fontSize(FontSize.TITLE_S)
                      .fontWeight(Weight.TITLE)
                      .fontColor(Ink.ON_BRAND)
                      .margin({ top: Space.SM })

                    Text(this.heroLine())
                      .fontSize(FontSize.BODY_S)
                      .fontColor(Ink.ON_BRAND_2)
                      .lineHeight(LineHeight.BODY_S)
                      .margin({ top: 4 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  // 大号半透明树叶：纯装饰，不承载信息
                  Image($r('app.media.ic_leaf'))
                    .width(72)
                    .height(72)
                    .fillColor(DECO_ART)
                    .objectFit(ImageFit.Contain)
                    .margin({ left: Space.SM })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .margin({ top: Space.LG })

                // 英雄区底部两枚小胶囊：把「活跃天数 / 记录条数」提前透出来
                Row() {
                  Text(`活跃 ${this.activeDays} 天`)
                    .fontSize(FontSize.BODY_S)
                    .fontColor(Ink.ON_BRAND)
                    .backgroundColor(DECO_PILL)
                    .borderRadius(Radius.FULL)
                    .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                  Text(`${this.recordCount} 条记录`)
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

              // ============ 2. 空态提示（有数据时不出现） ============
              if (this.recordCount === 0) {
                Column() {
                  EmptyHint({
                    title: '这一年还没有碳迹',
                    desc: '去「记一笔」记下第一条低碳行为，这里的大数字就会长出来。',
                    icon: $r('app.media.ic_leaf')
                  })
                }
                .width('100%')
                .margin({ bottom: Space.MD })
              }

              // ============ 3. 七张数字卡 ============
              ForEach(this.cards, (c: StatCard) => {
                Column() {
                  Row() {
                    // 40×40 圆角图标块：整页统一的「先有图形，再读文字」
                    Column() {
                      Image(c.icon)
                        .width(20)
                        .height(20)
                        .fillColor(c.iconInk)
                        .objectFit(ImageFit.Contain)
                    }
                    .width(40)
                    .height(40)
                    .borderRadius(Radius.SM)
                    .backgroundColor(c.iconSoft)
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)

                    Column() {
                      Text(c.label)
                        .fontSize(FontSize.BODY_S)
                        .fontColor(Ink.L2)
                        .width('100%')

                      // 大数字 + 单位：数字用 Normal 字重（Display 级用 Bold 会显笨重），
                      // 单位小两档、Ink.L3、**底部对齐**
                      Row() {
                        Text(c.value)
                          .fontSize(c.strong ? FontSize.DISPLAY_S : FontSize.TITLE_L)
                          .fontWeight(Weight.DISPLAY)
                          .fontColor(c.numInk)
                        if (c.unit.length > 0) {
                          Text(c.unit)
                            .fontSize(FontSize.SUB_S)
                            .fontColor(Ink.L3)
                            .margin({ left: 5, bottom: c.strong ? 7 : 5 })
                        }
                      }
                      .alignItems(VerticalAlign.Bottom)
                      .margin({ top: 2 })

                      Text(c.note)
                        .fontSize(FontSize.BODY_S)
                        .fontColor(Ink.L3)
                        .lineHeight(LineHeight.BODY_S)
                        .width('100%')
                        .margin({ top: 4 })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    .margin({ left: Space.MD })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                }
                .width('100%')
                .padding(Space.LG)
                // 统一白卡：层级不靠底色，靠「数字大小 + 数字颜色 + 图标色」区分。
                // （不用 Brand.MIST 铺底：它 #F2F9F5 与页面底 Bg.PAGE #F1F3F5 几乎同色，
                //   卡片会「陷进」背景里，反而看不出层级）
                .backgroundColor(Bg.CARD)
                .borderRadius(Radius.MD)
                .shadow(shadowCard())
                .margin({ bottom: Space.MD })
              }, (c: StatCard) => c.key)

              // ============ 4. 减排构成（四行分类条形） ============
              SectionCard({
                title: '减排构成',
                icon: $r('app.media.ic_tab_chart'),
                showIcon: true,
                badge: `${this.catRows.length} 个类目`,
                badgeColor: Brand.PRIMARY,
                badgeSoft: Brand.SOFT
              }) {
                Text('条形长度即占比，颜色与看板页的饼图一一对应')
                  .fontSize(FontSize.BODY_S)
                  .fontColor(Ink.L3)
                  .width('100%')
                  .margin({ bottom: Space.MD })

                ForEach(this.catRows, (r: CatRow) => {
                  RankRow({
                    label: r.label,
                    value: r.value,
                    percent: r.percent,
                    color: r.color
                  })
                }, (r: CatRow) => r.key)
              }

              // ============ 5. 结尾 ============
              SectionCard({
                title: '写在最后',
                icon: $r('app.media.ic_leaf'),
                showIcon: true,
                bottomSpace: 0
              }) {
                Text('低碳从来不是一次壮举，而是把一件小事重复很多遍。你记录的每一条，都算数。')
                  .fontSize(FontSize.BODY_M)
                  .fontColor(Ink.L2)
                  .lineHeight(LineHeight.BODY_L)
                  .width('100%')

                Row() {
                  Image($r('app.media.ic_check'))
                    .width(14)
                    .height(14)
                    .fillColor(Brand.PRIMARY)
                    .objectFit(ImageFit.Contain)
                    .margin({ right: 6 })
                  Text('数据全部保存在本机，不上传云端。')
                    .fontSize(FontSize.BODY_S)
                    .fontColor(Ink.L3)
                    .layoutWeight(1)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .margin({ top: Space.MD })

                Text(`统计截止 ${this.generatedAt} · 折算口径：1 棵树·年 ≈ ${KG_PER_TREE_PER_YEAR} kg CO₂e`)
                  .fontSize(FontSize.CAPTION)
                  .fontColor(Ink.L3)
                  .width('100%')
                  .margin({ top: Space.XS })

                Divider()
                  .color(Edge.HAIR)
                  .strokeWidth(1)
                  .margin({ top: Space.MD, bottom: Space.MD })

                Button('完成')
                  .width('100%')
                  .height(48)
                  .fontSize(FontSize.BODY_L)
                  .fontWeight(Weight.SUBTITLE)
                  .fontColor(Ink.ON_BRAND)
                  // 官方约束：Button 设渐变前必须把 backgroundColor 置为透明，否则实色底会盖住渐变
                  .backgroundColor(Color.Transparent)
                  .linearGradient(buttonGradient())
                  .borderRadius(Radius.FULL)
                  .onClick(() => {
                    this.onClose();
                  })
              }
            }
            .width('100%')
            // 入场：整块从下方 14vp 滑到位。
            // 刻意**不做透明度淡入** —— 万一挂载回调没触发，滑位只是偏一点，
            // 而 opacity 0 会让整页空白，全屏页不能赌这个。
            .translate({ y: this.entered ? 0 : ENTER_OFFSET })
            .onAppear(() => {
              animateTo(Motion.ENTER, () => {
                this.entered = true;
              });
            })
          }
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
