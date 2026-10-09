/**
 * 纯逻辑单元测试 —— 碳迹
 *
 * 为什么需要这个：应用要跑在鸿蒙设备/模拟器上才能验证 UI，
 * 但「减排量算得对不对」「任务推荐逻辑对不对」这类**纯计算逻辑**
 * 可以不依赖设备就测出来。这一步能在没有真机的情况下提前发现逻辑错误。
 *
 * 覆盖范围：
 *   · 因子库的算术自洽性（减排量 = 基准 − 实际）
 *   · 任务推荐引擎（短板优先、已完成标记、配额补齐）
 *   · 生活建议引擎（空数据、趋势对比、短板提醒）
 *   · 通用工具函数（round2 / formatDate / newId）
 *
 * 运行：tools/test-logic.sh
 */
import { BehaviorRecord, Category, formatDate, newId, round2, today } from './model/Models';
import { FACTORS, factorById, factorsOf } from './data/FactorLibrary';
import { buildAdvice, buildDailyTasks, DailyTask, summaryLine } from './data/TaskEngine';

/** 测试跑在 Node 上，但没有装 @types/node，这里手动声明用到的成员 */
declare const process: { exit(code: number): void };

let passed: number = 0;
let failed: number = 0;

function ok(name: string, cond: boolean, detail?: string): void {
  if (cond) {
    passed++;
    console.log(`  \u2713 ${name}`);
  } else {
    failed++;
    console.log(`  \u2717 ${name}${detail ? '  → ' + detail : ''}`);
  }
}

function eq(name: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  ok(name, a === e, `实际=${a} 期望=${e}`);
}

function near(name: string, actual: number, expected: number, tol: number): void {
  ok(name, Math.abs(actual - expected) <= tol, `实际=${actual} 期望=${expected}±${tol}`);
}

/** 构造一条行为记录 */
function rec(category: string, date: string, saved: number, ts: number): BehaviorRecord {
  return {
    id: `r${ts}`,
    category,
    factorId: 'x',
    name: '测试',
    amount: 1,
    unit: '次',
    saved,
    date,
    ts
  };
}

function dayOffset(n: number): string {
  const d: Date = new Date();
  d.setDate(d.getDate() + n);
  return formatDate(d);
}

// ===========================================================================
console.log('\n【1】因子库算术自洽性');

// 出行类：减排量必须等于 基准(燃油小汽车) − 该行为排放量
const CAR: number = 0.19567;
near('步行减排 = 基准 − 0', factorById('travel.walk')!.savedPerUnit, CAR, 1e-6);
near('骑行减排 = 基准 − 0', factorById('travel.bike')!.savedPerUnit, CAR, 1e-6);
// 地铁 0.04314、公交 0.053、新能源车 0.17（CPCD 2023）
near('地铁减排 = 0.19567 − 0.04314', factorById('travel.metro')!.savedPerUnit, CAR - 0.04314, 1e-6);
near('公交减排 = 0.19567 − 0.053', factorById('travel.bus')!.savedPerUnit, CAR - 0.053, 1e-6);
near('新能源车减排 = 0.19567 − 0.17', factorById('travel.nev')!.savedPerUnit, CAR - 0.17, 1e-6);

// 所有因子必须为正（负减排量没有业务含义）
let allPositive: boolean = true;
let allHaveSource: boolean = true;
for (let i = 0; i < FACTORS.length; i++) {
  if (!(FACTORS[i].savedPerUnit > 0)) {
    allPositive = false;
  }
  if (FACTORS[i].source.length < 8 || FACTORS[i].baseline.length < 4) {
    allHaveSource = false;
  }
}
ok('全部因子的减排量为正数', allPositive);
ok('全部因子都有出处与基准情景说明', allHaveSource);
ok(`因子总数 = ${FACTORS.length}（覆盖 4 个类目）`, FACTORS.length >= 13);

// 类目覆盖
const catCount: number[] = [
  factorsOf(Category.TRAVEL).length,
  factorsOf(Category.ENERGY).length,
  factorsOf(Category.RECYCLE).length,
  factorsOf(Category.FOOD).length
];
ok('四个类目都有因子', catCount[0] > 0 && catCount[1] > 0 && catCount[2] > 0 && catCount[3] > 0);
ok('factorById 对不存在的 id 返回 undefined', factorById('nope.nope') === undefined);

// 节电因子应等于河南电网因子
near('节约用电因子 = 河南电网 0.5897', factorById('energy.power')!.savedPerUnit, 0.5897, 1e-6);
// 节水 = 供水 + 污水处理
near('节水因子 = 0.1913 + 0.17088', factorById('energy.water')!.savedPerUnit, 0.1913 + 0.17088, 1e-6);

// ===========================================================================
console.log('\n【2】工具函数');

eq('round2 消除浮点噪声 0.1*3', round2(0.1 * 3), 0.3);
eq('round2(2) = 2', round2(2), 2);
// 契约：结果至多两位小数（1.005 这类二进制浮点边界值本就略小于 1.005，不做断言）
const rSamples: number[] = [3 * 0.19567, 7.5 * 0.5897, 12.345 * 0.36218, 1.005, 99.999];
// 用字符串表示来判断小数位数，避免再用浮点比较引入新的误差
function decimalsOf(v: number): number {
  const str: string = round2(v).toString();
  const dot: number = str.indexOf('.');
  return dot === -1 ? 0 : str.length - dot - 1;
}
ok('round2 结果至多两位小数',
  rSamples.every((v: number) => decimalsOf(v) <= 2),
  rSamples.map((v: number) => `${v}->${round2(v)}`).join(', '));
