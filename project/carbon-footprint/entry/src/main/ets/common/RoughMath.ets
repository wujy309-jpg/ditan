/**
 * 手绘抖动的**纯几何**部分 —— 「两遍墨」的地基
 *
 * ── 为什么整页需要这一点不完美 ────────────────────────────────────────────
 * v3 把界面做「对」了：细线、纸、墨、宋体。但它太干净了 —— 印章是完美矩形，
 * 横线是完美 1px。真实印刷品和真实盖出来的章，边缘一定有抖动：油墨在纸纤维上
 * 洇开、压印压力不匀、两遍走笔不会重合。这一点点不完美，是「人做的」和
 * 「生成的」之间最后的距离。
 *
 * 算法来自 rough.js（MIT，rough-stuff/rough）的 `roughLine`：
 *   一条边不是直连线，而是一条**两端各随机偏移、中段带一点弯曲的贝塞尔曲线**；
 *   同一个形画**两遍**，两遍的随机序列不同，叠在一起就有了「两遍墨」的浓淡。
 *
 * ── 为什么这个文件单独存在（不直接写在 view/Rough.ets）─────────────────
 * 因为「确定性」是本功能的验收红线：**同一枚章每次画出来必须一模一样**。
 * 把随机和几何放在一个不 import 任何 ArkUI 类型、纯 TypeScript 可编译的模块里，
 * 就能用 `tools/test-logic.sh` 在 Node 上直接断言：
 *   同 seed 同序号 → 同值；不同 seed → 不同形；峰值偏移不超出声明幅度。
 * 画的部分（Rough.ets）只剩「把数组里的数交给 ctx」，没有逻辑可出错。
 *
 * ── 不用 Math.random 的理由 ──────────────────────────────────────────────
 * 不是洁癖。`Math.random()` 会让同一枚章在每次重绘、每次进页面、每次截屏时
 * 长得都不一样；分享图会跟屏幕上看到的不一致；回归截图也没有可比性。
 * 这里用 (seed, n) 的纯函数，seed 来自印章文字，n 是画到第几个数。
 */

// ---------------------------------------------------------------------------
// 确定性伪随机
// ---------------------------------------------------------------------------

/** xorshift32：只做 32 位整数运算，任何 JS/ArkTS 引擎结果都精确一致 */
function mix32(x: number): number {
  let v: number = x | 0;
  v = (v ^ (v << 13)) | 0;
  v = (v ^ (v >>> 17)) | 0;
  v = (v ^ (v << 5)) | 0;
  return v;
}

/**
 * 第 n 个确定性伪随机数，落在 [0, 1)。
 *
 * `n * 0x9E3779B1`（黄金分割步进）让相邻 n 彼此远离，避免连续取数时
 * 出现「一条边抖、下一条边跟着抖」的规律感；随后 xorshift32 打散。
 */
export function seeded(seed: number, n: number): number {
  const step: number = (n * 0x9E3779B1) | 0;
  return (mix32((step ^ (seed | 0)) | 0) >>> 0) / 4294967296;
}

/**
 * 字符串 → 32 位种子（FNV 变体，乘法因子换成 31 以始终留在 2^53 精确区间内）。
 * 印章的 seed 用它算：同一句话的章每次都是同一种抖动，不同文字的章抖动不同。
 */
export function hashText(t: string): number {
  let h: number = 0x811C9DC5 | 0;
  for (let i = 0; i < t.length; i++) {
    h = ((h * 31) + t.charCodeAt(i)) | 0;
  }
  return h;
}

// ---------------------------------------------------------------------------
// 一条抖动的边
// ---------------------------------------------------------------------------

/**
 * 一条边画出来的形状：一次 moveTo + 一次 bezierCurveTo。
 * 字段用平铺的 8 个 number 而不是嵌套对象 —— ArkTS 严格模式下嵌套匿名对象
 * 需要额外声明类型，平铺最省事，也方便单测逐个比对。
 */
export class RoughCurve {
  x1: number = 0;
  y1: number = 0;
  cx1: number = 0;
  cy1: number = 0;
  cx2: number = 0;
  cy2: number = 0;
  x2: number = 0;
  y2: number = 0;
}

