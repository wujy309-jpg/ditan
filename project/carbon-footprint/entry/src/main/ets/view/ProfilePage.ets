/**
 * 我的 —— 主要功能 5：本地数据管理 ＋ 创新点 1：超级终端同步面板
 *
 * 同步面板直接消费 DistributedStore.snapshot()，
 * 展示「本机标识 / 可信设备 / 上次同步 / 冲突记录数 / 远端写入数」，
 * 对应赛题原文要求的「同步状态可视化面板」。
 *
 * ── 本次美化改动（只动视觉，不动业务逻辑）──────────────────────────────
 * v1 的三处硬伤：
 *   1. 顶部三宫格（累计 / 条数 / 积分）与「看板」页完全雷同 —— 两个页面第一眼分不出来；
 *   2. 「我的档案」是两张没有标签的浅灰输入框，像一张没写完的表单草稿；
 *   3. 「超级终端同步」是 6 行「标签——值」的纯文字，看起来像调试面板；
 *   4. 四张卡片各自手搓（圆角 / 内边距 / 阴影每块都不一样），裸写颜色 11 处。
 * 本次：
 *   1. 顶部换成**档案英雄区**（HeroCard · brand）：56×56 头像位 + 昵称 + 称号，
 *      下方三枚小胶囊，第三枚改用「碳积分」—— 与看板页英雄区的「本周」形成差异；
 *   2. 四张卡片全部改用 Common.ets 的 SectionCard（统一圆角 / 内边距 / 阴影 / 图标标题 / 角标）；
 *   3. 同步面板的 6 行改用 InfoRow（图标 + 标签 + 值 + 分隔线），
 *      并把「同步结果」这一行按 SyncOutcome 着色；
 *   4. 按钮统一胶囊圆角（Radius.FULL），主操作走 buttonGradient()，
 *      危险操作用 Semantic.WARNING / WARNING_SOFT 这一对；
 *   5. 裸写颜色全部收编到 Theme 令牌。
 *
 * 实现备注：统计项与同步项都通过 ForEach 渲染，而不是 @Builder 传值参数。
 * 原因：@Builder 按值传参时，状态变量变化不会触发其内部 UI 刷新，
 *      会出现「保存后数字不更新」的隐性 bug。
 */
import { BusinessError } from '@kit.BasicServicesKit';
import { CarbonRepository } from '../data/CarbonRepository';
import { PeerDevice, SyncOutcome, SyncSnapshot } from '../common/DistributedStore';
import { Profile } from '../model/Models';
import { AiCheckResult, runAiSelfCheck } from '../ai/AiSelfCheck';
import { resourceManager } from '@kit.LocalizationKit';
import { HeroCard, InfoRow, SectionCard } from './Common';
import {
  Bg, Brand, Edge, FontSize, Ink, LineHeight, Radius, Semantic, Space, Weight,
  buttonGradient, shadowCard
} from '../common/Theme';

/** 键值对，供 ForEach 渲染 */
interface KV {
  label: string;
  value: string;
}

/** 统计格子 */
interface Stat {
  value: string;
  label: string;
}

function outcomeText(o: string): string {
  if (o === SyncOutcome.SUCCESS) {
    return '同步成功';
  }
  if (o === SyncOutcome.PARTIAL) {
    return '部分成功';
  }
  if (o === SyncOutcome.FAILED) {
    return '同步失败';
  }
  if (o === SyncOutcome.NO_PEER) {
    return '无可信设备';
  }
  if (o === SyncOutcome.TIMEOUT) {
    return '等待超时';
  }
  return '从未同步';
}

function fmtTs(ts: number): string {
  if (ts <= 0) {
    return '从未同步';
  }
  const d: Date = new Date(ts);
  const hh: string = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`;
  const mi: string = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`;
  const ss: string = d.getSeconds() < 10 ? `0${d.getSeconds()}` : `${d.getSeconds()}`;
  return `${d.getMonth() + 1}-${d.getDate()} ${hh}:${mi}:${ss}`;
}

@Component
export struct ProfilePage {
  /** 数据版本号，页签切换时由 Index 递增，用于刷新（原因见 SmartService 注释） */
  @Prop @Watch('onVersion') version: number = 0;

  @State nickname: string = '';
  @State familyId: string = '';
  /** 三宫格原始聚合值；顶部已改为英雄区胶囊（读 totalSaved / recordCount / points） */
  @State stats: Stat[] = [];
  @State syncRows: KV[] = [];
  @State syncing: boolean = false;
  /** 上次同步结果（SyncOutcome 的字符串值），给同步面板的「同步结果」行着色用 */
  @State syncOutcome: string = '';

