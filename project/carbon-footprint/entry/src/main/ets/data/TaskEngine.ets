/**
 * 智能服务引擎 —— 创新拓展 4
 *
 * 赛题原文：「智能服务：个性化低碳任务推送、生活建议、减排成果社交分享功能。」
 *
 * 本模块负责前两项（任务推送、生活建议），分享在 view/ShareCard.ets。
 *
 * 设计要点：
 *   · 纯函数实现，不依赖 KV、不依赖 UI —— 输入行为记录，输出任务与建议，
 *     因此可以单独测试，也方便答辩时讲清「推荐逻辑是什么」。
 *   · 推荐逻辑刻意做成可解释的规则，而不是黑盒：每一句建议都能对应到
 *     用户数据里的一个具体事实。答辩被问「你的智能体现在哪」时，
 *     能指着代码说清楚，比说「用了 AI」更有说服力。
 */
import { BehaviorRecord, Category, categoryLabel, formatDate } from '../model/Models';

/** 一条个性化低碳任务 */
export interface DailyTask {
  id: string;
  category: string;
  title: string;
  hint: string;
  /** 今天是否已完成（按类目判断） */
  done: boolean;
  /** 完成后可得积分（与减排量挂钩，这里是提示性数值） */
  points: number;
}

/** 每个类目推荐的具体行为，用于生成任务文案 */
const SUGGESTIONS: Map<string, string> = new Map<string, string>([
  [Category.TRAVEL, '步行 / 骑行 / 公交地铁出行'],
  [Category.ENERGY, '随手关灯、空调调高 1℃、缩短淋浴时间'],
  [Category.RECYCLE, '旧纸箱、塑料瓶、旧衣物分类回收'],
  [Category.FOOD, '按需点餐、剩菜打包、光盘行动']
]);

/** 类目 → 基础积分提示 */
const BASE_POINTS: Map<string, number> = new Map<string, number>([
  [Category.TRAVEL, 20],
  [Category.ENERGY, 15],
  [Category.RECYCLE, 25],
  [Category.FOOD, 10]
]);

function countBy(records: BehaviorRecord[], category: string): number {
  let n: number = 0;
  for (let i = 0; i < records.length; i++) {
    if (records[i].category === category) {
      n++;
    }
  }
  return n;
}

function recordedToday(records: BehaviorRecord[], category: string, todayStr: string): boolean {
  for (let i = 0; i < records.length; i++) {
    if (records[i].category === category && records[i].date === todayStr) {
      return true;
    }
  }
  return false;
}

/** 取最近 n 天的记录 */
function recent(records: BehaviorRecord[], days: number): BehaviorRecord[] {
  const from: Date = new Date();
  from.setDate(from.getDate() - (days - 1));
  const fromStr: string = formatDate(from);
  const out: BehaviorRecord[] = [];
  for (let i = 0; i < records.length; i++) {
    if (records[i].date >= fromStr) {
      out.push(records[i]);
    }
  }
  return out;
}

/**
 * 生成今日个性化任务。
 *
 * 推荐规则（可解释）：
 *   1. 先挑「今天还没记录过」的类目；
 *   2. 同类目之间，按历史记录条数**从少到多**排序 —— 也就是优先补短板；
 *   3. 凑不满 3 条时，用剩余类目补齐，标记为「保持」。
 * 这样新用户拿到的是覆盖面，老用户拿到的是短板补齐。
 */
export function buildDailyTasks(records: BehaviorRecord[], todayStr: string): DailyTask[] {
  const cats: string[] = [Category.TRAVEL, Category.ENERGY, Category.RECYCLE, Category.FOOD];

  // 未完成的排前面；同类目按历史条数升序（短板优先）
  const pending: string[] = [];
  const finished: string[] = [];
  for (let i = 0; i < cats.length; i++) {
    if (recordedToday(records, cats[i], todayStr)) {
      finished.push(cats[i]);
    } else {
      pending.push(cats[i]);
    }
  }
  pending.sort((a: string, b: string): number => countBy(records, a) - countBy(records, b));

  const picked: string[] = [];
  for (let i = 0; i < pending.length && picked.length < 3; i++) {
    picked.push(pending[i]);
  }
  for (let i = 0; i < finished.length && picked.length < 3; i++) {
    picked.push(finished[i]);
  }

  const tasks: DailyTask[] = [];
  for (let i = 0; i < picked.length; i++) {
    const c: string = picked[i];
    const done: boolean = recordedToday(records, c, todayStr);
    const sug: string | undefined = SUGGESTIONS.get(c);
    const pts: number | undefined = BASE_POINTS.get(c);
    const task: DailyTask = {
      id: `task.${todayStr}.${c}`,
      category: c,
      title: `${done ? '继续保持' : '今天试试'}：${categoryLabel(c)}`,
      hint: sug === undefined ? '' : sug,
      done: done,
      points: pts === undefined ? 10 : pts
    };
    tasks.push(task);
  }
  return tasks;
}