/**
 * 一支「笔」：持有一个种子和取数进度，按顺序吐出抖动的边。
 *
 * 一个形画两遍 = 两支笔（seed 不同），而不是同一支笔连着取 16 个数 ——
 * 后者两遍的偏移会呈同分布，但「两遍几乎重合」的概率更高，看着像描粗了。
 */
export class RoughPen {
  private seedVal: number = 0;
  private stepNo: number = 0;

  constructor(seed: number) {
    this.seedVal = seed | 0;
  }

  next(): number {
    this.stepNo = this.stepNo + 1;
    return seeded(this.seedVal, this.stepNo);
  }

  /** 在 ±amp 之间取一个偏移 */
  private jitter(amp: number): number {
    return (this.next() * 2 - 1) * amp;
  }

  /**
   * 一条边。
   *
   * @param offset 端点峰值偏移（vp）。这是「笔抖得有多厉害」，不是线宽。
   * @param bowing 中段弯曲强度，相对 offset 的无量纲倍数；
   *               0 = 中段不弯，0.6 大约产生 0.45×offset 的实际弓高。
   *
   * ── 为什么每条边是「平移 + 一点点倾斜」而不是两端各抖各的 ────────────────
   * 这一条是反复试出来的，两个坑各踩了一次：
   *
   * 一稿：端点 x、y 各自独立抖 —— 每个拐角拖出一根 45° 的小尾巴。因为相邻两
   *       条边在同一个角上各跑一次，一条缩短、一条伸出，伸出的那截就成了「钩」。
   * 二稿：只往法线方向抖、切线方向留 40% —— 尾巴没了，但**整条边会歪**：两端
   *       各自 ±offset，一条 33vp 的边就有了 2° 以上的倾角。放大看不像「墨压
   *       出来的边」，像「画歪了的方框」。
   *
   * 现在的做法：一条边先整体平移（translate），再让两端反向偏一个很小的 tilt。
   *   · 平移 → 相邻边在拐角处自然错开，这是「手刻」的来源，保留；
   *   · 倾斜上限压到 offset×0.3 → 边是「直的，只是位置略偏」，不再像画歪。
   * 一笔刻出来的边本来就是直的：变的是位置、宽度和墨的浓淡，不是走向。
   */
  edge(x1: number, y1: number, x2: number, y2: number,
       offset: number, bowing: number): RoughCurve {
    const dx: number = x2 - x1;
    const dy: number = y2 - y1;
    const len: number = Math.sqrt(dx * dx + dy * dy);
    // 单位切线与法线（法线由切线逆时针转 90° 得到）
    const tx: number = len > 0.0001 ? dx / len : 1;
    const ty: number = len > 0.0001 ? dy / len : 0;
    const nx: number = -ty;
    const ny: number = tx;

    const shift: number = this.jitter(offset);            // 整条边的平移
    const tilt: number = this.jitter(offset * 0.3);       // 两端反向：只允许微斜
    const bow: number = bowing * offset * this.jitter(1.0); // 中段弓（两控制点同侧）
    const ctrl: number = offset * 0.2;                     // 控制点的局部抖
    // 拐点位置左右各留一段随机：余墨的分歧主要来自这里
    const d1: number = 0.18 + this.next() * 0.22;
    const d2: number = 1 - d1;

    const n1: number = shift + tilt;
    const n2: number = shift - tilt;

    const c: RoughCurve = new RoughCurve();
    c.x1 = x1 + nx * n1 + tx * this.jitter(offset * 0.25);
    c.y1 = y1 + ny * n1 + ty * this.jitter(offset * 0.25);
    c.cx1 = x1 + dx * d1 + nx * (shift + bow + this.jitter(ctrl));
    c.cy1 = y1 + dy * d1 + ny * (shift + bow + this.jitter(ctrl));
    c.cx2 = x1 + dx * d2 + nx * (shift + bow + this.jitter(ctrl));
    c.cy2 = y1 + dy * d2 + ny * (shift + bow + this.jitter(ctrl));
    c.x2 = x2 + nx * n2 + tx * this.jitter(offset * 0.25);
    c.y2 = y2 + ny * n2 + ty * this.jitter(offset * 0.25);
    return c;
  }

