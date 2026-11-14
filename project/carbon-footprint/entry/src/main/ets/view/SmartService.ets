/**
 * 智能服务 —— 创新拓展 4
 *
 * 赛题原文：「智能服务：个性化低碳任务推送、生活建议、减排成果社交分享功能。」
 *
 * 三块内容：
 *   1. 今日低碳任务 —— 由 data/TaskEngine.ets 按用户历史推荐（短板优先）
 *   2. 个性化生活建议 —— 每条都对应一个具体的数据事实
 *   3. 减排成果分享图 —— 用 componentSnapshot 把 ShareCard 截成图片，
 *      可存到应用沙箱，也可通过 SaveButton 安全控件存入相册（无需申请权限）
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CarbonRepository } from '../data/CarbonRepository';
import { buildAdvice, buildDailyTasks, DailyTask } from '../data/TaskEngine';
import { BehaviorRecord, categoryLabel, round2, today } from '../model/Models';
import {
  Bg, Brand, CatColor, Edge, FontSize, Ink, Radius, Rule, Seal, Semantic, Serif, Space, Weight,
  Motion, shadowCard, shadowRaised, shadowSubtle, heroGradient, softGradient
} from '../common/Theme';
import { DottedRule, Seal as SealStamp } from './Common';

const DOMAIN: number = 0x0005;
const TAG: string = 'SmartService';

/**
 * 分享卡的数据负载。
 * 一棵树每年约吸收 18 kg CO₂（常见引用值，不同树种与树龄差异较大，
 * 应用内按此折算仅用于形象化表达，Word 设计方案里需说明这是估算）。
 */
const KG_PER_TREE_PER_YEAR: number = 18;

export class SharePayload {
  version: number = 0;
  totalSaved: number = 0;
  totalPoints: number = 0;
  recordCount: number = 0;
  activeDays: number = 0;
  topCategory: string = '—';
  nickname: string = '';
  dateStr: string = '';
}

/**
 * 一条账目：项目 ………… 数值。账本是靠这一行一行的对齐成立的。
 *
 * ⚠️ 这里必须是 @Component，不能是 `@Builder ledgerRow(label, value)`。
 * @Builder 按值传参时，父组件的状态变了它**不会**重绘 —— 实测现象是：
 * 累计减排（直接子节点，走 @Prop）刷新成了 14.62，而这三行的
 * 「0 条 / 0 天 / —」停在首帧不动。EntryPage 与 ProfilePage 的实现备注里
 * 已经记过同一个坑，这里是第三次踩，所以单独写成组件。
 */
@Component
struct LedgerRow {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(12)
        .fontColor(Ink.L2)
      DottedRule({ dotColor: Rule.DASH })
      Text(this.value)
        .fontFamily(Serif.FAMILY)
        .fontSize(13)
        .fontColor(Ink.L1)
        .fontFeature('"tnum" 1')
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 5, bottom: 5 })
  }
}

/**
 * 分享卡 —— 「减排凭证」，一张会被截屏传播的小票。
 *
 * ── 为什么是「小票」不是「海报」──────────────────────────────────────────
 * 这张图会离开界面被单独传播（发群里、贴 PPT、印出来）。海报化的分享卡
 * 一定滑向「大圆角色块 + 渐变 + 大图标」——那是所有模板的默认长相。
 * 而「小票」本来就是这个产品的一部分：一行行账目、等宽数字、引导点线、
 * 落款盖章。它不需要为「分享」而改变语言，反而因为被传播才更需要守住语言。
 *
 * ── 结构 ────────────────────────────────────────────────────────────────
 *   抬头（刊名 + 「凭证」朱字）→ 账簿双线 → 累计减排大字
 *   → 三条明细（项目 ………… 数值）→ 点线 → 落款（日期 / 昵称）+ 朱印
 *   → 底注（本机数据）
 *
 * ── 两个技术注意 ─────────────────────────────────────────────────────────
 *   1. 数据用**基础类型**逐个接收（不是传 SharePayload）：实测 @Prop 收自定义
 *      类对象时父组件替换对象后子组件不刷新，分享卡会一直显示 0。
 *   2. id 固定为 carbonShareCard —— componentSnapshot 靠它取节点。
 *      印章是 Canvas 画的，截图能不能带出来必须实机验证（见交接文档）。
 */
@Component
export struct ShareCard {
  @Prop totalSaved: number = 0;
  @Prop recordCount: number = 0;
  @Prop activeDays: number = 0;
  @Prop topCategory: string = '—';
  @Prop nickname: string = '';
  @Prop dateStr: string = '';

