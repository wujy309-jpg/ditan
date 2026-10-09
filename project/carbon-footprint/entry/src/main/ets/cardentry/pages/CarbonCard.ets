/**
 * 桌面卡片 UI —— 碳迹
 *
 * 这是鸿蒙「万能卡片」，直接显示在桌面上，用户不必打开应用就能看到今日碳数据。
 * 数据由 CarbonCardAbility 通过 formBindingData 传入，本文件只负责渲染。
 *
 * 卡片组件有限制：只能用基础组件（Column / Row / Text / Divider / Stack 等），
 * 因此迷你趋势图用「一排不同高度的色块」实现，而不是图表库。
 */
import { CardData } from '../CarbonCardAbility';

/** 卡片通过 LocalStorage 接收 Ability 传来的数据 */
let storage = new LocalStorage();

@Entry(storage)
@Component
struct CarbonCard {
  @LocalStorageProp('todaySaved') todaySaved: string = '—';
  @LocalStorageProp('todayPoints') todayPoints: string = '—';
  @LocalStorageProp('totalSaved') totalSaved: string = '—';
  @LocalStorageProp('recordCount') recordCount: string = '—';
  @LocalStorageProp('dateText') dateText: string = '';
  @LocalStorageProp('bars') bars: string = '6,6,6,6,6,6,6';
  @LocalStorageProp('tip') tip: string = '';

  /** 把 "20,45,60" 解析成数组 */
  private barList(): string[] {
    const parts: string[] = this.bars.split(',');
    return parts.length > 0 ? parts : ['6'];
  }

  private isTodayEmpty(): boolean {
    return this.todaySaved === '0' || this.todaySaved === '—';
  }

  build() {
    Column() {
      // 顶部：应用名 + 日期
      Row() {
        Text('碳迹')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F9A4E')
        Blank()
        Text(this.dateText)
          .fontSize(11)
          .fontColor('#66000000')
      }
      .width('100%')

      // 主数值
      Row() {
        // 官方 2×2 卡片主数字 32fp；用 Normal 字重而非 Bold，避免小尺寸下发闷
        Text(this.todaySaved)
          .fontSize(32)
          .fontWeight(FontWeight.Normal)
          .fontColor('#E5000000')
        Text(' kg')
          .fontSize(12)
          .fontColor('#66000000')
          .margin({ left: 2, bottom: 4 })
      }
      .alignItems(VerticalAlign.Bottom)
      .width('100%')
      .margin({ top: 4 })

      Text('今日减排 CO₂e')
        .fontSize(10)
        .fontColor('#66000000')
        .width('100%')

      // 迷你 7 日趋势
      Row() {
        ForEach(this.barList(), (h: string) => {
          Column()
            .width(6)
            .height(`${h}%`)
            .backgroundColor('#1F9A4E')
            .borderRadius(2)
            .margin({ right: 3 })
            .opacity(0.85)
        }, (h: string, i: number) => `${i}-${h}`)
      }
      .width('100%')
      .height(28)
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 8 })

      Divider()
        .color('#E8F3EC')
        .margin({ top: 6, bottom: 6 })

      // 底部：积分 + 提示
      Row() {
        Text(`${this.todayPoints}`)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#D98A00')
        Text(' 积分')
          .fontSize(10)
          .fontColor('#66000000')
        Blank()
        Text(`累计 ${this.totalSaved} kg`)
          .fontSize(10)
          .fontColor('#66000000')
      }
      .width('100%')

      Text(this.tip)
        .fontSize(9)
        .fontColor(this.isTodayEmpty() ? '#D98A00' : '#1F9A4E')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .height('100%')
    // 官方《服务卡片设计规范》：2×2 卡片安全边距 12vp、圆角 18vp
    .padding(12)
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
    .onClick(() => {
      // 点卡片直接进应用
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { from: 'card' }
      });
    })
  }
}