  /** 矩形的一遍：上 → 右 → 下 → 左，四条边各自独立抖，拐角天然错开 */
  rect(x: number, y: number, w: number, h: number,
       offset: number, bowing: number): RoughCurve[] {
    const out: RoughCurve[] = [];
    out.push(this.edge(x, y, x + w, y, offset, bowing));
    out.push(this.edge(x + w, y, x + w, y + h, offset, bowing));
    out.push(this.edge(x + w, y + h, x, y + h, offset, bowing));
    out.push(this.edge(x, y + h, x, y, offset, bowing));
    return out;
  }

  /**
   * 第一遍的「余墨」：把已经算好的形，每个点抖一点点。
   *
   * 这是本功能和 rough.js 原版最大的分歧点。rough.js 两遍各自独立抖动，
   * 一遍偏移 +1vp、另一遍 −1vp，两条线能差 2vp —— 印在 3px/vp 的屏上就是
   * 两条分得开的线，观感像「拍照时手抖了」，不像「墨压了两遍」。
   *
   * 真实的第二遍是**同一笔的余墨**：形状跟着第一遍走，只是边缘洇出去一点、
   * 某些段浅一些。所以这里不从零重算，而在第一遍的形上做一次小位移。
   * 结果是一道深浅不匀的边缘，而不是两根线。
   */
  ghost(curves: RoughCurve[], amp: number): RoughCurve[] {
    const out: RoughCurve[] = [];
    for (let i = 0; i < curves.length; i++) {
      const src: RoughCurve = curves[i];
      const c: RoughCurve = new RoughCurve();
      c.x1 = src.x1 + this.jitter(amp);
      c.y1 = src.y1 + this.jitter(amp);
      c.cx1 = src.cx1 + this.jitter(amp);
      c.cy1 = src.cy1 + this.jitter(amp);
      c.cx2 = src.cx2 + this.jitter(amp);
      c.cy2 = src.cy2 + this.jitter(amp);
      c.x2 = src.x2 + this.jitter(amp);
      c.y2 = src.y2 + this.jitter(amp);
      out.push(c);
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// 单测用：把一遍矩形的 32 个数摊平，方便整体比对
// ---------------------------------------------------------------------------

export function flatten(curves: RoughCurve[]): number[] {
  const out: number[] = [];
  for (let i = 0; i < curves.length; i++) {
    const c: RoughCurve = curves[i];
    out.push(c.x1, c.y1, c.cx1, c.cy1, c.cx2, c.cy2, c.x2, c.y2);
  }
  return out;
}

/**
 * 一遍矩形里，任何一个控制点/端点**相对它自己那条边**偏离了多少（vp）。
 * 用来断言「抖得够，但不脏」的验收线（≤ 1.5vp）。
 *
 * ⚠️ 这里踩过一次坑：最早写的是「到四条边取最小距离」。在拐角附近，
 * 一个点离**相邻**那条边的距离会小于离自己那条边的距离，于是测出来的
 * 永远是切线方向那点小抖动，法线方向真正的大偏移被整个漏掉 ——
 * 验收线形同虚设。所以必须按下标认边：rect() 的推入顺序是 上→右→下→左。
 */
export function peakDeviation(curves: RoughCurve[], x: number, y: number,
                              w: number, h: number): number {
  let peak: number = 0;
  for (let i = 0; i < curves.length && i < 4; i++) {
    const c: RoughCurve = curves[i];
    const xs: number[] = [c.x1, c.cx1, c.cx2, c.x2];
    const ys: number[] = [c.y1, c.cy1, c.cy2, c.y2];
    for (let k: number = 0; k < 4; k++) {
      let d: number = 0;
      if (i === 0) {
        d = Math.abs(ys[k] - y);
      } else if (i === 1) {
        d = Math.abs(xs[k] - (x + w));
      } else if (i === 2) {
        d = Math.abs(ys[k] - (y + h));
      } else {
        d = Math.abs(xs[k] - x);
      }
      if (d > peak) {
        peak = d;
      }
    }
  }
  return peak;
}
