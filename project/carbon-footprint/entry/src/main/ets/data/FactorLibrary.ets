/**
 * 内置碳排放因子库 —— 碳迹
 *
 * ===========================================================================
 * 折算公式
 * ===========================================================================
 *   ER = AD × (EF_baseline − EF_activity)
 *
 *   ER          减排量（kg CO₂e）—— 本库 savedPerUnit 字段的含义
 *   AD          活动量（公里 / 度 / 立方米 / 公斤 / 餐次）
 *   EF_baseline 基准情景排放因子（高碳行为）
 *   EF_activity 实际行为排放因子（低碳行为）
 *
 *   本库所有 savedPerUnit 都已经是 (EF_baseline − EF_activity) 的差值，
 *   即**减排量**而非排放量。每条因子的 baseline 字段写明了基准情景。
 *
 * ===========================================================================
 * 数据来源总览（答辩时按这个顺序讲）
 * ===========================================================================
 *  ① CPCD — 中国产品全生命周期温室气体排放系数库（中国本土，主来源）
 *     https://lca.cityghg.com ｜ 出行类与回收 PET 用这个
 *
 *  ② 生态环境部、国家统计局《关于发布 2023 年电力二氧化碳排放因子的公告》
 *     公告 2025 年第 47 号，2025-12-31 发布 ｜ 节电类用这个
 *     同一公告内有 5 个口径，数值差异最大 56%，本库固定用「表 3 省级」的河南省值
 *
 *  ③ DEFRA（英国环境、食品和农村事务部）2025 年温室气体换算因子
 *     用于中国官方未发布对应因子的条目：回收废纸 / 铝 / 旧衣物、供水与污水处理
 *     ⚠️ 这几条是**英国口径**，应用中已逐条标注，答辩时必须主动说明
 *
 *  ④ 中国科学院地理科学与资源研究所 + WWF《中国城市餐饮食物浪费报告》（2018）
 *     + FAO《Food Wastage Footprint》(2013) 折算 ｜ 光盘行动用这个
 *
 * ===========================================================================
 * 三个必须知道的坑（已核实，避免答辩被问倒）
 * ===========================================================================
 *  1. 生态环境部《大型活动碳中和实施指南（试行）》（公告 2019 年第 19 号）
 *     **不含任何排放因子数值**。它只给「排放源 → 该用哪份标准」的对照表。
 *     网上「因子出自这份指南」的说法不准确。它的正确用途是**合规性依据**——
 *     证明我们的因子选型遵循了生态环境部推荐的体系。
 *
 *  2. 《省级温室气体清单编制指南（2025 年版）》（环办气候〔2026〕1 号）
 *     **没有「每人公里」交通因子**。它是区域清单方法学，道路交通核算的是
 *     全省分燃料消费量 × 单位热值含碳量 × 碳氧化率。
 *     不要拿它的表 2.2 当出行因子用。
 *
 *  3. CPCD 的地铁因子有两个条目，相差 4.9 倍：
 *     8.81 与 43.14 gCO₂e/人·公里（后者名为「实际人公里」）。
 *     43.14 与京沪地铁实际量级及 DEFRA 伦敦地铁（27.8 g）更吻合，本库采用 43.14。
 *
 * 详细论证过程见工作区文档《因子库数据来源与折算方法.md》。
 * ===========================================================================
 */
import { Category, Factor } from '../model/Models';

/**
 * 出行类基准：燃油小汽车。
 * CPCD 2023 中型汽油轿车「大门到坟墓」全生命周期 0.19567 kgCO₂e/车·公里。
 * ⚠️ 口径假设：按**单人驾车**计，此时「车·公里」等于「人·公里」。
 *    若多人共乘，人均排放应除以乘员数，本应用暂不做此折算，已在应用内说明。
 */
const BASELINE_CAR: string = '燃油小汽车 0.19567 kgCO₂e/车·公里（按单人驾车，CPCD 2023）';

/** 河南省电网平均排放因子（公告 2025 年第 47 号 表 3） */
const GRID_HENAN: string =
  '生态环境部、国家统计局《关于发布 2023 年电力二氧化碳排放因子的公告》' +
  '（公告 2025 年第 47 号，2025-12-31）表 3 河南省 0.5897 kgCO₂/kWh';

/** 全国电网平均排放因子（同公告 表 1），作为河南省值的对照 */
const GRID_NATIONAL: number = 0.5306;