  private trees(): number {
    return Math.round((this.totalSaved / KG_PER_TREE_PER_YEAR) * 10) / 10;
  }

  build() {
    Column() {
      // ── 抬头 ────────────────────────────────────────────────────────
      Row() {
        Text('碳 迹 · 减 排 凭 证')
          .fontFamily(Serif.FAMILY)
          .fontSize(11)
          .letterSpacing(1.2)
          .fontColor(Ink.L1)
        Blank()
        Text('凭 证')
          .fontFamily(Serif.FAMILY)
          .fontSize(9)
          .letterSpacing(1.5)
          .fontColor(Seal.RED)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // ── 账簿双线：粗在上、细在下 ────────────────────────────────────
      Column()
        .width('100%')
        .height(1.4)
        .backgroundColor(Rule.STRONG)
        .margin({ top: 9 })
      Column()
        .width('100%')
        .height(0.7)
        .backgroundColor(Rule.HAIR)
        .margin({ top: 2.5 })

      // ── 主数字 ──────────────────────────────────────────────────────
      Text('累 计 减 排')
        .fontSize(9)
        .letterSpacing(2)
        .fontColor(Ink.L3)
        .width('100%')
        .margin({ top: 18 })

      Row() {
        Text(`${this.totalSaved}`)
          .fontFamily(Serif.FAMILY)
          .fontSize(46)
          .fontColor(Ink.L1)
          .fontFeature('"tnum" 1')
        Text('kg CO₂e')
          .fontSize(11)
          .fontColor(Ink.L3)
          .margin({ left: 6, bottom: 9 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      Text(`折合 ${this.trees()} 棵树 · 年`)
        .fontSize(11)
        .fontColor(Ink.L2)
        .width('100%')
        .margin({ top: 3 })

      // ── 明细 ────────────────────────────────────────────────────────
      Column()
        .width('100%')
        .height(0.7)
        .backgroundColor(Rule.HAIR)
        .margin({ top: 14, bottom: 4 })

      LedgerRow({ label: '低碳记录', value: `${this.recordCount} 条` })
      LedgerRow({ label: '坚持记录', value: `${this.activeDays} 天` })
      LedgerRow({ label: '主力贡献', value: this.topCategory })

      // ── 落款：日期 + 昵称 在左，朱印在右（压住上面的点线 = 骑缝）──────
      Column()
        .width('100%')
        .height(0.7)
        .backgroundColor(Rule.HAIR)
        .margin({ top: 4, bottom: 10 })

      Row() {
        Column() {
          Text(this.nickname.length > 0 ? this.nickname : '低碳生活家')
            .fontFamily(Serif.FAMILY)
            .fontSize(13)
            .fontColor(Ink.L1)
            .width('100%')
          Text(this.dateStr)
            .fontSize(10)
            .fontColor(Ink.L3)
            .fontFeature('"tnum" 1')
            .width('100%')
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 印章是从组件里长出来的，不是贴上去的：同一套 Seal，只是印面更大
        SealStamp({ text: '碳迹', sealSize: 19, angle: -8, rough: 1.25 })
          .translate({ y: -14 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // ── 底注 ────────────────────────────────────────────────────────
      Text('本 机 生 成 · 数 据 不 出 设 备')
        .fontSize(8)
        .letterSpacing(1.5)
        .fontColor(Ink.L4)
        .width('100%')
        .margin({ top: 2 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 16 })
    // 比纸再亮半档：这是「贴上去的一张纸」，不是又一张卡片
    .backgroundColor(Bg.CARD)
    .backgroundImage($r('app.media.paper_card'), ImageRepeat.XY)
    .border({ width: 0.8, color: Rule.HAIR })
    .borderRadius(Radius.XS)
    .id('carbonShareCard')
  }
}

// ---------------------------------------------------------------------------
// 智能服务区块
// ---------------------------------------------------------------------------

@Component
export struct SmartService {
  /** 数据版本号：由 Index 在页签切换时递增，用于触发刷新。
   *  必须这样做——TabContent 会预建组件，aboutToAppear 只在首次渲染时执行一次，
   *  否则会出现「先打开看板、再回录入页记一笔、看板数字不变」的陈旧数据问题。 */
  @Prop @Watch('onVersion') version: number = 0;

  @State tasks: DailyTask[] = [];
  @State advice: string[] = [];
  /** 建议默认只露第一条，其余折叠 —— 三条建议铺满半屏，把凭证挤到一屏之外 */
  @State adviceOpen: boolean = false;
  @State share: SharePayload = new SharePayload();

  @State dbg: string = '';
  @State generating: boolean = false;
  @State msg: string = '';
  @State msgOk: boolean = true;
  /** 预览用的图片（生成后才有） */
  @State preview: image.PixelMap | undefined = undefined;
  @State savedPath: string = '';

  /** 快照需要组件已经渲染，所以先显示卡片本身，再截图 */
  @State showCard: boolean = true;

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
    const records: BehaviorRecord[] = await repo.listBehaviors();
    const todayStr: string = today();
    this.tasks = buildDailyTasks(records, todayStr);
    this.advice = buildAdvice(records);

    // 组装分享卡数据（整段包 try/catch：这段曾在真机静默失败，
    // 把异常暴露到界面上，避免再次出现「数据是 0 但没人知道为什么」）
    try {
    const payload: SharePayload = new SharePayload();
    payload.version = this.share.version + 1;

    // 刻意只用数组与下标循环，不用 Set / Map.forEach ——
    // 这条路径曾经在真机上「静默失败」导致分享卡一直显示 0（前面的 tasks/advice 已赋值，
    // 后面的 share 没赋上），换成数组后行为确定。
    let total: number = 0;
    const dayList: string[] = [];
    const catKeys: string[] = [];
    const catVals: number[] = [];
    for (let i = 0; i < records.length; i++) {
      const r: BehaviorRecord = records[i];
      total += r.saved;
      if (dayList.indexOf(r.date) < 0) {
        dayList.push(r.date);
      }
      const ci: number = catKeys.indexOf(r.category);
      if (ci < 0) {
        catKeys.push(r.category);
        catVals.push(r.saved);
      } else {
        catVals[ci] = catVals[ci] + r.saved;
      }
    }
    payload.totalSaved = round2(total);
    payload.recordCount = records.length;
    payload.activeDays = dayList.length;
    payload.totalPoints = await repo.pointsBalance();

    let topCat: string = '';
    let topVal: number = -1;
    for (let i = 0; i < catKeys.length; i++) {
      if (catVals[i] > topVal) {
        topVal = catVals[i];
        topCat = catKeys[i];
      }
    }
    payload.topCategory = topCat.length === 0 ? '还没有记录' : categoryLabel(topCat);
    const p = await repo.getProfile();
    payload.nickname = p.nickname;
    payload.dateStr = todayStr;
    this.share = payload;
    hilog.info(DOMAIN, TAG, 'share payload: saved=%{public}s records=%{public}d days=%{public}d',
      `${payload.totalSaved}`, payload.recordCount, payload.activeDays);
    } catch (e) {
      const err = e as BusinessError;
      this.dbg = `分享数据组装失败：code=${err.code} msg=${err.message}`;
      hilog.error(DOMAIN, TAG, 'build share payload failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 把分享卡截成 PixelMap */
  private async capture(): Promise<image.PixelMap | undefined> {
    try {
      const pm: image.PixelMap = await this.getUIContext()
        .getComponentSnapshot()
        .get('carbonShareCard');
      return pm;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'snapshot failed: code=%{public}d msg=%{public}s', err.code, err.message);
      return undefined;
    }
  }

  /** 生成分享图：截图 → 存到应用沙箱 → 预览 */
  private async generate(): Promise<void> {
    this.generating = true;
    this.msg = '';
    try {
      const pm: image.PixelMap | undefined = await this.capture();
      if (pm === undefined) {
        this.msgOk = false;
        this.msg = '生成失败：无法截取分享卡';
        return;
      }
      this.preview = pm;

      const ctx: common.Context | undefined = this.getUIContext().getHostContext();
      if (ctx === undefined) {
        this.msgOk = false;
        this.msg = '生成失败：拿不到应用上下文';
        return;
      }

      const packer: image.ImagePacker = image.createImagePacker();
      const opt: image.PackingOption = { format: 'image/png', quality: 98 };
      const buf: ArrayBuffer = await packer.packing(pm, opt);
      packer.release();

      const path: string = `${ctx.filesDir}/carbon-share-${Date.now()}.png`;
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, buf);
      } finally {
        fs.closeSync(file);
      }
      this.savedPath = path;
      this.msgOk = true;
      this.msg = `分享图已生成（${Math.round(buf.byteLength / 1024)} KB）`;
    } catch (e) {
      const err = e as BusinessError;
      this.msgOk = false;
      this.msg = `生成失败：${err.message}`;
    } finally {
      this.generating = false;
    }
  }

  /** 通过 SaveButton 获得临时授权后写入相册 */
  private async saveToAlbum(): Promise<void> {
    const pm: image.PixelMap | undefined = this.preview;
    if (pm === undefined) {
      this.msgOk = false;
      this.msg = '请先生成分享图';
      return;
    }
    try {
      const ctx: common.Context | undefined = this.getUIContext().getHostContext();
      if (ctx === undefined) {
        this.msgOk = false;
        this.msg = '拿不到应用上下文';
        return;
      }
      const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(ctx);
      const uri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png');

      const packer: image.ImagePacker = image.createImagePacker();
      const opt: image.PackingOption = { format: 'image/png', quality: 98 };
      const buf: ArrayBuffer = await packer.packing(pm, opt);
      packer.release();

      const file = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, buf);
      } finally {
        fs.closeSync(file);
      }
      this.msgOk = true;
      this.msg = '已保存到相册';
    } catch (e) {
      const err = e as BusinessError;
      this.msgOk = false;
      this.msg = `保存到相册失败：${err.message}`;
    }
  }

  build() {
    Column() {
      // ---------- 今日任务 ----------
      Column() {
        // 表头与 SectionCard 同一套语言（朱砂短线 + 宋体标题 + 双线）：
        // 这三块以前是"另一套卡片"，和上面十张卡放在一页里，像两个 App 拼起来的。
        Row() {
          Column()
            .width(9)
            .height(2)
            .backgroundColor(Seal.RED)
            .margin({ right: 7 })
          Text('今 日 低 碳 任 务')
            .fontFamily(Serif.FAMILY)
            .fontSize(15)
            .fontColor(Ink.L1)
            .letterSpacing(0.8)
            .layoutWeight(1)
          Text('智 能 任 务')
            .fontSize(10)
            .fontColor(Seal.RED)
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .border({ width: 0.8, color: Seal.RED, radius: 1 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 8 })

        Column().width('100%').height(1).backgroundColor(Rule.STRONG)
        Column().width('100%').height(1).backgroundColor(Rule.HAIR).margin({ top: 2.5, bottom: 12 })

        if (this.tasks.length === 0) {
          Text('暂无任务')
            .fontSize(12)
            .fontColor(Ink.L3)
            .width('100%')
        } else {
          ForEach(this.tasks, (t: DailyTask) => {
            Row() {
              Text(t.done ? '✓' : '○')
                .fontSize(16)
                .fontColor(t.done ? Brand.PRIMARY : Ink.L4)
                .width(24)
              Column() {
                Text(t.title)
                  .fontSize(13)
                  .fontColor(t.done ? Ink.L3 : Ink.L1)
                  .decoration({ type: t.done ? TextDecorationType.LineThrough : TextDecorationType.None })
                Text(t.hint)
                  .fontSize(10)
                  .fontColor(Ink.L3)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(`+${t.points}`)
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(t.done ? Ink.L4 : Semantic.ALERT)
            }
            .width('100%')
            .padding({ top: 8, bottom: 8 })
          }, (t: DailyTask) => t.id)
        }
      }
      .width('100%')
      .padding(Space.LG)
      .backgroundColor(Bg.CARD)
      .borderRadius(Radius.MD)
      .margin({ bottom: Space.MD })

      // ---------- 生活建议 ----------
      Column() {
        Row() {
          Column()
            .width(9)
            .height(2)
            .backgroundColor(Seal.RED)
            .margin({ right: 7 })
          Text('给 你 的 低 碳 建 议')
            .fontFamily(Serif.FAMILY)
            .fontSize(15)
            .fontColor(Ink.L1)
            .letterSpacing(0.8)
            .layoutWeight(1)
          if (this.advice.length > 1) {
            Text(this.adviceOpen ? '收起' : `展开 ${this.advice.length - 1} 条`)
              .fontSize(10)
              .fontColor(Ink.L3)
              .padding({ left: 6, top: 2, bottom: 2 })
              .onClick(() => {
                this.adviceOpen = !this.adviceOpen;
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 8 })

        Column().width('100%').height(1).backgroundColor(Rule.STRONG)
        Column().width('100%').height(1).backgroundColor(Rule.HAIR).margin({ top: 2.5, bottom: 10 })
        if (this.advice.length === 0) {
          Text('记录一些数据后，这里会根据你的情况给出建议。')
            .fontSize(12)
            .fontColor(Ink.L3)
            .width('100%')
        } else {
          ForEach(this.adviceOpen ? this.advice : this.advice.slice(0, 1), (a: string) => {
            Row() {
              Text('·')
                .fontSize(14)
                .fontColor(Brand.PRIMARY)
                .width(14)
              Text(a)
                .fontSize(12)
                .fontColor(Ink.L2)
                .lineHeight(19)
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .padding({ top: 5, bottom: 5 })
          }, (a: string) => a)
        }
      }
      .width('100%')
      .padding(Space.LG)
      .backgroundColor(Bg.CARD)
      .borderRadius(Radius.MD)
      .margin({ bottom: Space.MD })

      // ---------- 分享 ----------
      Column() {
        Row() {
          Column()
            .width(9)
            .height(2)
            .backgroundColor(Seal.RED)
            .margin({ right: 7 })
          Text('减 排 凭 证')
            .fontFamily(Serif.FAMILY)
            .fontSize(15)
            .fontColor(Ink.L1)
            .letterSpacing(0.8)
            .layoutWeight(1)
          Text('可 分 享')
            .fontSize(10)
            .fontColor(Seal.RED)
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .border({ width: 0.8, color: Seal.RED, radius: 1 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 8 })

        Column().width('100%').height(1).backgroundColor(Rule.STRONG)
        Column().width('100%').height(1).backgroundColor(Rule.HAIR).margin({ top: 2.5, bottom: 12 })

        // 不再在票面上方复述「累计 X kg · N 条」—— 票面里已经有了。
        // 同一个数字在一屏里说两遍，是「模板感」最常见的来源之一。
        if (this.dbg.length > 0) {
          Text(this.dbg)
            .fontSize(11)
            .fontColor(Semantic.WARNING)
            .width('100%')
            .margin({ bottom: 10 })
        }

        if (this.showCard) {
          ShareCard({
            totalSaved: this.share.totalSaved,
            recordCount: this.share.recordCount,
            activeDays: this.share.activeDays,
            topCategory: this.share.topCategory,
            nickname: this.share.nickname,
            dateStr: this.share.dateStr
          })
        }

        Row() {
          Button(this.generating ? '生成中…' : '生成分享图', { type: ButtonType.Normal })
            .layoutWeight(1)
            .height(38)
            .fontSize(13)
            .backgroundColor(Ink.L1)
            .fontColor(Ink.ON_BRAND)
            .enabled(!this.generating)
            .borderRadius(Radius.XS)
            .onClick(() => {
              this.generate();
            })

          // 安全控件只支持受限属性集（width/height/fontSize/backgroundColor/fontColor/iconColor…，
          // 不支持 layoutWeight、margin），所以把它包在一个带 layoutWeight 的 Row 里来参与布局。
          //
          // 配色：不改的话它走系统默认 —— 底色 sys.color.icon_emphasize（系统蓝 #0A59F7 一族）、
          // 文字/图标 sys.color.font_on_primary / icon_on_primary（白），
          // 在一屏绿色里蓝得非常跳，像外来控件。这里降级成**次要按钮**：
          // 浅绿底 + 品牌绿字/图标，与左侧实心绿的主按钮（生成分享图）形成主次关系。
          // ⚠️ fontColor 与 iconColor 必须同时给：二者默认都是白色，
          //    只改 backgroundColor 会得到「白图标 + 浅绿底」= 图标看不见。
          Row() {
            SaveButton({
              icon: SaveIconStyle.FULL_FILLED,
              text: SaveDescription.SAVE_IMAGE,
              buttonType: ButtonType.Normal
            })
              .width(148)
              .height(38)
              .fontSize(13)
              .backgroundColor(Bg.SUBTLE)
              .fontColor(Ink.L1)
              .iconColor(Ink.L1)
              .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
                if (result === SaveButtonOnClickResult.SUCCESS) {
                  this.saveToAlbum();
                } else {
                  this.msgOk = false;
                  this.msg = '未获得保存授权';
                }
              })
          }
          .layoutWeight(1)
          .margin({ left: 10 })
          .justifyContent(FlexAlign.End)
        }
        .width('100%')
        .margin({ top: 12 })

        if (this.preview !== undefined) {
          Text('分享图预览')
            .fontSize(11)
            .fontColor(Ink.L3)
            .width('100%')
            .margin({ top: 12, bottom: 6 })
          Image(this.preview)
            .width('100%')
            .borderRadius(Radius.SM)
        }

        if (this.savedPath.length > 0) {
          Text(`已存到：${this.savedPath}`)
            .fontSize(10)
            .fontColor(Ink.L3)
            .width('100%')
            .margin({ top: 8 })
        }

        if (this.msg.length > 0) {
          Text(this.msg)
            .fontSize(12)
            .fontColor(this.msgOk ? Brand.PRIMARY : Semantic.WARNING)
            .width('100%')
            .margin({ top: 8 })
        }
      }
      .width('100%')
      .padding(Space.LG)
      .backgroundColor(Bg.CARD)
      .borderRadius(Radius.MD)
    }
    .width('100%')
  }
}
