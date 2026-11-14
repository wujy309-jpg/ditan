/**
 * 科普 —— 主要功能 4：双碳科普专栏
 *
 * 内容来自 data/KnowledgeBase.ets（独立数据文件，内容负责人可直接编辑）。
 * 支持按标签筛选（政策 / 概念 / 技巧 / 数据）。
 *
 * ── 本次美化改动（只动视觉，数据来源 / applyFilter / 三个 @State 的语义全未改）──
 * v1 的三个病因：
 *   1. 顶部一整张白卡只放两行居中文字，白白吃掉约 1/5 屏，且五个页面顶部长得一样；
 *   2. 文章列表是「白卡 + 纯文字」，一行图标都没有，扫读时眼睛找不到落点；
 *   3. 标签颜色裸写（#1F9A4E / #33404D / #D8DEE6），四个分类之间没有颜色语义区分。
 * 对应改法：
 *   · 顶部换 HeroCard(fresh)：标题 + 副标题 + 「分类数 / 篇数」小胶囊 + 大号半透明书本装饰；
 *   · 标签筛选改用 Chip（选中主色实底 / 未选中浅灰底），并用 SectionCard 收口；
 *   · 每篇文章左侧补 40×40「分类色圆角图标块」，标签按语义着色（政策蓝 / 概念绿 /
 *     数据橙 / 技巧紫），四类之间靠颜色即可区分；
 *   · 「展开 / 收起」补 ic_arrow 箭头并做 90° 旋转动效，正文加发丝分隔线 + 行高；
 *   · 空状态改用 EmptyHint，页面根节点补 Bg.PAGE 底色。
 */
import { allTags, Article, ARTICLES } from '../data/KnowledgeBase';
import {
  Bg, Brand, CatColor, Edge, FontSize, Ink, LineHeight, Motion, Radius, Rule,
  Semantic, Serif, Space, Weight
} from '../common/Theme';
import { Chip, EmptyHint, HeroCard, SectionCard } from './Common';

@Component
export struct KnowledgePage {
  /** 已展开的文章 id；空串表示全部收起 */
  @State expanded: string = '';
  /** 当前筛选标签；空串表示全部 */
  @State tag: string = '';
  @State list: Article[] = ARTICLES;

  private applyFilter(t: string): void {
    this.tag = t;
    this.expanded = '';
    if (t.length === 0) {
      this.list = ARTICLES;
      return;
    }
    const out: Article[] = [];
    for (let i = 0; i < ARTICLES.length; i++) {
      if (ARTICLES[i].tag === t) {
        out.push(ARTICLES[i]);
      }
    }
    this.list = out;
  }

