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
  Bg, Brand, CatColor, Edge, FontSize, Ink, LineHeight, Motion, Radius,
  Semantic, Space, Weight
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
   * 政策 / 概念 / 数据 / 技巧必须与 tagSoft() 成对使用，保证「同色同义」。
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

  /** 标签 → 浅色底（与 tagColor 一一对应） */
  private tagSoft(t: string): string {
    if (t === '政策') {
      return Semantic.INFO_SOFT;
    }
    if (t === '概念') {
      return Brand.SOFT;
    }
    if (t === '数据') {
      return Semantic.ALERT_SOFT;
    }
    if (t === '技巧') {
      return CatColor.FOOD_SOFT;
    }
    return Bg.SUBTLE;
  }

  /** 标签 → 图标；只用 app.media 下确实存在的图标 */
  private tagIcon(t: string): Resource {
    if (t === '政策') {
      return $r('app.media.ic_target');
    }
    if (t === '概念') {
      return $r('app.media.ic_leaf');
    }
    if (t === '数据') {
      return $r('app.media.ic_tab_chart');
    }
    if (t === '技巧') {
      return $r('app.media.ic_flame');
    }
    return $r('app.media.ic_tab_book');
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          // ============ 英雄区：标题 + 副标题 + 分类/篇数小统计 ============
          HeroCard({ variant: 'fresh' }) {
            Row() {
              Column() {
                Text('双碳科普')
                  .fontSize(FontSize.TITLE_M)
                  .fontWeight(Weight.TITLE)
                  .fontColor(Ink.ON_BRAND)
                Text(`共 ${ARTICLES.length} 篇 · 了解碳中和，才能更好地记录低碳生活`)
                  .fontSize(FontSize.BODY_S)
                  .fontColor(Ink.ON_BRAND_2)
                  .lineHeight(LineHeight.BODY_S)
                  .margin({ top: 6 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              // 大号半透明书本：纯装饰，不承载信息。
              // 这里的 #33FFFFFF 是「叠在渐变上的透明白」，属于装饰而非语义色，故不走令牌。
              Image($r('app.media.ic_tab_book'))
                .width(72)
                .height(72)
                .fillColor('#33FFFFFF')
                .objectFit(ImageFit.Contain)
                .margin({ left: Space.SM })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 英雄区底部两个小胶囊：分类数 / 篇数。
            // 底色的 #26FFFFFF 是「叠在绿渐变上的 15% 透明白」，与看板页英雄区同语言，
            // 属于装饰性反白、不是语义色，所以不走令牌。
            Row() {
              Text(`${allTags().length} 个分类`)
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.ON_BRAND)
                .backgroundColor('#26FFFFFF')
                .borderRadius(Radius.FULL)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
              Text(`${ARTICLES.length} 篇科普`)
                .fontSize(FontSize.BODY_S)
                .fontColor(Ink.ON_BRAND)
                .backgroundColor('#26FFFFFF')
                .borderRadius(Radius.FULL)
                .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                .margin({ left: Space.SM })
            }
            .width('100%')
            .margin({ top: Space.LG })
          }

          // ============ 标签筛选 ============
          SectionCard({
            title: '按标签浏览',
            icon: $r('app.media.ic_target'),
            showIcon: true,
            badge: `${this.list.length} 篇`,
            badgeColor: Brand.PRIMARY,
            badgeSoft: Brand.SOFT
          }) {
            Flex({ wrap: FlexWrap.Wrap }) {
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
            .width('100%')
          }

          // ============ 文章列表 ============
          ForEach(this.list, (a: Article) => {
            // 外层 Column 只负责「整卡可点」与卡间距：
            // 自定义组件（SectionCard）上不挂 onClick，避免通用属性作用域不确定。
            Column() {
              SectionCard({ title: '', showIcon: false, bottomSpace: 0 }) {
                Row() {
                  // 40×40 分类色圆角图标块：让每张卡先「有图形」，再读文字
                  Column() {
                    Image(this.tagIcon(a.tag))
                      .width(20)
                      .height(20)
                      .fillColor(this.tagColor(a.tag))
                      .objectFit(ImageFit.Contain)
                  }
                  .width(40)
                  .height(40)
                  .borderRadius(Radius.SM)
                  .backgroundColor(this.tagSoft(a.tag))
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)

                  Column() {
                    Row() {
                      Text(a.tag)
                        .fontSize(FontSize.CAPTION)
                        .fontWeight(Weight.SUBTITLE)
                        .fontColor(this.tagColor(a.tag))
                        .backgroundColor(this.tagSoft(a.tag))
                        .borderRadius(Radius.XS)
                        .padding({ left: 7, right: 7, top: 3, bottom: 3 })

                      Text(a.title)
                        .fontSize(FontSize.SUB_M)
                        .fontWeight(Weight.SUBTITLE)
                        .fontColor(Ink.L1)
                        .layoutWeight(1)
                        .margin({ left: Space.SM })
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)

                    Text(a.summary)
                      .fontSize(FontSize.BODY_S)
                      .fontColor(Ink.L3)
                      .lineHeight(LineHeight.BODY_S)
                      .width('100%')
                      .margin({ top: 5 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .margin({ left: Space.MD })
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)

                // 展开 / 收起：文字右侧箭头，展开时右箭头转 90° 变成下箭头
                Row() {
                  Text(this.expanded === a.id ? '收起' : '展开')
                    .fontSize(FontSize.BODY_S)
                    .fontWeight(Weight.SUBTITLE)
                    .fontColor(Ink.L3)
                  Image($r('app.media.ic_arrow'))
                    .width(14)
                    .height(14)
                    .fillColor(Ink.L3)
                    .objectFit(ImageFit.Contain)
                    .rotate({ angle: this.expanded === a.id ? 90 : 0 })
                    .margin({ left: 2 })
                }
                .width('100%')
                .justifyContent(FlexAlign.End)
                .alignItems(VerticalAlign.Center)
                .margin({ top: Space.SM })

                if (this.expanded === a.id) {
                  // 发丝线把摘要与正文分开，长正文才不会和摘要糊成一片
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
            }
            .width('100%')
            .margin({ bottom: Space.MD })
            .onClick(() => {
              // 箭头旋转与正文高度变化都走快速弹性曲线，避免「啪」地跳变
              animateTo(Motion.QUICK, () => {
                this.expanded = this.expanded === a.id ? '' : a.id;
              });
            })
          }, (a: Article) => a.id)

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
    .backgroundColor(Bg.PAGE)
  }
}
