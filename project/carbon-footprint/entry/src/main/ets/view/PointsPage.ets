/**
 * 积分 —— 主要功能 3：碳积分激励体系 ＋ 创新拓展 3：模拟城市碳普惠平台
 *
 * 两条兑换线，刻意分开，答辩时也更清楚：
 *   · 本地碳积分 → 虚拟徽章 / 植树证书      （赛题「主要功能 3」的原文要求）
 *   · 平台积分   → 城市碳普惠真实权益        （赛题「创新拓展 3」的积分互通）
 * 本地积分可通过「上报」转为平台积分，1:1 互通。
 *
 * ── 本次美化改动（只动视觉结构，业务逻辑一行未改）──────────────────────────
 * v1 的问题：主卡做得不错，但主卡以下全是「名称 + 灰副标题 + 橙色价格 + 按钮」
 * 的价目表 —— 没有图形、没有层级，也没有任何「成就感」表达。本次：
 *   1. 主卡改用 HeroCard（与首页/看板同一套语言），右侧资源位从半透明勋章
 *      换成 RingStat 目标环：把「235 分」变成「离下一个权益还差多少分」；
 *      主卡底部补两枚半透明小胶囊（已兑换次数 / 可用权益数）。
 *   2. 权益行升级为**独立行卡**：40×40 图标色块 + 名称/来源 + 价格/胶囊按钮；
 *      积分不足时整行降对比度（但 enabled 判断逻辑原样保留）。
 *   3. 新增「我的低碳成就」勋章墙（4 枚，阈值直接读 balance，不引入新数据）。
 *   4. 三张内容卡统一走 SectionCard（带图标标题行 + 统一阴影 + 角标）；
 *      分节标题改用 CardTitle。
 *   5. 硬编码色全部换成 Theme.ets 令牌，页面根节点补 Bg.PAGE。
 */
import { CarbonRepository, POINTS_PER_KG } from '../data/CarbonRepository';
import { ApiCode, ApiResult, Benefit, ExchangeOrder, PlatformAccount } from '../data/CarbonInclusiveApi';
import { PointsEntry } from '../model/Models';
import { CardTitle, HeroCard, RingStat, SectionCard } from './Common';
import {
  Bg, Brand, Edge, FontSize, Ink, LineHeight, Radius, Semantic, Space, Weight,
  shadowBrand, shadowSubtle
} from '../common/Theme';

/** 本地可兑换的虚拟奖励 */
interface Reward {
  id: string;
  name: string;
  cost: number;
  desc: string;
}

const REWARDS: Reward[] = [
  { id: 'badge.sprout', name: '低碳新芽徽章', cost: 50, desc: '虚拟徽章 · 迈出第一步的纪念' },
  { id: 'badge.green', name: '绿色先锋徽章', cost: 150, desc: '虚拟徽章 · 连续记录的证明' },
  { id: 'cert.tree', name: '植树证书', cost: 300, desc: '电子证书 · 可生成为分享图' },
  { id: 'cert.carbon', name: '碳中和达人证书', cost: 800, desc: '电子证书 · 累计减排的里程碑' }
];

/**
 * 勋章墙条目。
 * 纯展示：阈值直接与本地碳积分余额比较，**不新增任何数据字段**。
 */
interface BadgeSpec {
  id: string;
  label: string;
  /** 解锁阈值（分） */
  threshold: number;
}

const BADGES: BadgeSpec[] = [
  { id: 'badge.100', label: '低碳新芽', threshold: 100 },
  { id: 'badge.300', label: '绿色先锋', threshold: 300 },
  { id: 'badge.500', label: '减碳达人', threshold: 500 },
  { id: 'badge.1000', label: '碳中和之星', threshold: 1000 }
];

function fmtTime(ts: number): string {
  const d: Date = new Date(ts);
  const mm: string = d.getMonth() + 1 < 10 ? `0${d.getMonth() + 1}` : `${d.getMonth() + 1}`;
  const dd: string = d.getDate() < 10 ? `0${d.getDate()}` : `${d.getDate()}`;
  const hh: string = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`;
  const mi: string = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`;
  return `${mm}-${dd} ${hh}:${mi}`;
}

@Component
export struct PointsPage {
  /** 数据版本号，页签切换时由 Index 递增，用于刷新（原因见 SmartService 注释） */
  @Prop @Watch('onVersion') version: number = 0;

  // 本地积分
  @State balance: number = 0;
  @State ledger: PointsEntry[] = [];

