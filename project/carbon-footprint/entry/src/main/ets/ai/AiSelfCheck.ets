/**
 * 端侧 AI 能力自检 —— 创新拓展 2 的配套工具
 *
 * 为什么需要它：
 *   端侧识别的效果取决于「模型输出索引 → 业务类目」的标定表，而这张表
 *   必须在设备上用真实照片标定（见 CategoryMapping 的文件头说明）。
 *   在做标定之前，得先确认三件事：模型能不能加载、输入输出张量对不对、
 *   推理能不能跑通。本模块就是干这个的——它把整条链路的中间结果打出来，
 *   让团队不必靠猜。
 *
 * 用途：
 *   1. 在「我的」页面点一下，就能看到模型是否可用、张量形状、Top-5 索引
 *   2. 用内置测试图跑一遍，验证预处理与推理链路（不需要相册权限）
 *   3. 输出的索引号直接就是标定表的素材
 *
 * 全程离线，不发起任何网络请求。
 */
import { image } from '@kit.ImageKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ClassScore, debugOutputShape, predictTopK, releaseModel } from './MindSporePredictor';
import { calibratedCount, ocrRuleCount, visionReady } from './CategoryMapping';

const DOMAIN: number = 0x0006;
const TAG: string = 'AiSelfCheck';

/** 内置自检图（放在 resources/rawfile 下） */
const TEST_IMAGE: string = 'selftest.jpg';

/** 自检结果 */
export interface AiCheckResult {
  /** 模型是否加载并推理成功 */
  ok: boolean;
  /** 张量形状与通道序等诊断信息 */
  shapeInfo: string;
  /** Top-5 候选（索引 + 分数） */
  topK: ClassScore[];
  /** 可读的 Top-5 文本 */
  topKText: string;
  /** 标定表状态说明 */
  calibration: string;
  /** 失败原因 */
  error: string;
}

/** 把 rawfile 里的图片读成 PixelMap */
async function loadTestPixelMap(
  mgr: resourceManager.ResourceManager
): Promise<image.PixelMap | undefined> {
  try {
    const bytes: Uint8Array = await mgr.getRawFileContent(TEST_IMAGE);
    const source: image.ImageSource = image.createImageSource(bytes.buffer.slice(0));
    const pm: image.PixelMap = await source.createPixelMap();
    return pm;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'load test image failed: %{public}s', JSON.stringify(e));
    return undefined;
  }
}

/**
 * 跑一次完整的端侧推理自检。
 * 任何一步失败都返回 ok=false 并带上原因，不抛异常——UI 只需展示结果。
 */
export async function runAiSelfCheck(
  mgr: resourceManager.ResourceManager
): Promise<AiCheckResult> {
  const calibration: string = visionReady()
    ? `标定表已配置 ${calibratedCount()} 条索引`
    : `标定表为空（${calibratedCount()} 条），视觉通路暂不产出建议；` +
      `文字识别通路已配置 ${ocrRuleCount()} 条关键词规则`;

  const pm: image.PixelMap | undefined = await loadTestPixelMap(mgr);
  if (pm === undefined) {
    const r: AiCheckResult = {
      ok: false,
      shapeInfo: '',
      topK: [],
      topKText: '',
      calibration: calibration,
      error: '读取内置自检图失败'
    };
    return r;
  }

  // 先取张量形状（这一步就能看出模型是否被 syscap 正确声明、能否加载）
  let shapeInfo: string = '';
  try {
    shapeInfo = await debugOutputShape(mgr, pm);
  } catch (e) {
    const err = e as Error;
    hilog.error(DOMAIN, TAG, 'debugOutputShape failed: %{public}s', JSON.stringify(e));
    const r: AiCheckResult = {
      ok: false,
      shapeInfo: '',
      topK: [],
      topKText: '',
      calibration: calibration,
      error: `模型加载或推理失败：${err.message}。` +
        `请确认 entry/src/main/syscap.json 已声明 SystemCapability.AI.MindSporeLite`
    };
    return r;
  }

  // 再取 Top-5
  try {
    const topK: ClassScore[] = await predictTopK(mgr, pm, 5);
    const parts: string[] = [];
    for (let i = 0; i < topK.length; i++) {
      parts.push(`#${topK[i].index}(${topK[i].score.toFixed(3)})`);
    }
    const r: AiCheckResult = {
      ok: true,
      shapeInfo: shapeInfo,
      topK: topK,
      topKText: parts.join('  '),
      calibration: calibration,
      error: ''
    };
    return r;
  } catch (e) {
    const err = e as Error;
    const r: AiCheckResult = {
      ok: false,
      shapeInfo: shapeInfo,
      topK: [],
      topKText: '',
      calibration: calibration,
      error: `推理失败：${err.message}`
    };
    return r;
  }
}

/** 释放常驻模型（省内存，可选调用） */
export function freeAiModel(): void {
  releaseModel();
}
