/**
 * 手绘抖动的**绘制**部分 —— 把 RoughMath 算好的贝塞尔交给 Canvas
 *
 * 坐标单位是 vp（ArkUI 的 Canvas 布局坐标就是 vp；Path().commands() 才是 px，
 * 这是本项目踩过的坑，见交接文档）。所以这里的数可以直接从布局尺寸传进来。
 *
 * ── 「两遍墨」到底怎么画 ─────────────────────────────────────────────────
 * 试过两遍各自独立抖动（rough.js 原版做法），在 3px/vp 的屏上两遍能差 2vp，
 * 观感是「两条分得开的线」——像拍照手抖，不像墨压了两遍。所以改成：
 *   第一遍：完整抖动幅度，满墨（alpha 1），**它决定形状**；
 *   第二遍：在第一遍的形上抖 0.4vp 的余墨，半墨（alpha 0.5）。
 * 于是边缘深浅不匀：两遍重合处深、只有一遍处浅。这才是「压印力道不匀」。
 */
import { RoughCurve, RoughPen } from '../common/RoughMath';

/** 第二遍的墨浓 —— 0.5 是试出来的：低于 0.35 看不出第二遍，高于 0.7 就只是描粗 */
const SECOND_PASS_ALPHA: number = 0.5;

/** 第二遍相对第一遍的位移幅度，按第一遍 offset 的比例取 */
const GHOST_RATIO: number = 0.55;

/** 中段弓的强度。账本的形都很小，弓多了会「软」，0.55 刚好能看出不是尺子画的 */
const BOWING: number = 0.55;

/** 余墨的种子差：取一个大质数，让两遍的随机序列彻底分开 */
const PASS_SEED_STEP: number = 7919;

/** 把一遍的曲线描出来 */
export function strokeCurves(ctx: CanvasRenderingContext2D, curves: RoughCurve[],
                             lineWidth: number, color: string, alpha: number): void {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.strokeStyle = color;
  ctx.lineWidth = lineWidth;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  ctx.beginPath();
  for (let i = 0; i < curves.length; i++) {
    const c: RoughCurve = curves[i];
    ctx.moveTo(c.x1, c.y1);
    ctx.bezierCurveTo(c.cx1, c.cy1, c.cx2, c.cy2, c.x2, c.y2);
  }
  ctx.stroke();
  ctx.restore();
}

/**
 * 抖动的矩形框：一遍定形，一遍余墨。
 *
 * @param seed   同一枚章必须传同一个值（用 hashText(印章文字)），否则每次重绘都变
 * @param offset 第一遍的端点峰值偏移（vp）。小章 1.0 左右，大章按比例放大
 */
export function roughRect(ctx: CanvasRenderingContext2D, x: number, y: number,
                          w: number, h: number, seed: number, offset: number,
                          lineWidth: number, color: string): void {
  const pen: RoughPen = new RoughPen(seed);
  const base: RoughCurve[] = pen.rect(x, y, w, h, offset, BOWING);
  strokeCurves(ctx, base, lineWidth, color, 1.0);

  const ghostPen: RoughPen = new RoughPen(seed + PASS_SEED_STEP);
  strokeCurves(ctx, ghostPen.ghost(base, offset * GHOST_RATIO),
               lineWidth * 0.85, color, SECOND_PASS_ALPHA);
}

/**
 * 抖动的横线：同一套「一遍定形 + 一遍余墨」。
 * 账本的主分隔线暂时不用（风险高、容易变脏），留给需要的地方。
 */
export function roughLine(ctx: CanvasRenderingContext2D, x1: number, y1: number,
                          x2: number, y2: number, seed: number, offset: number,
                          lineWidth: number, color: string): void {
  const pen: RoughPen = new RoughPen(seed);
  const base: RoughCurve[] = [pen.edge(x1, y1, x2, y2, offset, BOWING)];
  strokeCurves(ctx, base, lineWidth, color, 1.0);

  const ghostPen: RoughPen = new RoughPen(seed + PASS_SEED_STEP);
  strokeCurves(ctx, ghostPen.ghost(base, offset * GHOST_RATIO),
               lineWidth * 0.85, color, SECOND_PASS_ALPHA);
}