  /**
   * 标签 → 语义色。
   * 政策 / 概念 / 数据 / 技巧各有一个语义色，用于行首的标签文字，保证扫读时「同色同义」。
   */
  private tagColor(t: string): string {
    if (t === '政策') {
      return Semantic.INFO;
    }
    if (t === '概念') {
      return Brand.PRIMARY;
    }
    if (t === '数据') {
      return Semantic.ALERT;
    }
    if (t === '技巧') {
      return CatColor.FOOD;
    }
    return Ink.L2;
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // ============ 英雄区：标题 + 副标题 + 分类/篇数小统计 ============
          HeroCard({ variant: 'fresh', period: `${ARTICLES.length} 篇`, stamp: '科普' }) {
            Column() {
              Text('双 碳 科 普')
                .fontFamily(Serif.FAMILY)
                .fontSize(26)
                .fontColor(Ink.ON_BRAND)
                .letterSpacing(2)
                .width('100%')

              Text('了解碳中和，才能更好地记录低碳生活。')
                .fontSize(11)
                .fontColor(Ink.ON_BRAND_3)
                .lineHeight(18)
                .width('100%')
                .margin({ top: 8 })

              Column()
                .width('100%')
                .height(1)
                .backgroundColor('#33F7F2E6')
                .margin({ top: 16 })

              Row() {
                Text(`${allTags().length} 个分类`)
                  .fontSize(10)
                  .fontColor(Ink.ON_BRAND_3)
                  .letterSpacing(1)
                  .fontFeature('"tnum" 1')
                Blank()
                Text(`共 ${ARTICLES.length} 篇`)
                  .fontSize(10)
                  .fontColor(Ink.ON_BRAND_3)
                  .fontFeature('"tnum" 1')
              }
              .width('100%')
              .margin({ top: 10 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // ============ 标签筛选：裸芯片一行 ============
          // 原来这里是一张 SectionCard，只装 5 个胶囊 —— 卡片一多，页面就成了「一摞卡」。
          // 标签是筛选条，不是内容块，做成无卡的一行更符合它的身份。
          Scroll() {
            Row() {
              Chip({
                label: '全部',
                selected: this.tag.length === 0,
                onTap: () => {
                  this.applyFilter('');
                }
              })
              ForEach(allTags(), (t: string) => {
                Chip({
                  label: t,
                  selected: this.tag === t,
                  onTap: () => {
                    this.applyFilter(t);
                  }
                })
              }, (t: string) => t)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .align(Alignment.Start)
          .width('100%')
          .margin({ bottom: Space.SM })

          // ============ 文章列表：一张纸 + 若干行 ============
          // 原来是「一篇一张卡」：10 篇就是 10 张带内边距的白卡，翻起来像一摞便签。
          // 现在收进同一张账页，行与行用发丝线分隔，展开仍在本行内完成 ——
          // 内容一个字没少，卡片数从 10 降到 1。
          if (this.list.length > 0) {
            SectionCard({
              title: this.tag.length === 0 ? '全 部 科 普' : `${this.tag}`,
              icon: $r('app.media.ic_tab_book'),
              showIcon: true,
              badge: `${this.list.length} 篇`,
              badgeColor: Brand.PRIMARY
            }) {
              Column() {
                ForEach(this.list, (a: Article) => {
                  Column() {
                    Row() {
                      Column() {
                        Row() {
                          Text(`· ${a.tag}`)
                            .fontSize(10)
                            .letterSpacing(1)
                            .fontColor(this.tagColor(a.tag))
                          Text(a.title)
                            .fontFamily(Serif.FAMILY)
                            .fontSize(14)
                            .fontColor(Ink.L1)
                            .layoutWeight(1)
                            .margin({ left: 6 })
                        }
                        .width('100%')
                        .alignItems(VerticalAlign.Center)

                        Text(a.summary)
                          .fontSize(FontSize.BODY_S)
                          .fontColor(Ink.L3)
                          .lineHeight(LineHeight.BODY_S)
                          .maxLines(this.expanded === a.id ? 99 : 2)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .width('100%')
                          .margin({ top: 4 })
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)

                      // 展开态只靠箭头转 90°，省掉「展 开 / 收 起」那一整行
                      Image($r('app.media.ic_arrow'))
                        .width(13)
                        .height(13)
                        .fillColor(Ink.L4)
                        .objectFit(ImageFit.Contain)
                        .rotate({ angle: this.expanded === a.id ? 90 : 0 })
                        .margin({ left: Space.SM, top: 3 })
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Top)

                    if (this.expanded === a.id) {
                      Divider()
                        .color(Edge.HAIR)
                        .strokeWidth(1)
                        .margin({ top: Space.MD, bottom: Space.MD })

                      Text(a.body)
                        .fontSize(FontSize.BODY_M)
                        .fontColor(Ink.L2)
                        .lineHeight(LineHeight.BODY_L)
                        .width('100%')
                    }
                  }
                  .width('100%')
                  .padding({ top: 12, bottom: 12 })
                  .border({ width: { bottom: 0.8 }, color: Rule.HAIR })
                  .onClick(() => {
                    animateTo(Motion.QUICK, () => {
                      this.expanded = this.expanded === a.id ? '' : a.id;
                    });
                  })
                }, (a: Article) => a.id)
              }
              .width('100%')
            }
          }

          // ============ 空状态 ============
          if (this.list.length === 0) {
            EmptyHint({
              title: '该标签下暂无内容',
              desc: '换个标签看看，或点「全部」浏览全部科普。',
              icon: $r('app.media.ic_tab_book')
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
    // 纸纹兼作底色（backgroundColor 会盖住 backgroundImage）
    .backgroundImage($r('app.media.paper_page'), ImageRepeat.XY)
  }
}