/**
 * 生成个性化生活建议。
 *
 * 每条建议都对应一个具体的数据事实，可解释、可追溯。
 */
export function buildAdvice(records: BehaviorRecord[]): string[] {
  const out: string[] = [];
  const week: BehaviorRecord[] = recent(records, 7);
  const prevFrom: Date = new Date();
  prevFrom.setDate(prevFrom.getDate() - 13);
  const prevTo: Date = new Date();
  prevTo.setDate(prevTo.getDate() - 7);
  const prevFromStr: string = formatDate(prevFrom);
  const prevToStr: string = formatDate(prevTo);
  let prevSum: number = 0;
  for (let i = 0; i < records.length; i++) {
    if (records[i].date >= prevFromStr && records[i].date <= prevToStr) {
      prevSum += records[i].saved;
    }
  }

  if (records.length === 0) {
    out.push('还没有任何记录。先记一笔最简单的——比如今天走了多少公里——就能看到你的减排曲线。');
    return out;
  }

  // 1) 趋势对比
  let weekSum: number = 0;
  for (let i = 0; i < week.length; i++) {
    weekSum += week[i].saved;
  }
  if (prevSum > 0) {
    const diff: number = weekSum - prevSum;
    if (diff > 0.01) {
      out.push(`本周比上周多减排 ${Math.round(diff * 100) / 100} kg CO₂e，保持这个节奏。`);
    } else if (diff < -0.01) {
      out.push(`本周比上周少减排 ${Math.round(-diff * 100) / 100} kg CO₂e，可以回顾一下是哪类行为少了。`);
    } else {
      out.push('本周与上周减排量基本持平。');
    }
  } else {
    out.push(`本周已减排 ${Math.round(weekSum * 100) / 100} kg CO₂e，继续记录就能看到周对比。`);
  }

  // 2) 短板提醒
  let weakest: string = Category.TRAVEL;
  let weakestN: number = Number.MAX_SAFE_INTEGER;
  const cats: string[] = [Category.TRAVEL, Category.ENERGY, Category.RECYCLE, Category.FOOD];
  for (let i = 0; i < cats.length; i++) {
    const n: number = countBy(records, cats[i]);
    if (n < weakestN) {
      weakestN = n;
      weakest = cats[i];
    }
  }
  if (weakestN === 0) {
    out.push(`你还没有记录过「${categoryLabel(weakest)}」类的行为，这可能是被忽略的减排空间。`);
  }

  // 3) 停留提醒
  const lastDate: string = records[0].date;
  const todayStr: string = formatDate(new Date());
  if (lastDate < todayStr) {
    const d1: Date = new Date(`${lastDate}T00:00:00`);
    const d2: Date = new Date(`${todayStr}T00:00:00`);
    const gapDays: number = Math.round((d2.getTime() - d1.getTime()) / 86400000);
    if (gapDays >= 2) {
      out.push(`距离上次记录已经 ${gapDays} 天，补记一下也能算进累计减排。`);
    }
  }

  // 4) 用电类小贴士（数据驱动：只在用户确实记录过用电时出现）
  if (countBy(records, Category.ENERGY) > 0) {
    out.push('空调每调高 1℃ 约省电 7%，按全国电网平均排放因子折算，一个夏天能省下可观的碳。');
  }

  return out;
}

/** 汇总一句话结论，用于分享图 */
export function summaryLine(records: BehaviorRecord[]): string {
  let total: number = 0;
  for (let i = 0; i < records.length; i++) {
    total += records[i].saved;
  }
  const t: number = Math.round(total * 100) / 100;
  if (t <= 0) {
    return '开启我的低碳生活';
  }
  return `我已累计减排 ${t} kg CO₂e`;
}
