/**
 * 碳迹 · 设计令牌 v3 —— 「碳账本」
 *
 * ── 为什么要推翻 v2 ────────────────────────────────────────────────────────
 * v2 把界面做「干净」了，但干净不等于有辨识度：渐变英雄卡 + 白色圆角卡片流
 * + 胶囊标签，是 2024–2026 年所有 AI 辅助生成的移动端作品共用的同一套模具。
 * 把绿色换成蓝色、把 logo 换掉，界面依然成立 —— 一个「可替换」的界面，
 * 在评委眼里就是可替换的作品。
 *
 * v3 换的不是配色，是**信息的形状**：从「卡片堆」改成「一页账」。
 *   碳积分本质是记账：活动量 × 因子 = 减排量，每一条都可追溯、可核查。
 *   账本 / 凭证 / 印章的语言，恰好是这个产品真正的内核。
 *
 * ── 三条硬规则（改任何页面都先读这三条）──────────────────────────────────
 *   1. **不用卡片，用细线分组。** 圆角一律 2，阴影一律透明。分组靠 1px 横线
 *      与留白，不靠白底块。屏幕是纸，不是一堆漂浮的卡片。
 *   2. **数字右对齐、等宽。** Text 上挂 `.fontFeature('"tnum" 1')`（API 12 起
 *      支持，系统 HarmonyOS Sans SC 自带 tnum 特性，不用装字体）。
 *   3. **标题用宋体，正文用黑体。** 这是印刷品的分工：宋体做 Display，
 *      黑体做阅读。全篇一个字体，就会回到「模板感」。
 *
 * ── 配色 ─────────────────────────────────────────────────────────────────
 *   纸（暖米白）+ 墨（暖黑）+ 朱砂（印章红）+ 墨绿（数据）。四种颜色，各司其职。
 *   朱砂是这套语言里**唯一的高饱和色**，只用在印章、强调数字、选中标记上，
 *   全屏出现面积不超过 2%。它一多，就从「账本」变成「喜庆」。
 */
import { curves } from '@kit.ArkUI';

// ---------------------------------------------------------------------------
// 字体
// ---------------------------------------------------------------------------

/**
 * 宋体族名。
 * 字体文件是 Noto Serif CJK SC（SIL OFL 1.1），已按本工程用到的 1176 个字符
 * 子集化到 rawfile/fonts/LedgerSerif.otf（约 546 KB），在 Index.ets 启动时注册。
 *
 * ⚠️ 只给**固定文案**用（标题、期次、印章）。用户输入的昵称不要用它 ——
 *    子集字体没有那些字，缺字会渲染成豆腐块。
 */
export class Serif {
  static readonly FAMILY: string = 'LedgerSerif';
}

// ---------------------------------------------------------------------------
// 纸
// ---------------------------------------------------------------------------
export class Bg {
  /** 纸：整页底色，暖米白。不是纯白，也不是冷灰。 */
  static readonly PAGE: string = '#F2EDE1';
  /** 账页：比纸再亮半档，用来做「贴上去的一张纸」 */
  static readonly CARD: string = '#FBF8F1';
  /** 表格底 / 次级分组 */
  static readonly SUBTLE: string = '#EDE7D8';
  /** 凹陷：输入框、进度槽 */
  static readonly SUNKEN: string = '#E8E1CF';
  /** 分隔线 */
  static readonly LINE: string = '#DED5C0';
  /** 遮罩 */
  static readonly MASK: string = '#33000000';
}

// ---------------------------------------------------------------------------
// 墨：四级文字，暖黑（不用纯黑 —— 纯黑压在米白纸上会「跳」，像印刷漏墨）
// ---------------------------------------------------------------------------
export class Ink {
  static readonly L1: string = '#201D17';
  static readonly L2: string = '#4C463A';
  static readonly L3: string = '#857C6A';
  static readonly L4: string = '#B5AC98';
  /** 反白：深墨抬头区上的纸色字 */
  static readonly ON_BRAND: string = '#F7F2E6';
  static readonly ON_BRAND_2: string = '#C9BFA8';
  static readonly ON_BRAND_3: string = '#8E8371';
  /** 抬头区底色：墨绿近黑，压得住朱砂 */
  static readonly DECK: string = '#16211B';
}

