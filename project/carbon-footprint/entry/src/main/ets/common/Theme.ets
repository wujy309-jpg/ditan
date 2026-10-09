/**
 * 碳迹 · 设计令牌（Design Tokens）v2
 *
 * 数值来源：《HarmonyOS 设计规范》官方文档（逐字核对，见工作区
 * 《HarmonyOS-视觉改造调研报告.md》）。凡标「官方」的都有出处，
 * 标「本项目」的是在官方框架内的自有取舍。
 *
 * 三条最重要的官方原则（也是这次改造的依据）：
 *   1. 同层统一 + 层级正相关 —— **层级越高，圆角越大**。
 *   2. 文本要分四级，不能所有文字一个黑。
 *   3. 间距优先取 4 / 8 的倍数；卡片之间 12、卡片内边距 16、屏幕左右 16。
 *
 * ── v2 修订说明（本次美化）──────────────────────────────────────────────
 * v1 的问题不是缺令牌，而是**令牌只落地了 15%**：全工程还有 104 处裸写颜色
 * （其中 #FFFFFF 37 次、#1F9A4E 19 次）和 12 个「孤儿色」，它们是随手写的、
 * 不在任何规范里 —— 这正是界面看上去「拼贴、不统一」的根源。
 *
 * v2 做了三件事：
 *   1. 把 12 个孤儿色全部收编进令牌（见 Edge / Ink / Semantic），从源头消灭裸写；
 *   2. 补齐「让卡片有质感」缺的那几档：高光边（Sheen）、光晕（Glow）、
 *      浮起阴影（shadowFloat）、卡片内分隔线；
 *   3. 新增动效令牌（Motion.ENTER / PRESS / COUNT）—— v1 定义了弹簧曲线
 *      但全工程 0 次调用，等于没有。v2 把「怎么用」也写进注释。
 */
import { curves } from '@kit.ArkUI';

// ---------------------------------------------------------------------------
// 圆角：官方五档
// ---------------------------------------------------------------------------
export class Radius {
  /** 标签、角标、占位色块 */
  static readonly XS: number = 4;
  /** 图片、图标容器、微卡 */
  static readonly SM: number = 8;
  /** 普通卡片、内容容器 —— 官方指定值 */
  static readonly MD: number = 16;
  /** 按钮、菜单、选项卡 */
  static readonly LG: number = 20;
  /** 主卡、英雄区、半模态、弹窗 */
  static readonly XL: number = 32;
  /** 特大容器（全宽英雄区） */
  static readonly XXL: number = 36;
  /** 胶囊 */
  static readonly FULL: number = 999;
}

// ---------------------------------------------------------------------------
// 间距：8vp 体系（官方要求优先取 4/8 倍数）
// ---------------------------------------------------------------------------
export class Space {
  static readonly XS: number = 4;
  static readonly SM: number = 8;
  /** 卡片与卡片之间 —— 官方指定 12，不是 16 */
  static readonly MD: number = 12;
  /** 屏幕左右边距 / 卡片内边距 —— 官方指定 16 */
  static readonly LG: number = 16;
  static readonly XL: number = 20;
  static readonly XXL: number = 24;
  static readonly HUGE: number = 32;
}

// ---------------------------------------------------------------------------
// 文本色：官方四级（黑底不同透明度叠加）
// ---------------------------------------------------------------------------
export class Ink {
  /** 85% —— 标题、关键数字、最重要的信息 */
  static readonly L1: string = '#E5000000';
  /** 60% —— 正文、次级信息 */
  static readonly L2: string = '#99000000';
  /** 40% —— 辅助说明、单位、时间戳 */
  static readonly L3: string = '#66000000';
  /** 20% —— 占位符、禁用态 */
  static readonly L4: string = '#33000000';
  /** 反白文字（用在渐变卡上） */
  static readonly ON_BRAND: string = '#FFFFFF';
  /** 反白次级文字 */
  static readonly ON_BRAND_2: string = '#D7E8DC';
  /** 反白三级文字（英雄区最弱的一层） */
  static readonly ON_BRAND_3: string = '#A8CDB6';
}