  // 英雄区三枚胶囊的数据源（与 stats 同源，避免在 build 里按下标取数组）
  @State totalSaved: number = 0;
  @State recordCount: number = 0;
  @State points: number = 0;

  // 端侧 AI 自检
  @State aiBusy: boolean = false;
  @State aiMsg: string = '';
  @State aiOk: boolean = false;
  @State aiShape: string = '';
  @State aiTopK: string = '';
  @State aiCalib: string = '';

  /** 当前聚焦的输入框，用于画聚焦描边 */
  @State focusField: string = '';
  @State msg: string = '';
  @State msgOk: boolean = true;

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
    const p: Profile = await repo.getProfile();
    this.nickname = p.nickname;
    this.familyId = p.familyId;

    const total: number = await repo.totalSaved();
    const count: number = (await repo.listBehaviors()).length;
    const balance: number = await repo.pointsBalance();
    this.stats = [
      { value: `${total}`, label: '累计 kg CO₂e' },
      { value: `${count}`, label: '条记录' },
      { value: `${balance}`, label: '碳积分' }
    ];
    this.totalSaved = total;
    this.recordCount = count;
    this.points = balance;

    this.refreshSync();
  }

  private refreshSync(): void {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    let localId: string = repo.getLocalDeviceId();
    if (localId.length === 0) {
      localId = '未获取到（可能缺少设备管理服务）';
    }

    const peers: PeerDevice[] = repo.refreshPeers();
    let peerDesc: string = '未发现其他可信设备';
    if (peers.length > 0) {
      const names: string[] = [];
      for (let i = 0; i < peers.length; i++) {
        names.push(peers[i].deviceName);
      }
      peerDesc = `${peers.length} 台 · ${names.join('、')}`;
    }

    const snap: SyncSnapshot = repo.snapshot();
    this.syncOutcome = snap.lastOutcome;
    this.syncRows = [
      { label: '本机标识', value: localId },
      { label: '可信设备', value: peerDesc },
      { label: '上次同步', value: fmtTs(snap.lastSyncTime) },
      { label: '同步结果', value: outcomeText(snap.lastOutcome) },
      { label: '冲突记录数', value: `${snap.conflictCount}` },
      { label: '远端写入数', value: `${snap.remoteWriteCount}` }
    ];
  }

  /**
   * 纯展示称号：Profile 接口里没有等级字段，按累计减排量分档。
   * 阈值取 0 / 5 / 20 kg —— 与「记一笔」每日 3 kg 目标同量级：
   * 记满两天即脱离新芽，一周多一点到达人，坚持一周以上给到最高档。
   */
  private level(): string {
    if (this.totalSaved >= 20) {
      return '碳中和先锋';
    }
    if (this.totalSaved >= 5) {
      return '低碳达人';
    }
    if (this.totalSaved > 0) {
      return '低碳行者';
    }
    return '低碳新芽';
  }

  /** 同步行 → 图标（同步面板 6 行各有语义，用图标把语义前置） */
  private syncIcon(label: string): Resource {
    if (label === '可信设备') {
      return $r('app.media.ic_sync');
    }
    if (label === '上次同步') {
      return $r('app.media.ic_backup');
    }
    if (label === '同步结果') {
      return $r('app.media.ic_check');
    }
    if (label === '冲突记录数') {
      return $r('app.media.ic_target');
    }
    if (label === '远端写入数') {
      return $r('app.media.ic_export');
    }
    return $r('app.media.ic_tab_person');
  }

  /** 同步行 → 值颜色：只有「同步结果」需要按 SyncOutcome 变色 */
  private syncValueColor(label: string): string {
    if (label !== '同步结果') {
      return Ink.L1;
    }
    if (this.syncOutcome === SyncOutcome.SUCCESS) {
      return Brand.PRIMARY;
    }
    if (this.syncOutcome === SyncOutcome.PARTIAL || this.syncOutcome === SyncOutcome.FAILED) {
      return Semantic.ALERT;
    }
    return Ink.L3;
  }

  /** 跑一次端侧推理自检：验证模型能否加载、张量形状、Top-5 输出 */
  private async runAiCheck(): Promise<void> {
    if (this.aiBusy) {
      return;
    }
    this.aiBusy = true;
    this.aiMsg = '正在加载模型并推理…';
    this.aiShape = '';
    this.aiTopK = '';
    this.aiCalib = '';
    try {
      const rawCtx = this.getUIContext().getHostContext();
      if (rawCtx === undefined) {
        this.aiOk = false;
        this.aiMsg = '拿不到应用上下文';
        return;
      }
      const mgr: resourceManager.ResourceManager =
        rawCtx.getApplicationContext().resourceManager;
      const r: AiCheckResult = await runAiSelfCheck(mgr);
      this.aiOk = r.ok;
      this.aiCalib = r.calibration;
      if (r.ok) {
        this.aiShape = r.shapeInfo;
        this.aiTopK = r.topKText;
        this.aiMsg = '端侧推理链路可用';
      } else {
        this.aiMsg = r.error;
        this.aiShape = r.shapeInfo;
      }
    } catch (e) {
      const err = e as BusinessError;
      this.aiOk = false;
      this.aiMsg = `自检异常：${err.message}`;
    } finally {
      this.aiBusy = false;
    }
  }

  private async doSync(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    this.syncing = true;
    this.msg = '';
    try {
      const outcome: SyncOutcome = await repo.syncNow();
      this.msgOk = outcome === SyncOutcome.SUCCESS;
      this.msg = `同步结束：${outcomeText(outcome)}`;
    } catch (e) {
      const err = e as BusinessError;
      this.msgOk = false;
      this.msg = `同步异常：${err.message}`;
    } finally {
      this.syncing = false;
      this.refreshSync();
    }
  }

  private async saveProfile(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    const p: Profile = await repo.getProfile();
    p.nickname = this.nickname;
    p.familyId = this.familyId;
    await repo.saveProfile(p);
    this.msgOk = true;
    this.msg = '档案已保存，并会同步到其他设备';
  }

  private async backup(kind: string): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    try {
      const path: string = kind === 'json' ? await repo.backupJson() : await repo.backupCsv();
      this.msgOk = true;
      this.msg = `已导出到：${path}`;
    } catch (e) {
      const err = e as BusinessError;
      this.msgOk = false;
      this.msg = `导出失败：${err.message}`;
    }
  }

  private async wipe(): Promise<void> {
    const repo: CarbonRepository | undefined = CarbonRepository.get();
    if (repo === undefined) {
      return;
    }
    await repo.clearAll();
    this.msgOk = true;
    this.msg = '已清空全部本地数据';
    await this.refresh();
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // ============ 档案英雄区 ============
          // 与看板页的「深色数据英雄区」同语言、不同气质：这里用标准亮绿，
          // 强调「这是我」而不是「这是数据」。
          HeroCard({ variant: 'brand' }) {
            Row() {
              // 头像位：56×56 圆角方块（层级越高圆角越大 → 用 Radius.LG）
              Column() {
                Image($r('app.media.ic_tab_person'))
                  .width(28)
                  .height(28)
                  .fillColor(Ink.ON_BRAND)
                  .objectFit(ImageFit.Contain)
              }
              .width(56)
              .height(56)
              .borderRadius(Radius.LG)
              // 半透明装饰白（与看板页英雄区胶囊同一个值），只作「玻璃」质感，不是品牌色
              .backgroundColor('#26FFFFFF')
              .border({ width: 1, color: Edge.SHEEN })
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)

              Column() {
                Text(this.nickname.length > 0 ? this.nickname : '未设置昵称')
                  .fontSize(FontSize.TITLE_S)
                  .fontWeight(Weight.TITLE)
                  .fontColor(Ink.ON_BRAND)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                // 称号胶囊：纯展示，由 level() 按累计减排量分档
                Text(this.level())
                  .fontSize(FontSize.BODY_S)
                  .fontWeight(Weight.SUBTITLE)
                  .fontColor(Ink.ON_BRAND)
                  .backgroundColor('#26FFFFFF')
                  .borderRadius(Radius.FULL)
                  .padding({ left: 9, right: 9, top: 3, bottom: 3 })
                  .margin({ top: 7 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: Space.MD })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 三枚小胶囊：前两枚与看板页同口径，第三枚换成「碳积分」——两页第一眼就能分开
            Flex({ wrap: FlexWrap.Wrap }) {
              Text(`累计 ${this.totalSaved} kg`)
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.ON_BRAND)
                .backgroundColor('#26FFFFFF')
                .borderRadius(Radius.FULL)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                .margin({ right: Space.SM, bottom: Space.SM })
              Text(`${this.recordCount} 条记录`)
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.ON_BRAND)
                .backgroundColor('#26FFFFFF')
                .borderRadius(Radius.FULL)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                .margin({ right: Space.SM, bottom: Space.SM })
              Text(`碳积分 ${this.points} 分`)
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.ON_BRAND)
                .backgroundColor('#26FFFFFF')
                .borderRadius(Radius.FULL)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                .margin({ right: Space.SM, bottom: Space.SM })
            }
            .width('100%')
            .margin({ top: Space.XL })
          }

          // ============ 我的档案 ============
          SectionCard({ title: '我的档案', icon: $r('app.media.ic_tab_person'), showIcon: true }) {
            // 标签：v1 没有标签，两张浅灰输入框看起来像「没写完的表单」
            Text('昵称')
              .fontSize(FontSize.BODY_S)
              .fontColor(Ink.L3)
              .width('100%')
              .margin({ bottom: 6 })
            // 输入框：凹陷底（Bg.SUNKEN）+ 聚焦描边，明确「这里可以输入」
            TextInput({ placeholder: '昵称', text: this.nickname })
              .width('100%')
              .height(44)
              .fontSize(FontSize.BODY_L)
              .fontColor(Ink.L1)
              .placeholderColor(Ink.L4)
              .backgroundColor(Bg.SUNKEN)
              .borderRadius(Radius.SM)
              .borderWidth(this.focusField === 'nick' ? 1.5 : 0)
              .borderColor(Brand.PRIMARY)
              .onFocus(() => {
                this.focusField = 'nick';
              })
              .onBlur(() => {
                this.focusField = '';
              })
              .onChange((v: string) => {
                this.nickname = v;
              })

            Text('家庭 ID')
              .fontSize(FontSize.BODY_S)
              .fontColor(Ink.L3)
              .width('100%')
              .margin({ top: Space.MD, bottom: 6 })
            TextInput({ placeholder: '家庭 ID（用于家庭碳积分合并）', text: this.familyId })
              .width('100%')
              .height(44)
              .fontSize(FontSize.BODY_L)
              .fontColor(Ink.L1)
              .placeholderColor(Ink.L4)
              .backgroundColor(Bg.SUNKEN)
              .borderRadius(Radius.SM)
              .borderWidth(this.focusField === 'family' ? 1.5 : 0)
              .borderColor(Brand.PRIMARY)
              .onFocus(() => {
                this.focusField = 'family';
              })
              .onBlur(() => {
                this.focusField = '';
              })
              .onChange((v: string) => {
                this.familyId = v;
              })

            Button('保存档案')
              .width('100%')
              .height(44)
              .fontSize(FontSize.BODY_M)
              .fontColor(Ink.ON_BRAND)
              // 官方约束：Button 设渐变前必须把 backgroundColor 置为透明，否则实色底会盖住渐变
              .backgroundColor(Color.Transparent)
              .linearGradient(buttonGradient())
              .borderRadius(Radius.FULL)
              .margin({ top: Space.LG })
              .onClick(() => {
                this.saveProfile();
              })
          }

          // ============ 创新点 1：同步状态面板 ============
          SectionCard({
            title: '超级终端同步',
            icon: $r('app.media.ic_sync'),
            showIcon: true,
            badge: '创新点 1'
          }) {
            ForEach(this.syncRows, (r: KV) => {
              InfoRow({
                label: r.label,
                value: r.value,
                icon: this.syncIcon(r.label),
                showIcon: true,
                valueColor: this.syncValueColor(r.label),
                // 最后一行不留分隔线，避免分隔线紧贴下方按钮
                showDivider: r.label !== '远端写入数'
              })
            }, (r: KV) => r.label)

            Row() {
              Button('刷新设备')
                .layoutWeight(1)
                .height(40)
                .fontSize(FontSize.BODY_M)
                .backgroundColor(Brand.SOFT)
                .fontColor(Brand.PRIMARY)
                .borderRadius(Radius.FULL)
                .onClick(() => {
                  this.refreshSync();
                })
              Button(this.syncing ? '同步中…' : '立即同步')
                .layoutWeight(1)
                .height(40)
                .fontSize(FontSize.BODY_M)
                .fontColor(Ink.ON_BRAND)
                // 同「保存档案」：渐变按钮需要透明底
                .backgroundColor(Color.Transparent)
                .linearGradient(buttonGradient())
                .borderRadius(Radius.FULL)
                .margin({ left: Space.SM })
                .enabled(!this.syncing)
                .onClick(() => {
                  this.doSync();
                })
            }
            .width('100%')
            .margin({ top: Space.MD })

            Text('跨设备同步需两台设备登录同一华为账号、完成设备认证并处于同一局域网。')
              .fontSize(FontSize.BODY_S)
              .fontColor(Ink.L3)
              .lineHeight(LineHeight.BODY_S)
              .width('100%')
              .margin({ top: Space.MD })
          }

          // ============ 创新点 2：端侧 AI 自检 ============
          SectionCard({
            title: '端侧 AI 自检',
            icon: $r('app.media.ic_ai'),
            showIcon: true,
            badge: '创新点 2'
          }) {
            Text('用内置测试图跑一次端侧推理，确认模型可加载、张量形状正确、能输出候选索引。'
              + '这个过程全程离线，也是做「索引 → 类目」标定表的第一步。')
              .fontSize(FontSize.BODY_S)
              .fontColor(Ink.L3)
              .lineHeight(LineHeight.BODY_S)
              .width('100%')

            Button(this.aiBusy ? '推理中…' : '运行 AI 自检')
              .width('100%')
              .height(40)
              .fontSize(FontSize.BODY_M)
              .backgroundColor(Brand.SOFT)
              .fontColor(Brand.PRIMARY)
              .borderRadius(Radius.FULL)
              .margin({ top: Space.MD })
              .enabled(!this.aiBusy)
              .onClick(() => {
                this.runAiCheck();
              })

            if (this.aiMsg.length > 0) {
              Text(this.aiMsg)
                .fontSize(FontSize.BODY_S)
                .fontColor(this.aiOk ? Brand.PRIMARY : Semantic.WARNING)
                .width('100%')
                .margin({ top: Space.MD })
            }
            if (this.aiShape.length > 0) {
              Text(this.aiShape)
                .fontSize(FontSize.CAPTION)
                .fontColor(Ink.L2)
                .width('100%')
                .padding(Space.SM)
                .backgroundColor(Bg.SUNKEN)
                .borderRadius(Radius.SM)
                .margin({ top: Space.SM })
            }
            if (this.aiTopK.length > 0) {
              Text(`Top-5 候选：${this.aiTopK}`)
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.L1)
                .width('100%')
                .padding(Space.SM)
                .backgroundColor(Bg.SUNKEN)
                .borderRadius(Radius.SM)
                .margin({ top: 6 })
            }
            if (this.aiCalib.length > 0) {
              Text(this.aiCalib)
                .fontSize(FontSize.CAPTION)
                .fontColor(Ink.L3)
                .width('100%')
                .margin({ top: 6 })
            }
          }

          // ============ 主要功能 5：本地数据管理 ============
          SectionCard({ title: '本地数据管理', icon: $r('app.media.ic_backup'), showIcon: true }) {
            Row() {
              Button('备份数据')
                .layoutWeight(1)
                .height(40)
                .fontSize(FontSize.BODY_M)
                .backgroundColor(Brand.SOFT)
                .fontColor(Brand.PRIMARY)
                .borderRadius(Radius.FULL)
                .onClick(() => {
                  this.backup('json');
                })
              Button('导出报表')
                .layoutWeight(1)
                .height(40)
                .fontSize(FontSize.BODY_M)
                .backgroundColor(Brand.SOFT)
                .fontColor(Brand.PRIMARY)
                .borderRadius(Radius.FULL)
                .margin({ left: Space.SM })
                .onClick(() => {
                  this.backup('csv');
                })
            }
            .width('100%')

            // 危险操作：语义色成对使用（WARNING 文字 + WARNING_SOFT 底）
            Button('清空全部数据')
              .width('100%')
              .height(40)
              .fontSize(FontSize.BODY_M)
              .backgroundColor(Semantic.WARNING_SOFT)
              .fontColor(Semantic.WARNING)
              .borderRadius(Radius.FULL)
              .margin({ top: Space.MD })
              .onClick(() => {
                this.wipe();
              })
          }

          // 操作反馈条
          if (this.msg.length > 0) {
            Text(this.msg)
              .fontSize(FontSize.BODY_S)
              .fontColor(this.msgOk ? Brand.PRIMARY : Semantic.WARNING)
              .width('100%')
              .padding(Space.MD)
              .backgroundColor(Bg.CARD)
              .borderRadius(Radius.MD)
              .shadow(shadowCard())
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
