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
  Bg, Brand, CatColor, Edge, FontSize, Ink, Radius, Semantic, Space, Weight,
  Motion, shadowCard, shadowRaised, shadowSubtle, heroGradient, softGradient
} from '../common/Theme';

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
 * 分享卡：这个组件会被 componentSnapshot 截图，所以要给一个稳定的 id。
 *
 * 注意：这里刻意用**基础类型**逐个接收数据，而不是传一个 SharePayload 对象。
 * 原因：实测发现 `@Prop` 接收自定义类对象时，父组件替换该对象后子组件没有刷新
 * （分享卡一直显示 0，而同一份数据在父组件里已是 2.35）。改成基础类型后行为确定。
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
      Row() {
        Text('碳迹')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Ink.ON_BRAND)
        Blank()
        Text(this.nickname)
          .fontSize(12)
          .fontColor(Ink.ON_BRAND_2)
      }
      .width('100%')

      Text('我的低碳成绩单')
        .fontSize(12)
        .fontColor(Ink.ON_BRAND_2)
        .width('100%')
        .margin({ top: 2 })

      Text(`${this.totalSaved}`)
        .fontSize(48)
        .fontWeight(FontWeight.Bold)
        .fontColor(Ink.ON_BRAND)
        .width('100%')
        .margin({ top: 18 })

      Text('kg CO₂e 累计减排')
        .fontSize(13)
        .fontColor(Ink.ON_BRAND_2)
        .width('100%')

      Row() {
        Column() {
          Text(`${this.trees()}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Ink.ON_BRAND)
          Text('相当于种树（棵·年）')
            .fontSize(10)
            .fontColor(Ink.ON_BRAND_2)
            .margin({ top: 4 })
        }
        .layoutWeight(1)

        Column() {
          Text(`${this.recordCount}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Ink.ON_BRAND)
          Text('条低碳记录')
            .fontSize(10)
            .fontColor(Ink.ON_BRAND_2)
            .margin({ top: 4 })
        }
        .layoutWeight(1)

        Column() {
          Text(`${this.activeDays}`)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Ink.ON_BRAND)
          Text('天坚持记录')
            .fontSize(10)
            .fontColor(Ink.ON_BRAND_2)
            .margin({ top: 4 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 22 })

      Divider()
        .color(Edge.ON_BRAND)
        .margin({ top: 16, bottom: 12 })

      Row() {
        Text(`主力贡献：${this.topCategory}`)
          .fontSize(11)
          .fontColor(Ink.ON_BRAND_2)
          .layoutWeight(1)
        Text(this.dateStr)
          .fontSize(11)
          .fontColor(Ink.ON_BRAND_2)
      }
      .width('100%')

      Text('数据全部保存在本机，不上传云端')
        .fontSize(9)
        .fontColor(Ink.ON_BRAND_3)
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(22)
    .backgroundColor(Brand.PRIMARY)
    .borderRadius(Radius.MD)
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
        Row() {
          Text('今日低碳任务')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Ink.L1)
            .layoutWeight(1)
          Text('创新点 4')
            .fontSize(10)
            .fontColor(Semantic.ALERT)
            .backgroundColor(Semantic.ALERT_SOFT)
            .borderRadius(8)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        }
        .width('100%')
        .margin({ bottom: 10 })

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
        Text('给你的低碳建议')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Ink.L1)
          .width('100%')
          .margin({ bottom: 10 })
        if (this.advice.length === 0) {
          Text('记录一些数据后，这里会根据你的情况给出建议。')
            .fontSize(12)
            .fontColor(Ink.L3)
            .width('100%')
        } else {
          ForEach(this.advice, (a: string) => {
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
        Text('减排成果分享')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Ink.L1)
          .width('100%')
        Text(`累计 ${this.share.totalSaved} kg CO₂e · ${this.share.recordCount} 条记录`)
          .fontSize(11)
          .fontColor(Ink.L3)
          .width('100%')
          .margin({ top: 2, bottom: 10 })
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
          Button(this.generating ? '生成中…' : '生成分享图')
            .layoutWeight(1)
            .height(38)
            .fontSize(13)
            .backgroundColor(Brand.PRIMARY)
            .enabled(!this.generating)
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
              buttonType: ButtonType.Capsule
            })
              .width(148)
              .height(38)
              .fontSize(13)
              .backgroundColor(Brand.SOFT)
              .fontColor(Brand.PRIMARY)
              .iconColor(Brand.PRIMARY)
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