export const FACTORS: Factor[] = [
  // ------------------------------------------------------------------
  // 出行 —— 来源：CPCD 2023，基准为燃油小汽车
  // ------------------------------------------------------------------
  {
    id: 'travel.walk',
    category: Category.TRAVEL,
    name: '步行',
    unit: '公里',
    savedPerUnit: 0.19567,
    baseline: BASELINE_CAR,
    source: 'CPCD 中国产品全生命周期温室气体排放系数库（2023）'
  },
  {
    id: 'travel.bike',
    category: Category.TRAVEL,
    name: '骑行',
    unit: '公里',
    savedPerUnit: 0.19567,
    baseline: BASELINE_CAR,
    source: 'CPCD 中国产品全生命周期温室气体排放系数库（2023）'
  },
  {
    id: 'travel.metro',
    category: Category.TRAVEL,
    name: '地铁出行',
    unit: '公里',
    savedPerUnit: 0.15253,
    baseline: BASELINE_CAR,
    source: 'CPCD（2023）地铁 0.04314 kgCO₂e/人·公里 → 0.19567 − 0.04314 = 0.15253'
  },
  {
    id: 'travel.bus',
    category: Category.TRAVEL,
    name: '公交出行',
    unit: '公里',
    savedPerUnit: 0.14267,
    baseline: BASELINE_CAR,
    source: 'CPCD（2023）中型客车 0.053 kgCO₂e/人·公里 → 0.19567 − 0.053 = 0.14267'
  },
  {
    id: 'travel.nev',
    category: Category.TRAVEL,
    name: '新能源车出行',
    unit: '公里',
    savedPerUnit: 0.02567,
    baseline: BASELINE_CAR,
    source: 'CPCD（2023）纯电动汽车 0.17 kgCO₂e/公里 → 0.19567 − 0.17 = 0.02567'
  },

  // ------------------------------------------------------------------
  // 节水节电 —— 来源：生态环境部 2025 年第 47 号公告
  // ------------------------------------------------------------------
  {
    id: 'energy.power',
    category: Category.ENERGY,
    name: '节约用电',
    unit: '度',
    savedPerUnit: 0.5897,
    baseline: '不节电（等量电网供电）',
    source: GRID_HENAN
  },
  {
    id: 'energy.ac',
    category: Category.ENERGY,
    name: '少开空调',
    unit: '度',
    savedPerUnit: 0.5897,
    baseline: '不节电（等量电网供电）',
    source: GRID_HENAN +
      '。口径说明：按「节约的电量（度）」计量，不按「小时」——' +
      '每小时耗电量随匹数、能效等级、环境温度差异极大，无权威出处可依'
  },
  {
    id: 'energy.water',
    category: Category.ENERGY,
    name: '节约用水',
    unit: '立方米',
    savedPerUnit: 0.36218,
    baseline: '不节水（等量自来水供应 + 污水处理）',
    source: 'DEFRA 2025：供水 0.1913 + 污水处理 0.17088 = 0.36218 kgCO₂e/m³。' +
      '⚠️ 英国口径——中国官方未发布自来水碳排放因子，已在应用内标注'
  },

  // ------------------------------------------------------------------
  // 旧物回收 —— 减排量 = 原生料排放 − 再生料排放（同源同年求差）
  // ------------------------------------------------------------------
  {
    id: 'recycle.plastic',
    category: Category.RECYCLE,
    name: '回收塑料（PET）',
    unit: '公斤',
    savedPerUnit: 0.3208,
    baseline: '原生 PET 生产（未回收）',
    source: 'CPCD 2022：原生 PET 长丝 1.4929 − 再生 PET 长丝 1.1721 = 0.3208 kgCO₂e/kg'
  },
  {
    id: 'recycle.paper',
    category: Category.RECYCLE,
    name: '回收废纸',
    unit: '公斤',
    savedPerUnit: 0.2197,
    baseline: '原生纸浆生产（未回收）',
    source: 'DEFRA 2025 原生料 − 再生料。⚠️ 英国口径——中国官方未发布对应因子'
  },
  {
    id: 'recycle.can',
    category: Category.RECYCLE,
    name: '回收易拉罐（铝）',
    unit: '公斤',
    savedPerUnit: 8.1208,
    baseline: '原生铝电解生产（未回收）',
    source: 'DEFRA 2025 原生铝 − 再生铝。⚠️ 英国口径——中国官方未发布对应因子'
  },
  {
    id: 'recycle.cloth',
    category: Category.RECYCLE,
    name: '回收旧衣物',
    unit: '公斤',
    savedPerUnit: 22.1578,
    baseline: '新纺织面料生产（未回收）',
    source: 'DEFRA 2025 原生料 − 再生料。⚠️ 英国口径——中国官方未发布对应因子。' +
      '纺织业碳强度本身很高，故数值显著大于其他回收类'
  },

  // ------------------------------------------------------------------
  // 光盘行动
  // ------------------------------------------------------------------
  {
    id: 'food.cleanplate',
    category: Category.FOOD,
    name: '光盘行动',
    unit: '餐次',
    savedPerUnit: 0.19,
    baseline: '按每餐平均浪费量折算的混合食物碳强度',
    source: '中科院地理科学与资源研究所 + WWF《中国城市餐饮食物浪费报告》（2018）' +
      '人均浪费 93 克/餐 × 2.06 kgCO₂e/kg（FAO 折算）≈ 0.19 kgCO₂e/餐'
  },
  {
    id: 'food.waste',
    category: Category.FOOD,
    name: '减少食物浪费',
    unit: '公斤',
    savedPerUnit: 2.06,
    baseline: '混合食物全生命周期碳强度均值',
    source: 'FAO《Food Wastage Footprint》(2013) 折算值：3.3 Gt CO₂e ÷ 1.6 Gt 食物。' +
      '⚠️ 该值为折算所得而非 FAO 直接发布，且食物碳强度随种类差异极大，此处是混合均值'
  }
];

/** 按类目筛选因子 */
export function factorsOf(category: string): Factor[] {
  const out: Factor[] = [];
  for (let i = 0; i < FACTORS.length; i++) {
    if (FACTORS[i].category === category) {
      out.push(FACTORS[i]);
    }
  }
  return out;
}

/** 按 id 查因子，查不到返回 undefined */
export function factorById(id: string): Factor | undefined {
  for (let i = 0; i < FACTORS.length; i++) {
    if (FACTORS[i].id === id) {
      return FACTORS[i];
    }
  }
  return undefined;
}

/** 当前使用的电网因子口径（供「我的」页面展示与切换预留） */
export function gridFactorInfo(): string {
  return `河南省 ${GRID_HENAN.split(' ').pop()}（全国平均 ${GRID_NATIONAL}）`;
}
