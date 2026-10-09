/**
 * 碳迹 —— 应用主入口
 *
 * 职责：初始化数据层（DistributedStore + CarbonRepository），
 *      然后把五个基础功能装进底部页签。
 *
 * 页签与赛题二「主要功能」的对应关系：
 *   记一笔 → 主要功能 1  低碳行为核算
 *   看板   → 主要功能 2  数据可视化看板
 *   积分   → 主要功能 3  碳积分激励体系
 *   科普   → 主要功能 4  双碳科普专栏
 *   我的   → 主要功能 5  本地数据管理（＋创新点 1 同步面板）
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CarbonRepository } from '../data/CarbonRepository';
import { Bg, Brand, FontSize, Ink, Motion, Radius, Semantic, Space, Weight } from '../common/Theme';
import { DashboardPage } from '../view/DashboardPage';
import { EntryPage } from '../view/EntryPage';
import { KnowledgePage } from '../view/KnowledgePage';
import { PointsPage } from '../view/PointsPage';
import { ProfilePage } from '../view/ProfilePage';
import { YearReportPage } from '../view/YearReportPage';

const DOMAIN: number = 0x0001;
const TAG: string = 'Index';

@Entry
@Component
struct Index {
  @State ready: boolean = false;
  @State errMsg: string = '';
  /**
   * 数据版本号：每次切换页签就递增，各页面用 @Watch 监听它来刷新。
   * 为什么需要：ArkUI 的 TabContent 会预建组件，aboutToAppear 只在首次渲染时
   * 执行一次。没有这个机制就会出现「先看看板、再回录入页记一笔、看板数字不变」。
   */
  @State dataVersion: number = 0;

  /** 当前页签，用于自定义 tabBar 的选中态着色 */
  @State currentIndex: number = 0;

  /**
   * 「我的年度碳迹」报告是否展开。
   *
   * 为什么放在 Index 而不是某个页面里：报告是**全屏**的（要盖住底部页签栏），
   * 挂在页面内部做不到这一点。放在根节点用 Stack 叠一层是最简单的做法，
   * 也避免了为它引入 Navigation / bindContentCover 那套路由。
   */
  @State showYearReport: boolean = false;

  /**
   * 自定义页签项：图标 + 文字，选中时一起落进一个 Brand.SOFT 胶囊指示器。
   * 之前是纯文字 tabBar，在五个页签的应用里信息量明显不足 ——
   * 图标能让用户不读文字就完成定位。
   *
   * 排布取舍（重要）：图标在上、文字在下（Column），而不是左右并排（Row）。
   * 五个页签在 360vp 屏上每格只有 72vp，而「记一笔」三个字（10vp × 3 = 30vp）
   * 加图标 23vp 再加左右各 14vp 内边距要 86vp —— 横排必然溢出被裁；
   * 竖排最宽只要 58vp，稳。
   *
   * ⚠️ 透明底必须写 Color.Transparent，不要写成 8 位全零的十六进制字符串
   *    （ArkUI 里那种写法不是合法色值，底会变黑）。
   */
  @Builder
  tabItem(index: number, icon: Resource, label: string) {
    Column() {
      Column() {
        Image(icon)
          .width(23)
          .height(23)
          .fillColor(this.currentIndex === index ? Brand.PRIMARY : Ink.L3)
          .objectFit(ImageFit.Contain)
          // 选中时图标轻微放大 1.08，配合胶囊一起「跳」出来
          .scale({
            x: this.currentIndex === index ? 1.08 : 1,
            y: this.currentIndex === index ? 1.08 : 1
          })
        Text(label)
          .fontSize(FontSize.CAPTION)
          .fontWeight(this.currentIndex === index ? Weight.SUBTITLE : Weight.BODY)
          .fontColor(this.currentIndex === index ? Brand.PRIMARY : Ink.L3)
          .margin({ top: 3 })
      }
      .padding({ left: 14, right: 14, top: 5, bottom: 5 })
      .borderRadius(Radius.MD)
      .backgroundColor(this.currentIndex === index ? Brand.SOFT : Color.Transparent)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
  private controller: TabsController = new TabsController();

  aboutToAppear(): void {
    this.boot();
  }

  private async boot(): Promise<void> {
    try {
      const ctx: common.Context | undefined = this.getUIContext().getHostContext();
      if (ctx === undefined) {
        this.errMsg = '无法获取应用上下文，请重启应用。';
        return;
      }
      await CarbonRepository.init(ctx as common.Context);
      this.ready = true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'init failed: %{public}s', JSON.stringify(err));
      this.errMsg = `数据层初始化失败：${err.message}`;
    }
  }

  build() {
    Column() {
      if (this.ready) {
        Stack() {
        Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
          TabContent() {
            EntryPage({ version: this.dataVersion })
          }.tabBar(this.tabItem(0, $r('app.media.ic_tab_add'), '记一笔'))

          TabContent() {
            DashboardPage({
              version: this.dataVersion,
              onOpenReport: () => {
                animateTo(Motion.SMOOTH, () => {
                  this.showYearReport = true;
                });
              }
            })
          }.tabBar(this.tabItem(1, $r('app.media.ic_tab_chart'), '看板'))

          TabContent() {
            PointsPage({ version: this.dataVersion })
          }.tabBar(this.tabItem(2, $r('app.media.ic_tab_medal'), '积分'))

          TabContent() {
            KnowledgePage()
          }.tabBar(this.tabItem(3, $r('app.media.ic_tab_book'), '科普'))

          TabContent() {
            ProfilePage({ version: this.dataVersion })
          }.tabBar(this.tabItem(4, $r('app.media.ic_tab_person'), '我的'))
        }
        .barMode(BarMode.Fixed)
        .barHeight(56)
        .barBackgroundColor(Bg.CARD)
        .divider({ strokeWidth: 0.5, color: Bg.LINE })
        .scrollable(false)
        .width('100%')
        .height('100%')
        .onChange((index: number) => {
          // 指示器移动 / 图标缩放包进弹性动画里，切页签才是「滑过去」而不是「跳过去」。
          // dataVersion 放在 animateTo 之外：数据刷新不该被算进这一帧动画。
          animateTo(Motion.SMOOTH, () => {
            this.currentIndex = index;
          });
          this.dataVersion = this.dataVersion + 1;
        })

        // 年度报告：整屏覆盖。放在 Stack 的最后一个子节点，因此自然盖在 Tabs 之上。
        if (this.showYearReport) {
          YearReportPage({
            version: this.dataVersion,
            onClose: () => {
              animateTo(Motion.SMOOTH, () => {
                this.showYearReport = false;
              });
            }
          })
        }
        }
        .width('100%')
        .height('100%')
      } else if (this.errMsg.length > 0) {
        Column() {
          Text('启动失败')
            .fontSize(FontSize.TITLE_S)
            .fontWeight(Weight.TITLE)
            .fontColor(Semantic.WARNING)
          Text(this.errMsg)
            .fontSize(FontSize.BODY_M)
            .fontColor(Ink.L2)
            .margin({ top: Space.MD })
            .textAlign(TextAlign.Center)
            .padding({ left: Space.HUGE, right: Space.HUGE })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .height('100%')
      } else {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(Brand.PRIMARY)
          Text('正在初始化数据层…')
            .fontSize(FontSize.BODY_M)
            .fontColor(Ink.L2)
            .margin({ top: Space.MD })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Bg.PAGE)
  }
}