// ---------------------------------------------------------------------------
// 分隔线 / 描边
//
// v2 新增。v1 里这两档是裸写的 #D8DEE6 和 #EBEFF4 —— 前者偏蓝、比 Ink.L3 还亮，
// 是「同一个界面里灰度不统一」的直接来源。收编成令牌后全工程只剩一种描边灰度。
// ---------------------------------------------------------------------------
export class Edge {
  /** 卡片内分隔线（几乎看不见，只做视觉分组） */
  static readonly HAIR: string = '#14000000';
  /** 卡片外描边 / 胶囊边框 */
  static readonly NORMAL: string = '#1F000000';
  /** 需要被看见的边框（如未选中的可点区域） */
  static readonly STRONG: string = '#33000000';
  /** 卡片顶部高光边 —— 半透明白，制造「玻璃厚度」 */
  static readonly SHEEN: string = '#40FFFFFF';
  /** 渐变卡上的内部分隔 */
  static readonly ON_BRAND: string = '#33FFFFFF';
}

// ---------------------------------------------------------------------------
// 品牌色
// ---------------------------------------------------------------------------
export class Brand {
  static readonly PRIMARY: string = '#1F9A4E';
  static readonly DEEP: string = '#0B7A3B';
  /** 更深一档，用于深色英雄区收口 */
  static readonly INK: string = '#064E26';
  static readonly BRIGHT: string = '#26A85C';
  /** 提亮一档，用于渐变高光点 */
  static readonly LIME: string = '#5CC98A';
  /** 最浅一档，仅用于「渐变的下端」（如柱状图柱身），不做文字与描边 */
  static readonly LIGHT: string = '#7FD3A5';
  /** 浅色底：用于选中态、标签底 */
  static readonly SOFT: string = '#E8F3EC';
  /** 更浅一档，用于大面积铺底 */
  static readonly MIST: string = '#F2F9F5';
}

// ---------------------------------------------------------------------------
// 语义色：官方三件套 + 各自的浅底
//
// v1 只定义了「色」，没定义「底」。结果各处自己配浅底，出现了 #FFF8E8、#FBEAE8
// 等一批孤儿色。v2 成对提供：用 Alert 就一定用 AlertSoft。
// ---------------------------------------------------------------------------
export class Semantic {
  static readonly WARNING: string = '#E84026';
  static readonly WARNING_SOFT: string = '#FBEAE8';
  static readonly ALERT: string = '#ED6F21';
  static readonly ALERT_SOFT: string = '#FDF0E7';
  static readonly CONFIRM: string = '#64BB5C';
  static readonly CONFIRM_SOFT: string = '#EAF6E9';
  static readonly INFO: string = '#0A59F7';
  static readonly INFO_SOFT: string = '#E7F0FE';
}

// ---------------------------------------------------------------------------
// 背景
// ---------------------------------------------------------------------------
export class Bg {
  /** 官方 background_secondary */
  static readonly PAGE: string = '#F1F3F5';
  static readonly CARD: string = '#FFFFFF';
  /** 微卡填充（第三级卡片，无阴影） */
  static readonly SUBTLE: string = '#F5F7FA';
  /** 比微卡再深一点，用于输入框等「凹陷」元素 */
  static readonly SUNKEN: string = '#F0F2F5';
  /** 分隔线 */
  static readonly LINE: string = '#EBEFF4';
  /** 遮罩 */
  static readonly MASK: string = '#33000000';
}

// ---------------------------------------------------------------------------
// 字号：官方阶梯
// 注意 Display 级官方用 **Light** 字重，大数字用 Bold 会显得笨重。
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

/**
 * 行高。v1 全工程只有一处显式 lineHeight，正文行距靠默认值 ——
 * 长段落（科普正文、低碳建议）读起来会「挤」。官方要求正文行高约为字号的 1.5–1.6 倍。
 */
