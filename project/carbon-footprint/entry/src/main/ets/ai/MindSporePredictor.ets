/**
 * 端侧图像分类推理器（MindSpore Lite · ArkTS）—— 创新拓展 2
 *
 * 全离线：模型来自 resources/rawfile/mobilenetv2.ms，**不发起任何网络请求**，
 * 图片不会离开设备。这是本创新点最重要的答辩卖点。
 *
 * 模型：MobileNetV2（Open Images 预训练），11.4 MB，文件魔数 MSL2。
 *   下载地址 https://download.mindspore.cn/model_zoo/official/lite/mobilenetv2_openimage_lite/1.5/mobilenetv2.ms
 *
 * ⚠️ 三条来自调研的关键提示（详见工作区《端侧AI图片识别_技术调研.md》）：
 *   1. `SystemCapability.AI.MindSporeLite` 在 SDK 里被标为 OpenHarmony 能力，
 *      必须在 entry/src/main/syscap.json 里显式 addedSysCaps，否则用不了。
 *   2. **通道序是本模块最大的坑**：官方示例把分量注释成 B/G/R，但 PixelMap
 *      读出的缓冲区实际是 RGBA。若 top-1 结果明显乱跳，八成就是这里错了。
 *      见 CHANNEL_MODE 常量，改动它即可切换。
 *   3. 模型输出不是归一化概率，只是相对分数，不能当置信度直接用。
 */
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { image } from '@kit.ImageKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0006;
const TAG: string = 'MindSporePredictor';

const MODEL_NAME: string = 'mobilenetv2.ms';

/** 模型输入尺寸（MobileNetV2 标准输入） */
const INPUT_W: number = 224;
const INPUT_H: number = 224;
/** 先缩放到短边 256，再中心裁剪 224（官方示例做法） */
const RESIZE_SHORT: number = 256;
const CROP_OFFSET: number = 16;

/** 归一化参数：必须与模型训练时一致，否则结果全错 */
const MEANS: number[] = [0.485, 0.456, 0.406];
const STDS: number[] = [0.229, 0.224, 0.225];

/**
 * 通道序。PixelMap.readPixelsToBuffer 给出的是 RGBA，
 * 而不同模型期望的输入顺序可能是 RGB 或 BGR。
 * 若识别结果明显不合理，先改这里试。
 */
const CHANNEL_MODE: string = 'RGB'; // 'RGB' | 'BGR'

let cachedModel: mindSporeLite.Model | undefined = undefined;

/** 一条候选：类别索引 + 分数 */
export interface ClassScore {
  index: number;
  score: number;
}

/** 从 rawfile 加载模型（进程内只加载一次，常驻内存） */
async function ensureModel(mgr: resourceManager.ResourceManager): Promise<mindSporeLite.Model> {
  const cached: mindSporeLite.Model | undefined = cachedModel;
  if (cached !== undefined) {
    return cached;
  }

  const raw: Uint8Array = await mgr.getRawFileContent(MODEL_NAME);
  hilog.info(DOMAIN, TAG, 'model bytes = %{public}d', raw.byteLength);

  const cpu: mindSporeLite.CpuDevice = {
    threadNum: 2,
    threadAffinityMode: mindSporeLite.ThreadAffinityMode.NO_AFFINITIES,
    precisionMode: 'enforce_fp32'
  };
  const context: mindSporeLite.Context = {
    target: ['cpu'],
    cpu: cpu
  };

  // 复制一份再交给推理引擎，避免与 rawfile 缓冲区共享内存
  const buf: ArrayBuffer = raw.buffer.slice(0);
  const model: mindSporeLite.Model = await mindSporeLite.loadModelFromBuffer(buf, context);
  cachedModel = model;
  hilog.info(DOMAIN, TAG, 'model loaded');
  return model;
}

/**
 * PixelMap → 模型输入张量。
 * 流程：等比缩放到短边 256 → 中心裁剪 224×224 → 读 RGBA → 归一化为 Float32
 */
