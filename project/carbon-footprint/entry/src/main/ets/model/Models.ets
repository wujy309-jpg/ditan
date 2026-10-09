/**
 * 领域模型 —— 碳迹
 *
 * 三个核心概念：
 *   Factor          内置碳排放因子（静态数据，见 data/FactorLibrary.ets）
 *   BehaviorRecord  一条低碳行为记录（用户产生，跨设备同步）
 *   PointsEntry     一条积分流水（只增不改，天然免冲突）
 */

/** 低碳行为类目 */
export enum Category {
  TRAVEL = 'travel',
  ENERGY = 'energy',
  RECYCLE = 'recycle',
  FOOD = 'food'
}

/** 全部类目，供选择器使用 */
export const ALL_CATEGORIES: string[] = [
  Category.TRAVEL,
  Category.ENERGY,
  Category.RECYCLE,
  Category.FOOD
];

/** 类目 → 中文名 */
export function categoryLabel(category: string): string {
  if (category === Category.TRAVEL) {
    return '出行';
  }
  if (category === Category.ENERGY) {
    return '节水节电';
  }
  if (category === Category.RECYCLE) {
    return '旧物回收';
  }
  if (category === Category.FOOD) {
    return '光盘行动';
  }
  return '其他';
}

/** 内置碳排放因子 */
export interface Factor {
  /** 唯一标识，如 'travel.metro' */
  id: string;
  /** 所属类目，取 Category 的值 */
  category: string;
  /** 展示名，如「地铁出行」 */
  name: string;
  /** 计量单位：公里 / 度 / 立方米 / 公斤 / 餐次 */
  unit: string;
  /**
   * 每单位活动的**减排量**，kg CO₂e / 单位。
   * 恒为正数，含义是「相比基准情景少排了多少」。
   */
  savedPerUnit: number;
  /** 减排量相对的基准情景（答辩必问，务必写清） */
  baseline: string;
  /** 数据出处 */
  source: string;
}

/** 一条低碳行为记录 */
export interface BehaviorRecord {
  id: string;
  category: string;
  factorId: string;
  /** 因子名快照——避免因子库调整后历史记录显示错乱 */
  name: string;
  amount: number;
  unit: string;
  /** 减排量 kg CO₂e = amount × factor.savedPerUnit */
  saved: number;
  /** 行为发生日期，YYYY-MM-DD */
  date: string;
  /** 录入时间戳（毫秒） */
  ts: number;
}

/** 一条积分流水 */
export interface PointsEntry {
  id: string;
  /** 正数为获得，负数为消耗 */
  delta: number;
  reason: string;
  ts: number;
  /** 本笔之后的余额，便于对账 */
  balanceAfter: number;
}

/** 用户档案 */
export interface Profile {
  nickname: string;
  /** 家庭 ID：创新点 1「家庭碳积分合并统计」的分组键 */
  familyId: string;
  createdAt: number;
}

/** 生成默认档案 */
export function defaultProfile(): Profile {
  const p: Profile = {
    nickname: '低碳生活家',
    familyId: 'default',
    createdAt: Date.now()
  };
  return p;
}

/**
 * 生成唯一 ID。
 *
 * 为什么不能只用「时间戳 + 随机数」：
 *   同一毫秒内连续生成时 Date.now() 不变，唯一性完全依赖随机数；
 *   随机数取值 10 万时，500 次生成按生日悖论就会撞 1–3 次（实测撞了 3 次）。
 *   加一个进程内单调递增的序号后，同毫秒内也不可能重复。
 */
let idSeq: number = 0;

export function newId(): string {
  idSeq = (idSeq + 1) % 1000000;
  const rand: number = Math.floor(Math.random() * 1000000);
  return `${Date.now()}-${idSeq}-${rand}`;
}

/** Date → YYYY-MM-DD */
export function formatDate(d: Date): string {
  const y: number = d.getFullYear();
  const m: number = d.getMonth() + 1;
  const day: number = d.getDate();
  const mm: string = m < 10 ? `0${m}` : `${m}`;
  const dd: string = day < 10 ? `0${day}` : `${day}`;
  return `${y}-${mm}-${dd}`;
}

/** 今天，YYYY-MM-DD */
export function today(): string {
  return formatDate(new Date());
}

/** 减排量保留 2 位小数（避免浮点误差在界面上显示成 0.30000000000000004） */
export function round2(v: number): number {
  return Math.round(v * 100) / 100;
}