export class LineHeight {
  /** 12 号字配 18 —— 说明文字 */
  static readonly BODY_S: number = 18;
  /** 13 号字配 21 —— 列表正文 */
  static readonly BODY_M: number = 21;
  /** 14 号字配 23 —— 科普正文 */
  static readonly BODY_L: number = 23;
}

/**
 * 字重。
 *
 * ⚠️ 官方 Display 规格是 Light（300），但 ArkUI 的 FontWeight 只暴露
 * Lighter / Normal / Regular / Medium / Bold / Bolder 六档，没有 300。
 * 这里用 Normal（400）作为最接近的等价 —— 关键是大数字**不要用 Bold**，
 * 用 Bold 会显得笨重，这是「高级感」和「廉价感」的分水岭。
 */
export class Weight {
  static readonly DISPLAY: FontWeight = FontWeight.Normal;
  static readonly TITLE: FontWeight = FontWeight.Bold;
  static readonly SUBTITLE: FontWeight = FontWeight.Medium;
  static readonly BODY: FontWeight = FontWeight.Normal;
}

// ---------------------------------------------------------------------------
// 四个行为类目的识别色
// 官方要求「主色相不超过 3 种」是针对整体画面的；这里是**数据分类色**，
// 属于数据可视化用色，且只在饼图/标签等局部出现，不参与大面积铺底。
// ---------------------------------------------------------------------------
export class CatColor {
  static readonly TRAVEL: string = '#1F9A4E';
  static readonly ENERGY: string = '#0A59F7';
  static readonly RECYCLE: string = '#ED6F21';
  static readonly FOOD: string = '#7B5BD6';

  static readonly TRAVEL_SOFT: string = '#E8F3EC';
  static readonly ENERGY_SOFT: string = '#E7F0FE';
  static readonly RECYCLE_SOFT: string = '#FDF0E7';
  static readonly FOOD_SOFT: string = '#F1EDFC';
}

/**
 * 日历热力图的四级色阶（v2 新增）。
 *
 * 为什么单独定义而不复用 Brand.*：热力图需要**四级明度差可辨**的同一色相，
 * 而品牌色只有 3 档且其中两档太接近，直接拿来用会出现"两格看不出深浅"。
 * 0 值格子用 `Bg.SUBTLE`（中性灰），表示"这天没有记录"而不是"低碳"，语义上要区分开。
 */
export class Heat {
  static readonly L1: string = '#C9E8D5';
  static readonly L2: string = '#8FD3AC';
  static readonly L3: string = '#4CB078';
  static readonly L4: string = '#0B7A3B';
  /**
   * 无记录。
   * ⚠️ 别调深：热力图里「没记录」的格子占绝大多数，
   *    一旦它们有了实心色块的重量，整张图会变成一片灰底、
   *    反而把真正有数据的那几格淹没掉。
   */
  static readonly EMPTY: string = '#F0F2F5';
}

// ---------------------------------------------------------------------------
// 阴影
// ⚠️ 官方原文：shadow() 的 radius / offsetX / offsetY **单位是 px 不是 vp**，
//    需用 vp2px 换算。这是「写了阴影却看不见」的典型原因（3x 屏上 8px 只有 2.7vp）。
// ⚠️ 官方在移动端主要用「蒙层 + 明度」表达层级，阴影只作辅助，所以这里刻意做得很轻。
// ---------------------------------------------------------------------------
export interface Elevation {
  radius: number;
  color: string;
  offsetX: number;
  offsetY: number;
}

/** 次卡：最常见的一档，轻到几乎看不出，但能托起卡片 */
export function shadowCard(): ShadowOptions {
  return {
    radius: vp2px(12),
    color: '#14000000',
    offsetX: 0,
    offsetY: vp2px(2)
  };
}

/** 浮起：用于需要强调的卡片（如当前选中的任务） */
export function shadowRaised(): ShadowOptions {
  return {
    radius: vp2px(20),
    color: '#1A000000',
    offsetX: 0,
    offsetY: vp2px(6)
  };
}

/** 轻提示：列表行、内嵌小块 */
export function shadowSubtle(): ShadowOptions {
  return {
    radius: vp2px(8),
    color: '#0F000000',
    offsetX: 0,
    offsetY: vp2px(1)
  };
}