ok('today() 形如 YYYY-MM-DD', /^\d{4}-\d{2}-\d{2}$/.test(today()));
const ids: Set<string> = new Set<string>();
for (let i = 0; i < 500; i++) {
  ids.add(newId());
}
eq('newId() 500 次无重复', ids.size, 500);
eq('formatDate 补零', formatDate(new Date(2026, 0, 5)), '2026-01-05');

// ===========================================================================
console.log('\n【3】任务推荐引擎');

const T: string = today();

// 3.1 全新用户：应给出 3 个任务，且都未完成
const t1: DailyTask[] = buildDailyTasks([], T);
eq('新用户任务数 = 3', t1.length, 3);
ok('新用户任务全部未完成', t1[0].done === false && t1[1].done === false && t1[2].done === false);
ok('新用户任务覆盖出行（短板优先，历史为空时按类目顺序）', t1[0].category === Category.TRAVEL);
ok('每个任务都有提示文案', t1.every((x: DailyTask) => x.hint.length > 0));
ok('每个任务积分提示为正', t1.every((x: DailyTask) => x.points > 0));

// 3.2 今天已记录出行：出行应判为已完成
const withTravel: BehaviorRecord[] = [rec(Category.TRAVEL, T, 2.0, Date.now())];
const t2: DailyTask[] = buildDailyTasks(withTravel, T);
const travelTask: DailyTask | undefined = t2.find((x: DailyTask) => x.category === Category.TRAVEL);
ok('今天记过出行 → 出行任务不出现在待办里（已有 3 个待办类目）', travelTask === undefined);
ok('其余任务仍未完成', t2.filter((x: DailyTask) => x.done).length === 0);

// 3.3 今天记录了两类：只剩 2 个待办，需要从已完成类目补齐到 3 条
const twoToday: BehaviorRecord[] = [
  rec(Category.TRAVEL, T, 2.0, Date.now()),
  rec(Category.ENERGY, T, 1.0, Date.now() + 1)
];
const t3: DailyTask[] = buildDailyTasks(twoToday, T);
eq('补足到 3 条任务', t3.length, 3);
// 今天已记录 2 类 → 剩余 2 个待办占满名额，再用 1 个已完成类目补齐到 3 条
eq('其中已完成 1 条（配额 3 条，2 条待办 + 1 条已完成）',
  t3.filter((x: DailyTask) => x.done).length, 1);
ok('已完成的排在未完成之后', t3[2].done === true);

// 3.4 短板优先：能源类记录很多、回收类没有 → 回收类应排在能源类之前
const skewed: BehaviorRecord[] = [];
for (let i = 0; i < 10; i++) {
  skewed.push(rec(Category.ENERGY, dayOffset(-i - 1), 1.0, Date.now() - i * 1000));
}
const t4: DailyTask[] = buildDailyTasks(skewed, T);
const idxRecycle: number = t4.findIndex((x: DailyTask) => x.category === Category.RECYCLE);
const idxEnergy: number = t4.findIndex((x: DailyTask) => x.category === Category.ENERGY);
ok('短板类目（回收，0 条）出现在任务里', idxRecycle >= 0, `回收 idx=${idxRecycle}`);
// 能源类已有 10 条记录，不属于短板；3 条配额被 3 个 0 记录类目占满，它应被挤出
ok('长板类目（能源，10 条）被挤出任务列表', idxEnergy === -1, `能源 idx=${idxEnergy}`);
// 出行与回收同为 0 条记录属并列短板，稳定排序下按类目原序排列，只要求进入前 3
ok('短板类目进入任务配额（前三）', idxRecycle >= 0 && idxRecycle <= 2, `回收 idx=${idxRecycle}`);

// ===========================================================================
console.log('\n【4】生活建议引擎');

const a0: string[] = buildAdvice([]);
eq('无数据时只给一条引导', a0.length, 1);
ok('无数据时的引导文案正确', a0[0].includes('还没有任何记录'));

const a1: string[] = buildAdvice([rec(Category.TRAVEL, T, 3.0, Date.now())]);
ok('有数据时至少给一条建议', a1.length >= 1);
ok('有数据时不再出现空数据引导', !a1[0].includes('还没有任何记录'));

// 趋势对比：本周多、上周少 → 应提示「多减排」
const trendUp: BehaviorRecord[] = [
  rec(Category.TRAVEL, dayOffset(-1), 10.0, Date.now()),
  rec(Category.TRAVEL, dayOffset(-9), 1.0, Date.now() - 1)
];
const aUp: string[] = buildAdvice(trendUp);
ok('本周优于上周时提示「多减排」', aUp.some((s: string) => s.includes('多减排')));

const trendDown: BehaviorRecord[] = [
  rec(Category.TRAVEL, dayOffset(-1), 1.0, Date.now()),
  rec(Category.TRAVEL, dayOffset(-9), 10.0, Date.now() - 1)
];
const aDown: string[] = buildAdvice(trendDown);
ok('本周差于上周时提示「少减排」', aDown.some((s: string) => s.includes('少减排')));

// 短板提醒：只记了出行 → 应提醒其他未记录的类目
const aWeak: string[] = buildAdvice([rec(Category.TRAVEL, T, 3.0, Date.now())]);
ok('提示从未记录过的类目', aWeak.some((s: string) => s.includes('还没有记录过')));

// ===========================================================================
console.log('\n【5】分享文案');

eq('无数据时的分享文案', summaryLine([]), '开启我的低碳生活');
ok('有数据时分享文案含减排量', summaryLine([rec(Category.TRAVEL, T, 12.34, Date.now())])
  .includes('12.34'));

// ===========================================================================
console.log(`\n${'='.repeat(52)}`);
console.log(`测试结果：通过 ${passed} 项，失败 ${failed} 项`);
console.log('='.repeat(52));
if (failed > 0) {
  process.exit(1);
}