// ---------------------------------------------------------------------------
// 线：账本的分组全靠它，所以单独给一组令牌
// ---------------------------------------------------------------------------
export class Rule {
  /** 主分隔（表头下的那条实线） */
  static readonly STRONG: string = '#211E17';
  /** 次分隔（行与行之间） */
  static readonly HAIR: string = '#D9CFB8';
  /** 虚线用的浅一档 */
  static readonly DASH: string = '#C9BEA4';
}

export class Edge {
  static readonly HAIR: string = '#1A201D17';
  static readonly NORMAL: string = '#33201D17';
  static readonly STRONG: string = '#55201D17';
  static readonly SHEEN: string = '#40FFFFFF';
  static readonly ON_BRAND: string = '#33F7F2E6';
}

// ---------------------------------------------------------------------------
// 印：朱砂。全屏出现面积 ≤ 2%
// ---------------------------------------------------------------------------
export class Seal {
  /** 朱砂 —— 印章、强调数字、选中标记 */
  static readonly RED: string = '#AB3A28';
  /** 淡朱砂 —— 标签底、弱化强调 */
  static readonly RED_SOFT: string = '#F2E2DC';
}

// ---------------------------------------------------------------------------
// 品牌（保留类名：五个页面都在 import，换值不换名）
// ---------------------------------------------------------------------------
export class Brand {
  /** 数据主色：墨绿。比 v2 的 #1F9A4E 暗一档，压得住纸色 */
  static readonly PRIMARY: string = '#1D5C43';
  static readonly DEEP: string = '#14432F';
  static readonly INK: string = '#0E2A1E';
  static readonly BRIGHT: string = '#2E7A57';
  static readonly LIME: string = '#5E9C7C';
  static readonly LIGHT: string = '#9CC4AC';
  static readonly SOFT: string = '#E3E9DF';
  static readonly MIST: string = '#EDF0E7';
}

// ---------------------------------------------------------------------------
// 语义色：同样降饱和，融进纸色
// ---------------------------------------------------------------------------
export class Semantic {
  static readonly WARNING: string = '#A6382B';
  static readonly WARNING_SOFT: string = '#F2E2DC';
  static readonly ALERT: string = '#A65A1F';
  static readonly ALERT_SOFT: string = '#F1E5D6';
  static readonly CONFIRM: string = '#2E7A57';
  static readonly CONFIRM_SOFT: string = '#E3E9DF';
  static readonly INFO: string = '#2F4A6B';
  static readonly INFO_SOFT: string = '#E2E7EE';
}

// ---------------------------------------------------------------------------
// 类目识别色：印刷套色，不要荧光
// ---------------------------------------------------------------------------
export class CatColor {
  static readonly TRAVEL: string = '#1D5C43';
  static readonly ENERGY: string = '#2F4A6B';
  static readonly RECYCLE: string = '#A65A1F';
  static readonly FOOD: string = '#5B4B6B';

  static readonly TRAVEL_SOFT: string = '#E3E9DF';
  static readonly ENERGY_SOFT: string = '#E2E7EE';
  static readonly RECYCLE_SOFT: string = '#F1E5D6';
  static readonly FOOD_SOFT: string = '#E9E4EC';
}

/**
 * 日历热力图四级。
 * 0 值格子必须是「纸上的一道浅痕」，不能是实心灰块 —— 它占了大多数格子。
 */
export class Heat {
  static readonly L1: string = '#CBD9C6';
  static readonly L2: string = '#9BB894';
  static readonly L3: string = '#5E8A63';
  static readonly L4: string = '#1D5C43';
  static readonly EMPTY: string = '#E5DECB';
}

// ---------------------------------------------------------------------------
// 圆角：账本没有圆角。留 2 是为了避免直角在低分辨率下出现锯齿毛边。
// ---------------------------------------------------------------------------
export class Radius {
  static readonly XS: number = 2;
  static readonly SM: number = 2;
  static readonly MD: number = 2;
  static readonly LG: number = 2;
  static readonly XL: number = 2;
  static readonly XXL: number = 2;
  static readonly FULL: number = 999;
}