/**
 * v2 新增：**绿色投影**。
 *
 * 这是让「主卡」从背景里跳出来的关键一招 —— 普通灰投影只能表达「浮起」，
 * 而带主色的投影会把卡片染成环境色，观感上贵一档。
 * 注意透明度必须很低（12%），高了立刻变「廉价发光」。
 */
export function shadowBrand(): ShadowOptions {
  return {
    radius: vp2px(24),
    color: '#1F1F9A4E',
    offsetX: 0,
    offsetY: vp2px(8)
  };
}

/** 英雄区下方的主卡：范围大、几乎无色，只做「离开背景」的暗示 */
export function shadowFloat(): ShadowOptions {
  return {
    radius: vp2px(28),
    color: '#12000000',
    offsetX: 0,
    offsetY: vp2px(10)
  };
}

// ---------------------------------------------------------------------------
// 渐变
// ---------------------------------------------------------------------------

/**
 * 英雄区渐变：从亮绿到深绿，135° 让左上更亮，符合光照直觉。
 *
 * ⚠️ 为什么是 4 个色标而不是 3 个（这是踩坑之后的修正）：
 *    最初想在渐变之上再叠一层径向光斑（overlay + radialGradient）来做"光感"，
 *    实测发现 overlay 的尺寸与宿主不一致，径向渐变的边界在卡片上留下**一道竖直接缝**，
 *    非常明显。既然叠加不可靠，就改成**在渐变本身里做层次**：
 *    多一个 `LIME` 高光色标放在 12% 处，等价于"光从左上打过来"，
 *    而且零层级、零接缝、零性能开销。
 */
export function heroGradient(): LinearGradientOptions {
  return {
    angle: 135,
    colors: [[Brand.LIME, 0.0], [Brand.BRIGHT, 0.14], [Brand.PRIMARY, 0.58], [Brand.DEEP, 1.0]]
  };
}

/**
 * v2 新增：**深色英雄区**。
 *
 * 为什么需要第二个英雄渐变：v1 全应用只有一种绿渐变，看板/积分/科普的顶卡
 * 长得一模一样，页面之间没有辨识度。深色版把重心压在墨绿，
 * 用在「数据看板」这种需要沉稳气质的页面。
 */
export function heroGradientDeep(): LinearGradientOptions {
  return {
    angle: 160,
    colors: [[Brand.BRIGHT, 0.0], [Brand.PRIMARY, 0.22], [Brand.DEEP, 0.66], [Brand.INK, 1.0]]
  };
}

/** v2 新增：清爽版（亮绿→绿），用于科普这类需要「轻松」气质的页面 */
export function heroGradientFresh(): LinearGradientOptions {
  return {
    angle: 120,
    colors: [[Brand.LIME, 0.0], [Brand.BRIGHT, 0.38], [Brand.PRIMARY, 0.82], [Brand.DEEP, 1.0]]
  };
}

/** 次级渐变卡（较弱，用于不想抢主卡风头的区块） */
export function softGradient(): LinearGradientOptions {
  return {
    angle: 135,
    colors: [[Brand.PRIMARY, 0.0], [Brand.DEEP, 1.0]]
  };
}

/** 顶部装饰性径向光晕，叠在英雄区上增加纵深感 */
export function heroGlow(): RadialGradientOptions {
  return {
    center: ['78%', '12%'],
    radius: '62%',
    colors: [['#33FFFFFF', 0.0], ['#00FFFFFF', 1.0]]
  };
}

/**
 * v2 新增：加强版光晕（更大、更亮）。
 * 配合 heroGlow() 一前一后叠两层，英雄区就有了「光从左上打过来」的体积感。
 */
export function heroGlowStrong(): RadialGradientOptions {
  return {
    center: ['18%', '88%'],
    radius: '70%',
    colors: [['#26FFFFFF', 0.0], ['#00FFFFFF', 1.0]]
  };
}

