/**
 * 端侧识别的「业务翻译层」—— 创新拓展 2
 *
 * 做两件事：
 *   1) 视觉模型的输出索引 → 本应用的 factorId（**标定表**）
 *   2) OCR 文本 → factorId（关键词规则）
 * 然后把两路融合成一条建议。
 *
 * factorId 全部取自 data/FactorLibrary.ets，请勿改动拼写。
 *
 * ===========================================================================
 * ⚠️ 标定表为什么是空的 —— 这是有意的，不是没做完
 * ===========================================================================
 * 官方 mobilenetv2.ms 是 Open Images 预训练模型，输出 1000 个通用类别，
 * 而官方**没有提供配套的标签文件**（找不到类名列表）。
 *
 * 绕过办法（不需要知道 1000 个类名叫什么）：
 *   只关心「哪些输出索引对应哪一类低碳行为」——
 *   1. 每个类目拍 2–3 张典型照片；
 *   2. 跑一次识别，把 top-5 的**索引号**打出来（用 debugOutputShape 与日志）；
 *   3. 若「塑料瓶」这组照片反复在索引 A、B 上得高分，就把 A、B 记到
 *      'recycle.plastic' 名下；
 *   4. 没标定到的索引一律视为「无法判定」。
 *
 * 答辩话术：模型的类目空间是通用的（Open Images），我们在端侧做了一层
 * **类目标定**，把它映射到本应用的 4 大类 14 个低碳行为，并且只在高置信时
 * 预填、低置信交给用户确认——既保证体验，也避免 AI 误判污染用户的碳账本。
 *
 * 重要：**14 类里大约只有 6–8 类能靠视觉模型覆盖**（回收类、餐饮类较好；
 * 「地铁」「新能源车」「步行」「节约用电」这类行为/账单语义的类别，
 * 通用分类器天然识别不了），所以「AI 预填 + 用户确认」不是妥协，而是正解。
 */
import { ClassScore } from './MindSporePredictor';

/** 一条 AI 建议 */
export interface AiSuggestion {
  factorId: string;
  /** 0~1，AI 对该建议的把握 */
  confidence: number;
  /** 依据说明，用于 UI 展示与答辩演示 */
  reason: string;
  /** 来源通路 */
  source: string; // 'vision' | 'ocr' | 'none'
}

/** 无结果时的返回值 */
export const NO_SUGGESTION: AiSuggestion = {
  factorId: '',
  confidence: 0,
  reason: '未能识别，请手动选择',
  source: 'none'
};

/* ------------------------------------------------------------------ *
 * 1) 视觉通路：输出索引 → factorId
 *
 * ⚠️ 下表需要在真机上用团队自己拍的照片标定后填入（见文件头说明）。
 *    空表 = 视觉通路暂时不产出建议，但不影响 OCR 通路与整体功能。
 * ------------------------------------------------------------------ */
const INDEX_TO_FACTOR: Map<number, string> = new Map<number, string>([
  // 标定示例（**请替换为实测出的真实索引**）：
  // [440, 'recycle.plastic'],
  // [720, 'travel.bus'],
  // [301, 'recycle.cloth'],
]);

/** 标定表当前已标定的条目数（UI 上用来如实告知能力边界） */
export function calibratedCount(): number {
  return INDEX_TO_FACTOR.size;
}

/** 视觉通路：把 top-K 变成建议。第一条命中标定表的即为结果 */
export function suggestFromVision(topK: ClassScore[]): AiSuggestion {
  for (let i = 0; i < topK.length; i++) {
    const item: ClassScore = topK[i];
    const factorId: string | undefined = INDEX_TO_FACTOR.get(item.index);
    if (factorId !== undefined && factorId.length > 0) {
      const conf: number = item.score > 1 ? 1 : (item.score < 0 ? 0 : item.score);
      const s: AiSuggestion = {
        factorId: factorId,
        confidence: conf,
        reason: `端侧模型命中类别 ${item.index}（得分 ${item.score.toFixed(3)}）`,
        source: 'vision'
      };
      return s;
    }
  }
  return NO_SUGGESTION;
}

/** 视觉通路是否可用（标定表非空） */
export function visionReady(): boolean {
  return INDEX_TO_FACTOR.size > 0;
}

/* ------------------------------------------------------------------ *
 * 2) OCR 通路：关键词 → factorId
 *
 * 规则按「先具体后宽泛」排列，命中即返回。
 * 关键词可自由扩充，改这里不用重新编译模型，非常适合快速迭代。
 * ------------------------------------------------------------------ */