// ---------------------------------------------------------------------------
// 间距：8vp 体系不变（官方要求 4/8 的倍数）
// ---------------------------------------------------------------------------
export class Space {
  static readonly XS: number = 4;
  static readonly SM: number = 8;
  static readonly MD: number = 12;
  static readonly LG: number = 16;
  static readonly XL: number = 20;
  static readonly XXL: number = 24;
  static readonly HUGE: number = 32;
}

// ---------------------------------------------------------------------------
// 字号
// ---------------------------------------------------------------------------
export class FontSize {
  static readonly DISPLAY_L: number = 56;
  static readonly DISPLAY_M: number = 48;
  static readonly DISPLAY_S: number = 38;
  static readonly TITLE_L: number = 30;
  static readonly TITLE_M: number = 24;
  static readonly TITLE_S: number = 20;
  static readonly SUB_L: number = 18;
  static readonly SUB_M: number = 16;
  static readonly SUB_S: number = 14;
  static readonly BODY_L: number = 16;
  static readonly BODY_M: number = 14;
  static readonly BODY_S: number = 12;
  static readonly CAPTION: number = 10;
}

export class LineHeight {
  static readonly BODY_S: number = 18;
  static readonly BODY_M: number = 21;
  static readonly BODY_L: number = 23;
}

export class Weight {
  static readonly DISPLAY: FontWeight = FontWeight.Normal;
  static readonly TITLE: FontWeight = FontWeight.Bold;
  static readonly SUBTITLE: FontWeight = FontWeight.Medium;
  static readonly BODY: FontWeight = FontWeight.Normal;
}

// ---------------------------------------------------------------------------
// 阴影：账本不用投影。函数保留（页面在 import），一律返回全透明 ——
// 这样二十多处 `.shadow(shadowCard())` 不用改一行页面代码就同时消失。
// ---------------------------------------------------------------------------

export function noShadow(): ShadowOptions {
  return { radius: 0, color: '#00000000', offsetX: 0, offsetY: 0 };
}

export function shadowCard(): ShadowOptions {
  return noShadow();
}

export function shadowRaised(): ShadowOptions {
  return noShadow();
}

export function shadowSubtle(): ShadowOptions {
  return noShadow();
}

export function shadowBrand(): ShadowOptions {
  return noShadow();
}


// ---------------------------------------------------------------------------
// 渐变：同理，全部压平成纯色。页面里的 `.linearGradient(heroGradient())`
// 会渲染成一块实心墨色 —— 由「渐变卡」变成「封面块」，结构变了但代码没动。
// ---------------------------------------------------------------------------
function flat(color: string): LinearGradientOptions {
  return { angle: 90, colors: [[color, 0.0], [color, 1.0]] };
}

export function heroGradient(): LinearGradientOptions {
  return flat(Ink.DECK);
}

export function heroGradientDeep(): LinearGradientOptions {
  return flat(Ink.DECK);
}


export function softGradient(): LinearGradientOptions {
  return flat(Bg.SUBTLE);
}


export function buttonGradient(): LinearGradientOptions {
  return flat(Ink.L1);
}





// ---------------------------------------------------------------------------
// 动效：保留 v2 的物理曲线。账本不需要花哨动画，但「翻页/盖章」要有落点。
// ---------------------------------------------------------------------------
export class Motion {
  static readonly SMOOTH: AnimateParam = {
    duration: 320,
    curve: curves.springMotion(0.38, 0.9)
  };
  static readonly QUICK: AnimateParam = {
    duration: 180,
    curve: curves.springMotion(0.4, 0.95)
  };
  static readonly ENTER: AnimateParam = {
    duration: 380,
    curve: curves.springMotion(0.34, 0.92)
  };
  static readonly PRESS: AnimateParam = {
    duration: 110,
    curve: Curve.Friction
  };
  static readonly COUNT: AnimateParam = {
    duration: 800,
    curve: Curve.EaseOut
  };
}

export const ENTER_OFFSET: number = 14;