  // 碳普惠平台（创新点 3）
  @State bound: boolean = false;
  @State accountId: string = '';
  @State platformPoints: number = 0;
  @State unreported: number = 0;
  @State benefits: Benefit[] = [];
  @State orders: ExchangeOrder[] = [];
  @State busy: boolean = false;

  @State hint: string = '';
  @State hintOk: boolean = true;

  aboutToAppear(): void {
    this.refresh();
  }

  onVersion(): void {
    this.refresh();
  }

  private async refresh(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    this.balance = await repo.pointsBalance();
    this.ledger = (await repo.listPoints()).slice(0, 10);

    const api = repo.platform();
    const acc: PlatformAccount = await api.getAccount();
    this.bound = acc.bound;
    this.accountId = acc.accountId;
    this.platformPoints = acc.points;
    const gap: number = this.balance - acc.reportedTotal;
    this.unreported = gap > 0 ? gap : 0;
    this.benefits = await api.listBenefits();
    this.orders = (await api.listOrders()).slice(0, 5);
  }

  private say(ok: boolean, text: string): void {
    this.hintOk = ok;
    this.hint = text;
  }

  // ---------------- 本地奖励兑换 ----------------

  private async redeemLocal(r: Reward): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    if (this.balance < r.cost) {
      this.say(false, `积分不足，还差 ${r.cost - this.balance} 分`);
      return;
    }
    await repo.addPoints(-r.cost, `兑换「${r.name}」`);
    this.say(true, `兑换成功：${r.name}`);
    await this.refresh();
  }

  // ---------------- 碳普惠平台 ----------------

  private async bind(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    this.busy = true;
    try {
      const res: ApiResult = await repo.platform().bindAccount(repo.getLocalDeviceId());
      this.say(res.code === ApiCode.OK, res.message);
    } finally {
      this.busy = false;
      await this.refresh();
    }
  }

  private async report(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    if (this.unreported <= 0) {
      this.say(false, '没有需要上报的积分');
      return;
    }
    this.busy = true;
    try {
      const res: ApiResult = await repo.platform().reportPoints(this.unreported);
      this.say(res.code === ApiCode.OK, res.message);
    } finally {
      this.busy = false;
      await this.refresh();
    }
  }

  private async exchange(b: Benefit): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    this.busy = true;
    try {
      const res: ApiResult = await repo.platform().exchange(b.id);
      this.say(res.code === ApiCode.OK, res.message);
    } finally {
      this.busy = false;
      await this.refresh();
    }
  }

  // ---------------- 视觉辅助计算（纯读，不参与业务） ----------------

  /**
   * 下一个「还买不起」的权益价格。
   * 若全部买得起，则返回最贵的一项（用于让目标环收口在 100%）。
   */
  private nextGoalCost(): number {
    let locked: number = 0;
    let maxCost: number = 0;
    for (let i = 0; i < this.benefits.length; i++) {
      const c: number = this.benefits[i].cost;
      if (c > maxCost) {
        maxCost = c;
      }
      if (c > this.balance && (locked === 0 || c < locked)) {
        locked = c;
      }
    }
    if (locked > 0) {
      return locked;
    }
    return maxCost;
  }

  /** 目标环完成度（0–100）：以「下一个可兑换权益」为分母 */
  private goalPercent(): number {
    if (this.benefits.length === 0) {
      return 0;
    }
    const target: number = this.nextGoalCost();
    if (target <= 0) {
      return 100;
    }
    const p: number = Math.round(this.balance / target * 100);
    return p > 100 ? 100 : p;
  }

  /** 距离下一个权益还差多少分（全部解锁时为 0） */
  private goalGap(): number {
    const target: number = this.nextGoalCost();
    const gap: number = target - this.balance;
    return gap > 0 ? gap : 0;
  }

  /** 当前平台积分买得起、且还有库存的权益数量 */
  private usableCount(): number {
    let n: number = 0;
    for (let i = 0; i < this.benefits.length; i++) {
      const b: Benefit = this.benefits[i];
      if (this.platformPoints >= b.cost && b.stock > 0) {
        n++;
      }
    }
    return n;
  }

  /** 权益图标：按 id / 名称关键词匹配（只读，不新增权益数据） */
  private benefitIcon(b: Benefit): Resource {
    // 注意：「地铁」与「单车」原本都落到 ic_travel（走路小人），两张行卡长得一模一样。
    // 为此专门补绘了 ic_metro / ic_bike 两个图标，让权益一眼可辨。
    const key: string = `${b.id} ${b.name}`;
    if (key.indexOf('metro') >= 0 || key.indexOf('地铁') >= 0) {
      return $r('app.media.ic_metro');
    }
    if (key.indexOf('bike') >= 0 || key.indexOf('单车') >= 0) {
      return $r('app.media.ic_bike');
    }
    if (key.indexOf('bag') >= 0 || key.indexOf('袋') >= 0) {
      return $r('app.media.ic_recycle');
    }
    if (key.indexOf('ticket') >= 0 || key.indexOf('公园') >= 0) {
      return $r('app.media.ic_tree');
    }
    if (key.indexOf('power') >= 0 || key.indexOf('电') >= 0) {
      return $r('app.media.ic_energy');
    }
    return $r('app.media.ic_gift');
  }

  /** 权益图标底色：按价格分档取语义浅底，让列表有「图形节奏」 */
  private benefitSoft(b: Benefit): string {
    if (b.cost >= 800) {
      return Semantic.INFO_SOFT;
    }
    if (b.cost >= 500) {
      return Semantic.CONFIRM_SOFT;
    }
    if (b.cost >= 200) {
      return Semantic.ALERT_SOFT;
    }
    if (b.cost >= 100) {
      return Brand.SOFT;
    }
    return Brand.MIST;
  }

  /** 勋章图标：4 枚依次为 芽 → 树 → 火 → 勋章 */
  private badgeIcon(id: string): Resource {
    if (id === 'badge.100') {
      return $r('app.media.ic_leaf');
    }
    if (id === 'badge.300') {
      return $r('app.media.ic_tree');
    }
    if (id === 'badge.500') {
      return $r('app.media.ic_flame');
    }
    return $r('app.media.ic_tab_medal');
  }

  private rewardIcon(r: Reward): Resource {
    if (r.id === 'cert.tree') {
      return $r('app.media.ic_tree');
    }
    if (r.id === 'cert.carbon') {
      return $r('app.media.ic_leaf');
    }
    return $r('app.media.ic_tab_medal');
  }

  private rewardSoft(r: Reward): string {
    if (r.id === 'cert.tree') {
      return Semantic.CONFIRM_SOFT;
    }
    if (r.id === 'cert.carbon') {
      return Brand.SOFT;
    }
    return Brand.MIST;
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // ============ 主卡（第一级）：当前积分 + 目标环 ============
          // 用 HeroCard 统一「页面第一屏」的语言；右侧从装饰性勋章图标换成
          // 目标环 —— 装饰只能好看，目标环能回答「我还差多少」。
          HeroCard({ variant: 'brand' }) {
            Row() {
              Column() {
                Text('当前碳积分')
                  .fontSize(FontSize.BODY_S)
                  .fontColor(Ink.ON_BRAND_2)
                Row() {
                  Text(`${this.balance}`)
                    .fontSize(FontSize.DISPLAY_M)
                    .fontWeight(Weight.DISPLAY)
                    .fontColor(Ink.ON_BRAND)
                  Text('分')
                    .fontSize(FontSize.SUB_S)
                    .fontColor(Ink.ON_BRAND_2)
                    .margin({ left: 5, bottom: 7 })
                }
                .alignItems(VerticalAlign.Bottom)
                .margin({ top: 2 })
                Text(`每减排 1 kg CO₂e 得 ${POINTS_PER_KG} 积分`)
                  .fontSize(FontSize.BODY_S)
                  .fontColor(Ink.ON_BRAND_2)
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              RingStat({
                percent: this.goalPercent(),
                diameter: 96,
                ringWidth: 7,
                trackColor: Edge.ON_BRAND,
                ringColor: Ink.ON_BRAND
              }) {
                Text(`${this.goalPercent()}%`)
                  .fontSize(FontSize.TITLE_S)
                  .fontWeight(Weight.SUBTITLE)
                  .fontColor(Ink.ON_BRAND)
                Text(this.benefits.length === 0
                  ? '待绑定账户'
                  : (this.goalGap() > 0 ? `还差 ${this.goalGap()} 分` : '权益全解锁'))
                  .fontSize(FontSize.CAPTION)
                  .fontColor(Ink.ON_BRAND_2)
                  .margin({ top: 1 })
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 底部两枚小胶囊：参考看板英雄区底部的写法（半透明白底）
            Row() {
              Text(`已兑换 ${this.orders.length} 次`)
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.ON_BRAND)
                .backgroundColor(Edge.ON_BRAND)
                .borderRadius(Radius.FULL)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
              Text(`可用权益 ${this.usableCount()} 项`)
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.ON_BRAND)
                .backgroundColor(Edge.ON_BRAND)
                .borderRadius(Radius.FULL)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                .margin({ left: Space.SM })
            }
            .width('100%')
            .margin({ top: Space.XL })
          }

          if (this.hint.length > 0) {
            Text(this.hint)
              .fontSize(FontSize.BODY_M)
              .fontColor(this.hintOk ? Brand.PRIMARY : Semantic.WARNING)
              .lineHeight(LineHeight.BODY_L)
              .width('100%')
              .padding(Space.MD)
              .backgroundColor(Bg.CARD)
              .borderRadius(Radius.MD)
              .shadow(shadowSubtle())
              .margin({ bottom: Space.MD })
          }

          // ============ 创新点 3：城市碳普惠平台 ============
          SectionCard({
            title: '城市碳普惠平台',
            icon: $r('app.media.ic_sync'),
            showIcon: true,
            badge: '创新点 3',
            badgeColor: Semantic.ALERT,
            badgeSoft: Semantic.ALERT_SOFT
          }) {
            if (!this.bound) {
              Text('绑定城市碳普惠账户后，本地碳积分可 1:1 互通为平台积分，用于兑换地铁券、共享单车券等真实权益。')
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.L2)
                .lineHeight(LineHeight.BODY_S)
                .width('100%')
              Button(this.busy ? '绑定中…' : '绑定碳普惠账户')
                .width('100%')
                .height(40)
                .fontSize(FontSize.BODY_M)
                .backgroundColor(Brand.PRIMARY)
                .fontColor(Ink.ON_BRAND)
                .margin({ top: Space.MD })
                .enabled(!this.busy)
                .onClick(() => {
                  this.bind();
                })
            } else {
              // 平台积分 / 待上报：两个大数字，用语义色区分「已到手」与「待搬运」
              Row() {
                Column() {
                  Text(`${this.platformPoints}`)
                    .fontSize(FontSize.TITLE_M)
                    .fontWeight(Weight.DISPLAY)
                    .fontColor(Brand.PRIMARY)
                  Text('平台积分')
                    .fontSize(FontSize.BODY_S)
                    .fontColor(Ink.L2)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)

                Column() {
                  Text(`${this.unreported}`)
                    .fontSize(FontSize.TITLE_M)
                    .fontWeight(Weight.DISPLAY)
                    .fontColor(Semantic.ALERT)
                  Text('待上报')
                    .fontSize(FontSize.BODY_S)
                    .fontColor(Ink.L2)
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
              }
              .width('100%')
              .padding({ top: Space.SM, bottom: Space.SM })

              Text(`账户号：${this.accountId}`)
                .fontSize(FontSize.CAPTION)
                .fontColor(Ink.L3)
                .width('100%')
                .margin({ top: Space.XS })

              Button(this.busy ? '上报中…' : `上报积分（${this.unreported}）`)
                .width('100%')
                .height(38)
                .fontSize(FontSize.BODY_S)
                .backgroundColor(Brand.SOFT)
                .fontColor(Brand.PRIMARY)
                .margin({ top: Space.SM })
                .enabled(!this.busy && this.unreported > 0)
                .onClick(() => {
                  this.report();
                })

              Divider()
                .color(Edge.HAIR)
                .strokeWidth(1)
                .margin({ top: Space.LG, bottom: Space.MD })

              CardTitle({
                title: '可兑换权益',
                icon: $r('app.media.ic_share'),
                showIcon: true
              })
                .margin({ bottom: Space.MD })

              // 每项权益 = 一张浅底行卡：图标色块 + 名称/来源 + 价格/胶囊按钮
              ForEach(this.benefits, (b: Benefit) => {
                Row() {
                  Column() {
                    Image(this.benefitIcon(b))
                      .width(20)
                      .height(20)
                      .fillColor(this.platformPoints >= b.cost ? Brand.PRIMARY : Ink.L4)
                      .objectFit(ImageFit.Contain)
                  }
                  .width(40)
                  .height(40)
                  .borderRadius(Radius.SM)
                  .backgroundColor(this.platformPoints >= b.cost ? this.benefitSoft(b) : Bg.SUBTLE)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .margin({ right: Space.MD })

                  Column() {
                    Text(b.name)
                      .fontSize(FontSize.BODY_M)
                      .fontWeight(Weight.SUBTITLE)
                      .fontColor(this.platformPoints >= b.cost ? Ink.L1 : Ink.L3)
                      .maxLines(1)
                    Text(`${b.provider} · 余 ${b.stock}`)
                      .fontSize(FontSize.CAPTION)
                      .fontColor(this.platformPoints >= b.cost ? Ink.L3 : Ink.L4)
                      .maxLines(1)
                      .margin({ top: 3 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Column() {
                    Text(`${b.cost} 分`)
                      .fontSize(FontSize.BODY_S)
                      .fontWeight(Weight.SUBTITLE)
                      .fontColor(this.platformPoints >= b.cost ? Semantic.ALERT : Ink.L4)
                    Button('兑换')
                      .fontSize(FontSize.BODY_S)
                      .height(32)
                      .padding({ left: 14, right: 14 })
                      .borderRadius(Radius.FULL)
                      .backgroundColor(this.platformPoints >= b.cost ? Brand.PRIMARY : Bg.SUBTLE)
                      .fontColor(this.platformPoints >= b.cost ? Ink.ON_BRAND : Ink.L3)
                      .margin({ top: 6 })
                      .enabled(!this.busy)
                      .onClick(() => {
                        this.exchange(b);
                      })
                  }
                  .alignItems(HorizontalAlign.End)
                  .margin({ left: Space.SM })
                }
                .width('100%')
                .padding(Space.MD)
                .backgroundColor(Bg.CARD)
                .borderRadius(Radius.MD)
                .border({ width: 1, color: Edge.HAIR })
                .shadow(shadowSubtle())
                .margin({ bottom: Space.SM })
                .alignItems(VerticalAlign.Center)
              }, (b: Benefit) => b.id)

              if (this.orders.length > 0) {
                Divider()
                  .color(Edge.HAIR)
                  .strokeWidth(1)
                  .margin({ top: Space.SM, bottom: Space.MD })

                CardTitle({
                  title: '兑换记录',
                  icon: $r('app.media.ic_check'),
                  showIcon: true
                })
                  .margin({ bottom: Space.SM })

                ForEach(this.orders, (o: ExchangeOrder) => {
                  Row() {
                    Text(o.benefitName)
                      .fontSize(FontSize.BODY_S)
                      .fontColor(Ink.L2)
                      .layoutWeight(1)
                      .maxLines(1)
                    Text(`-${o.cost}`)
                      .fontSize(FontSize.BODY_S)
                      .fontWeight(Weight.SUBTITLE)
                      .fontColor(Semantic.WARNING)
                    Text(o.orderId.substring(0, 12))
                      .fontSize(FontSize.CAPTION)
                      .fontColor(Ink.L3)
                      .margin({ left: Space.SM })
                  }
                  .width('100%')
                  .padding({ top: 5, bottom: 5 })
                }, (o: ExchangeOrder) => o.orderId)
              }

              Text('说明：城市碳普惠平台无公开个人 API，此处为本地模拟实现，保留了真实接口的异步、错误码、库存与幂等语义。')
                .fontSize(FontSize.CAPTION)
                .fontColor(Ink.L3)
                .lineHeight(LineHeight.BODY_S)
                .width('100%')
                .margin({ top: Space.MD })
            }
          }

          // ============ 勋章墙（纯展示，不引入新数据） ============
          SectionCard({
            title: '我的低碳成就',
            icon: $r('app.media.ic_tab_medal'),
            showIcon: true
          }) {
            Row() {
              ForEach(BADGES, (bd: BadgeSpec) => {
                Column() {
                  Column() {
                    Image(this.badgeIcon(bd.id))
                      .width(20)
                      .height(20)
                      .fillColor(this.balance >= bd.threshold ? Ink.ON_BRAND : Ink.L4)
                      .objectFit(ImageFit.Contain)
                  }
                  .width(44)
                  .height(44)
                  .borderRadius(Radius.FULL)
                  .backgroundColor(this.balance >= bd.threshold ? Brand.PRIMARY : Bg.SUBTLE)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                  .shadow(this.balance >= bd.threshold ? shadowBrand() : shadowSubtle())

                  Text(bd.label)
                    .fontSize(FontSize.CAPTION)
                    .fontWeight(Weight.SUBTITLE)
                    .fontColor(this.balance >= bd.threshold ? Ink.L1 : Ink.L4)
                    .maxLines(1)
                    .margin({ top: Space.SM })

                  Text(this.balance >= bd.threshold ? '已达成' : `${bd.threshold} 分`)
                    .fontSize(FontSize.CAPTION)
                    .fontColor(this.balance >= bd.threshold ? Brand.PRIMARY : Ink.L4)
                    .margin({ top: 1 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Center)
              }, (bd: BadgeSpec) => bd.id)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)

            Text(`累计碳积分满 100 / 300 / 500 / 1000 分各解锁一枚勋章 · 当前 ${this.balance} 分`)
              .fontSize(FontSize.CAPTION)
              .fontColor(Ink.L3)
              .width('100%')
              .margin({ top: Space.MD })
          }

          // ============ 主要功能 3：本地虚拟奖励 ============
          SectionCard({
            title: '低碳徽章与证书',
            icon: $r('app.media.ic_leaf'),
            showIcon: true
          }) {
            ForEach(REWARDS, (r: Reward) => {
              Row() {
                Column() {
                  Image(this.rewardIcon(r))
                    .width(20)
                    .height(20)
                    .fillColor(this.balance >= r.cost ? Brand.PRIMARY : Ink.L4)
                    .objectFit(ImageFit.Contain)
                }
                .width(40)
                .height(40)
                .borderRadius(Radius.SM)
                .backgroundColor(this.balance >= r.cost ? this.rewardSoft(r) : Bg.SUBTLE)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .margin({ right: Space.MD })

                Column() {
                  Text(r.name)
                    .fontSize(FontSize.BODY_M)
                    .fontWeight(Weight.SUBTITLE)
                    .fontColor(this.balance >= r.cost ? Ink.L1 : Ink.L3)
                    .maxLines(1)
                  Text(r.desc)
                    .fontSize(FontSize.CAPTION)
                    .fontColor(this.balance >= r.cost ? Ink.L3 : Ink.L4)
                    .maxLines(1)
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Column() {
                  Text(`${r.cost} 分`)
                    .fontSize(FontSize.BODY_S)
                    .fontWeight(Weight.SUBTITLE)
                    .fontColor(this.balance >= r.cost ? Semantic.ALERT : Ink.L4)
                  Button('兑换')
                    .fontSize(FontSize.BODY_S)
                    .height(32)
                    .padding({ left: 14, right: 14 })
                    .borderRadius(Radius.FULL)
                    .backgroundColor(this.balance >= r.cost ? Brand.PRIMARY : Bg.SUBTLE)
                    .fontColor(this.balance >= r.cost ? Ink.ON_BRAND : Ink.L3)
                    .margin({ top: 6 })
                    .onClick(() => {
                      this.redeemLocal(r);
                    })
                }
                .alignItems(HorizontalAlign.End)
                .margin({ left: Space.SM })
              }
              .width('100%')
              .padding(Space.MD)
              .backgroundColor(Bg.CARD)
              .borderRadius(Radius.MD)
              .border({ width: 1, color: Edge.HAIR })
              .shadow(shadowSubtle())
              .margin({ bottom: Space.SM })
              .alignItems(VerticalAlign.Center)
            }, (r: Reward) => r.id)
          }

          // ============ 流水 ============
          SectionCard({
            title: '积分流水',
            icon: $r('app.media.ic_tab_book'),
            showIcon: true
          }) {
            if (this.ledger.length === 0) {
              Text('还没有积分记录，去「记一笔」记录低碳行为即可获得积分。')
                .fontSize(FontSize.BODY_M)
                .fontColor(Ink.L3)
                .lineHeight(LineHeight.BODY_M)
                .width('100%')
            } else {
              ForEach(this.ledger, (p: PointsEntry) => {
                Row() {
                  Column() {
                    Text(p.reason)
                      .fontSize(FontSize.BODY_M)
                      .fontColor(Ink.L1)
                      .maxLines(1)
                    Text(`${fmtTime(p.ts)} · 余额 ${p.balanceAfter}`)
                      .fontSize(FontSize.CAPTION)
                      .fontColor(Ink.L3)
                      .margin({ top: 3 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Text(p.delta > 0 ? `+${p.delta}` : `${p.delta}`)
                    .fontSize(FontSize.SUB_S)
                    .fontWeight(Weight.SUBTITLE)
                    .fontColor(p.delta > 0 ? Brand.PRIMARY : Semantic.WARNING)
                }
                .width('100%')
                .padding({ top: 9, bottom: 9 })
              }, (p: PointsEntry) => p.id)
            }
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
