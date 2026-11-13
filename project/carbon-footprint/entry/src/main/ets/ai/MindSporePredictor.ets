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
/** 正在进行的加载：并发调用共用同一个 Promise，避免同时加载两份 11.4 MB 模型 */
let pendingModel: Promise<mindSporeLite.Model> | undefined = undefined;

/** 一条候选：类别索引 + 分数 */
export interface ClassScore {
  index: number;
  score: number;
}

/** 取常驻模型：有缓存直接给；正在加载就等同一个 Promise；都没有才真正加载 */
async function ensureModel(mgr: resourceManager.ResourceManager): Promise<mindSporeLite.Model> {
  const cached: mindSporeLite.Model | undefined = cachedModel;
  if (cached !== undefined) {
    return cached;
  }
  const pending: Promise<mindSporeLite.Model> | undefined = pendingModel;
  if (pending !== undefined) {
    return pending;
  }
  const job: Promise<mindSporeLite.Model> = loadModel(mgr);
  pendingModel = job;
  try {
    return await job;
  } finally {
    pendingModel = undefined;
  }
}

/** 从 rawfile 加载模型（进程内只加载一次，常驻内存） */
async function loadModel(mgr: resourceManager.ResourceManager): Promise<mindSporeLite.Model> {
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
 * 流程：读源像素 → 等比缩放（短边 256）+ 中心裁剪 224×224（盒式平均）
 *       → RGBA 取 RGB → 归一化为 Float32
 *
 * ⚠️ 为什么不用 pixelMap.scale() / crop()：
 *   1. 它们是**原地变换**，会改掉调用方传进来的 PixelMap —— 预览图被裁成
 *      224×224，且 LowCarbonClassifier 先跑视觉再拿同一个 pm 跑 OCR 时，
 *      OCR 收到的是裁剪图，文字被裁掉、识别质量崩掉；
 *   2. 官方推荐的副本写法 pixelMap.clone() 需要 API 18，本项目兼容
 *      5.0.0(12)，真机上会直接抛错（构建期已报「API 18 才支持」警告）。
 * 所以在 JS 侧自己做重采样：既不碰调用方对象，也不依赖高版本 API。
 */
async function preprocess(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
  const info: image.ImageInfo = await pixelMap.getImageInfo();
  const w: number = info.size.width;
  const h: number = info.size.height;
  if (w <= 0 || h <= 0) {
    throw new Error('invalid image size');
  }

  // 1. 读源图像素（RGBA_8888）。只读，不改变原图。
  const srcBuf: ArrayBuffer = new ArrayBuffer(w * h * 4);
  await pixelMap.readPixelsToBuffer(srcBuf);
  const src: Uint8Array = new Uint8Array(srcBuf);

  // 2. 等比缩放到短边 RESIZE_SHORT，再中心裁剪成 INPUT_W × INPUT_H。
  //    缩放与裁剪合成一次重采样：每个目标像素取源图上对应的矩形，求 RGB 均值。
  const scale: number = RESIZE_SHORT / Math.min(w, h);
  const scaledW: number = Math.max(INPUT_W, Math.round(w * scale));
  const scaledH: number = Math.max(INPUT_H, Math.round(h * scale));
  const offX: number = Math.floor((scaledW - INPUT_W) / 2);
  const offY: number = Math.floor((scaledH - INPUT_H) / 2);

  const out: Float32Array = new Float32Array(INPUT_W * INPUT_H * 3);
  const bgr: boolean = CHANNEL_MODE === 'BGR';
  let o: number = 0;

  for (let y = 0; y < INPUT_H; y++) {
    const sy0: number = Math.min(h - 1, Math.floor((offY + y) / scale));
    const sy1: number = Math.min(h, Math.max(sy0 + 1, Math.floor((offY + y + 1) / scale)));
    for (let x = 0; x < INPUT_W; x++) {
      const sx0: number = Math.min(w - 1, Math.floor((offX + x) / scale));
      const sx1: number = Math.min(w, Math.max(sx0 + 1, Math.floor((offX + x + 1) / scale)));

      let sumR: number = 0;
      let sumG: number = 0;
      let sumB: number = 0;
      let n: number = 0;
      for (let yy = sy0; yy < sy1; yy++) {
        const row: number = yy * w;
        for (let xx = sx0; xx < sx1; xx++) {
          const i: number = (row + xx) * 4;
          sumR += src[i];
          sumG += src[i + 1];
          sumB += src[i + 2];
          n++;
        }
      }
      if (n === 0) {
        n = 1;
      }
      const c0: number = sumR / n;   // R
      const c1: number = sumG / n;   // G
      const c2: number = sumB / n;   // B
      const r: number = bgr ? c2 : c0;
      const b: number = bgr ? c0 : c2;
      out[o] = (r / 255.0 - MEANS[0]) / STDS[0];
      out[o + 1] = (c1 / 255.0 - MEANS[1]) / STDS[1];
      out[o + 2] = (b / 255.0 - MEANS[2]) / STDS[2];
      o += 3;
    }
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

/**
 * 清空常驻模型引用。
 *
 * 注意用词：这**不是**显式释放 native 内存。ArkTS 侧的 mindSporeLite.Model
 * 没有公开的 destroy/release 接口，置空后只保证下一次 ensureModel 重新加载，
 * 那 11.4 MB 要等 GC 回收。改名前它叫 releaseModel，看起来像释放，其实没有，
 * 属名实不符；调用点（AiSelfCheck.freeAiModel）语义也随之变成「卸载缓存」。
 * 若日后 SDK 提供了真正的释放接口，在下面补一行即可。
 */
export function releaseModel(): void {
  const m: mindSporeLite.Model | undefined = cachedModel;
  if (m !== undefined) {
    cachedModel = undefined;
  }
}