/**
 * v2 新增：**进度条 / 迷你条的横向渐变**。
 * 用于分类占比条、目标进度条 —— 纯色条会显得「平」，横向渐变有推进感。
 */
export function barGradient(): LinearGradientOptions {
  return {
    angle: 90,
    colors: [[Brand.LIME, 0.0], [Brand.PRIMARY, 1.0]]
  };
}

/** v2 新增：主按钮渐变（比纯色按钮多一点「材质」） */
export function buttonGradient(): LinearGradientOptions {
  return {
    angle: 135,
    colors: [[Brand.BRIGHT, 0.0], [Brand.PRIMARY, 1.0]]
  };
}

/**
 * v2 新增：**环形进度没法用线性渐变**，用扫描渐变（sweep）做出「从浅到深」的
 * 进度拖尾，这是让进度环从「系统控件」变成「设计过的图形」的关键。
 */
export function ringGradient(): SweepGradientOptions {
  return {
    center: ['50%', '50%'],
    start: 0,
    end: 360,
    colors: [[Brand.LIME, 0.0], [Brand.BRIGHT, 0.5], [Brand.PRIMARY, 1.0]]
  };
}

/**
 * v2 新增：**装饰性色斑**。
 * 在没有插画素材的前提下，用两三个大半径、低饱和的径向色斑叠在英雄区上，
 * 就能做出「mesh gradient（网格渐变）」的现代感 —— 这是零素材条件下
 * 性价比最高的一招，具体用法见 heroDeco 注释。
 */
export function decoBlob(x: string, y: string, color: string): RadialGradientOptions {
  // ⚠️ 坑：渐变的**收尾色必须与起始色同色相、只把透明度降到 0**。
  //    写成 '#00FFFFFF'（透明白）去收 '#1A000000'（半透明黑）的尾，
  //    中间会插值出一圈灰雾，在色斑边界上留下一道肉眼可见的「接缝」。
  const fade: string = `#00${color.substring(1)}`;
  return {
    center: [x, y],
    radius: '55%',
    colors: [[color, 0.0], [fade, 1.0]]
  };
}

// ---------------------------------------------------------------------------
// 动效：官方推荐物理曲线而非线性曲线
// 「弹簧曲线在到达终点时速度为 0，不会产生动画戛然而止的观感」
//
// ⚠️ v1 定义了 SMOOTH / QUICK 但**一次都没调用**，全工程零动画。
//    v2 把三个场景拆开，并对每个场景写清「用在哪」，避免再次定义即闲置：
//      ENTER —— 页面/卡片入场（位移 + 淡入）
//      PRESS —— 按下反馈（缩放，必须 ≤ 120ms 才有「跟手」感）
//      COUNT —— 数字滚动（慢，让用户看清数字在变）
// ---------------------------------------------------------------------------
export class Motion {
  /** 常规入场/切换 */
  static readonly SMOOTH: AnimateParam = {
    duration: 320,
    curve: curves.springMotion(0.38, 0.9)
  };
  /** 快速反馈（按压、选中） */
  static readonly QUICK: AnimateParam = {
    duration: 180,
    curve: curves.springMotion(0.4, 0.95)
  };
  /** 卡片入场：稍慢一点，位移更明显，让「内容长出来」这件事被看见 */
  static readonly ENTER: AnimateParam = {
    duration: 380,
    curve: curves.springMotion(0.34, 0.92)
  };
  /** 按压反馈：必须短 */
  static readonly PRESS: AnimateParam = {
    duration: 110,
    curve: Curve.Friction
  };
  /** 数字滚动：用减速曲线，末段变慢便于读数 */
  static readonly COUNT: AnimateParam = {
    duration: 800,
    curve: Curve.EaseOut
  };
}

/** 按压时的缩放比 —— 0.96 是「有反馈但不夸张」的经验值 */
export const PRESS_SCALE: number = 0.96;

/** 卡片入场时向上位移的距离（vp） */
export const ENTER_OFFSET: number = 14;

/** 入场动画的错峰间隔（ms）：第 n 张卡片延迟 n × 这个值 */
export const STAGGER_STEP: number = 45;