async function preprocess(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
  const info: image.ImageInfo = await pixelMap.getImageInfo();
  const w: number = info.size.width;
  const h: number = info.size.height;

  if (w <= 0 || h <= 0) {
    throw new Error('invalid image size');
  }

  const scale: number = RESIZE_SHORT / Math.min(w, h);
  await pixelMap.scale(scale, scale);

  const after: image.ImageInfo = await pixelMap.getImageInfo();
  const ax: number = Math.floor((after.size.width - INPUT_W) / 2);
  const ay: number = Math.floor((after.size.height - INPUT_H) / 2);
  await pixelMap.crop({
    x: ax < 0 ? 0 : ax,
    y: ay < 0 ? 0 : ay,
    size: { width: INPUT_W, height: INPUT_H }
  });

  const rgba: ArrayBuffer = new ArrayBuffer(INPUT_W * INPUT_H * 4);
  await pixelMap.readPixelsToBuffer(rgba);
  const u8: Uint8Array = new Uint8Array(rgba);

  const out: Float32Array = new Float32Array(INPUT_W * INPUT_H * 3);
  const bgr: boolean = CHANNEL_MODE === 'BGR';
  let o: number = 0;
  for (let i = 0; i + 3 < u8.length; i += 4) {
    const c0: number = u8[i];         // R（RGBA 缓冲区的第 0 个分量）
    const c1: number = u8[i + 1];     // G
    const c2: number = u8[i + 2];     // B
    const r: number = bgr ? c2 : c0;
    const b: number = bgr ? c0 : c2;
    out[o] = (r / 255.0 - MEANS[0]) / STDS[0];
    out[o + 1] = (c1 / 255.0 - MEANS[1]) / STDS[1];
    out[o + 2] = (b / 255.0 - MEANS[2]) / STDS[2];
    o += 3;
  }
  return out.buffer;
}

/**
 * 端侧推理主入口。
 * @returns top-K（按分数降序）。索引的业务含义由 CategoryMapping 的标定表决定。
 */
export async function predictTopK(
  mgr: resourceManager.ResourceManager,
  pixelMap: image.PixelMap,
  k: number
): Promise<ClassScore[]> {
  const model: mindSporeLite.Model = await ensureModel(mgr);
  const inputBuffer: ArrayBuffer = await preprocess(pixelMap);

  const inputs: mindSporeLite.MSTensor[] = model.getInputs();
  if (inputs.length < 1) {
    throw new Error('model has no input tensor');
  }
  inputs[0].setData(inputBuffer);

  const outputs: mindSporeLite.MSTensor[] = await model.predict(inputs);
  if (outputs.length < 1) {
    throw new Error('model returned no output');
  }
  const logits: Float32Array = new Float32Array(outputs[0].getData());

  const all: ClassScore[] = [];
  for (let i = 0; i < logits.length; i++) {
    const item: ClassScore = { index: i, score: logits[i] };
    all.push(item);
  }
  all.sort((a: ClassScore, b: ClassScore): number => b.score - a.score);
  return all.slice(0, k);
}

/**
 * 诊断用：打印输入/输出张量形状。
 * 首次接入或排查通道序问题时，先跑这个确认模型输出维度（应为 1000 类）。
 */
export async function debugOutputShape(
  mgr: resourceManager.ResourceManager,
  pixelMap: image.PixelMap
): Promise<string> {
  const model: mindSporeLite.Model = await ensureModel(mgr);
  const inputBuffer: ArrayBuffer = await preprocess(pixelMap);
  const inputs: mindSporeLite.MSTensor[] = model.getInputs();
  inputs[0].setData(inputBuffer);
  const outputs: mindSporeLite.MSTensor[] = await model.predict(inputs);
  const inShape: string = JSON.stringify(inputs[0].shape);
  const outShape: string = JSON.stringify(outputs[0].shape);
  return `CHANNEL_MODE=${CHANNEL_MODE} input.shape=${inShape} ` +
    `output.shape=${outShape} elementNum=${outputs[0].elementNum}`;
}

/** 释放常驻模型（页面销毁时可选调用） */
export function releaseModel(): void {
  const m: mindSporeLite.Model | undefined = cachedModel;
  if (m !== undefined) {
    cachedModel = undefined;
  }
}