interface KeywordRule {
  keywords: string[];
  factorId: string;
}

const OCR_RULES: KeywordRule[] = [
  // —— 出行 ——
  { keywords: ['地铁', '轨道交通', 'metro', 'subway', '号线', '乘车码'], factorId: 'travel.metro' },
  { keywords: ['公交', '巴士', 'bus', '公交站', '快速公交', 'brt'], factorId: 'travel.bus' },
  { keywords: ['共享单车', '骑行', '自行车', '哈啰', '美团单车', '青桔'], factorId: 'travel.bike' },
  { keywords: ['新能源汽车', '充电桩', '电动车充电', '国网电动'], factorId: 'travel.nev' },
  { keywords: ['步数', '健走', '步行', '万步'], factorId: 'travel.walk' },
  // —— 节水节电 ——
  { keywords: ['电费', '用电量', '千瓦时', 'kwh', '度电', '电表'], factorId: 'energy.power' },
  { keywords: ['水费', '用水量', '立方米', '吨水', '水表'], factorId: 'energy.water' },
  { keywords: ['空调', '制冷', '26℃', '温度设定'], factorId: 'energy.ac' },
  // —— 旧物回收 ——
  { keywords: ['可回收物', '回收塑料', '塑料瓶', 'pet', '饮料瓶'], factorId: 'recycle.plastic' },
  { keywords: ['废纸', '纸箱', '报纸', '纸类回收', '纸板'], factorId: 'recycle.paper' },
  { keywords: ['易拉罐', '铝罐', '金属回收', '铝制品'], factorId: 'recycle.can' },
  { keywords: ['旧衣物', '旧衣服', '纺织', '织物回收', '捐衣'], factorId: 'recycle.cloth' },
  // —— 光盘行动 ——
  { keywords: ['光盘行动', '光盘', '剩菜打包', '打包盒'], factorId: 'food.cleanplate' },
  { keywords: ['食物浪费', '厨余', '按需点餐', '小份菜'], factorId: 'food.waste' }
];

/** 已配置的关键词规则条数 */
export function ocrRuleCount(): number {
  return OCR_RULES.length;
}

/** OCR 文本 → 建议。命中多条时取最先匹配（规则表已按具体度排序） */
export function suggestFromOcr(text: string): AiSuggestion {
  if (text.length === 0) {
    return NO_SUGGESTION;
  }
  const lower: string = text.toLowerCase();
  for (let r = 0; r < OCR_RULES.length; r++) {
    const rule: KeywordRule = OCR_RULES[r];
    for (let k = 0; k < rule.keywords.length; k++) {
      const kw: string = rule.keywords[k];
      if (lower.includes(kw.toLowerCase())) {
        const s: AiSuggestion = {
          factorId: rule.factorId,
          confidence: 0.75,
          reason: `识别到文字「${kw}」`,
          source: 'ocr'
        };
        return s;
      }
    }
  }
  return NO_SUGGESTION;
}

/* ------------------------------------------------------------------ *
 * 3) 两路融合
 * ------------------------------------------------------------------ */

/** 融合：谁置信度高用谁；同 factorId 则加成；冲突则降权提示确认 */
export function fuse(vision: AiSuggestion, ocr: AiSuggestion): AiSuggestion {
  if (vision.factorId.length === 0 && ocr.factorId.length === 0) {
    return NO_SUGGESTION;
  }
  if (vision.factorId.length === 0) {
    return ocr;
  }
  if (ocr.factorId.length === 0) {
    return vision;
  }
  if (vision.factorId === ocr.factorId) {
    const both: AiSuggestion = {
      factorId: vision.factorId,
      confidence: Math.min(1, vision.confidence + ocr.confidence * 0.5),
      reason: `图像与文字双路一致：${vision.reason}；${ocr.reason}`,
      source: 'vision'
    };
    return both;
  }
  const winner: AiSuggestion = vision.confidence >= ocr.confidence ? vision : ocr;
  const conflicted: AiSuggestion = {
    factorId: winner.factorId,
    confidence: winner.confidence * 0.6,
    reason: `图像与文字结果不一致，倾向：${winner.reason}`,
    source: winner.source
  };
  return conflicted;
}

/** 按 factorId 反查是否在因子库中存在——避免标定表写错时把脏数据写进账本 */
export function isKnownFactor(factorId: string, known: string[]): boolean {
  return known.indexOf(factorId) >= 0;
}
