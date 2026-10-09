/**
 * 端侧 AI 识别的统一入口 —— 创新拓展 2
 *
 * 全程离线：不发起任何网络请求，图片不会离开设备。
 *
 * 两条通路，**互相独立、各自失败都不影响另一条**：
 *   通路 A —— MindSpore Lite 视觉分类（需要 syscap.json 声明能力）
 *   通路 B —— Core Vision Kit 端侧 OCR + 关键词（作为保底）
 *
 * ⚠️ 已知环境限制（来自调研，务必知晓）：
 *   · Core Vision Kit **不支持模拟器**，OCR 通路只能在真机上验证；
 *     MindSpore Lite 支持模拟器。
 *   · 所以本模块对两条通路都做了 try/catch 降级：任何一条挂了，
 *     应用仍能正常手动录入，不会卡死或崩溃。
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { resourceManager } from '@kit.LocalizationKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { predictTopK } from './MindSporePredictor';
import {
  AiSuggestion,
  fuse,
  NO_SUGGESTION,
  suggestFromOcr,
  suggestFromVision,
  visionReady
} from './CategoryMapping';

const DOMAIN: number = 0x0006;
const TAG: string = 'LowCarbonClassifier';

/** OCR 引擎是否已初始化 */
let ocrInited: boolean = false;

/** 识别结果详情，便于 UI 展示与排查 */
export interface ClassifyDetail {
  suggestion: AiSuggestion;
  /** OCR 识别到的原文（可能为空） */
  ocrText: string;
  /** 视觉通路是否真的跑起来了 */
  visionOk: boolean;
  /** OCR 通路是否真的跑起来了 */
  ocrOk: boolean;
  /** 失败原因，供 UI 如实告知用户 */
  note: string;
}

// ---------------------------------------------------------------------------
// 取图
// ---------------------------------------------------------------------------

/** URI → PixelMap（两条通路的公共输入） */
async function uriToPixelMap(uri: string): Promise<image.PixelMap | undefined> {
  let file: fileIo.File | undefined = undefined;
  try {
    file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    const source: image.ImageSource = image.createImageSource(file.fd);
    const pixelMap: image.PixelMap = await source.createPixelMap();
    return pixelMap;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'uriToPixelMap failed: %{public}s', JSON.stringify(e));
    return undefined;
  } finally {
    if (file !== undefined) {
      try {
        await fileIo.close(file);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'close file failed');
      }
    }
  }
}

/** 从相册选一张图 */
export async function pickFromGallery(): Promise<image.PixelMap | undefined> {
  try {
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    options.maxSelectNumber = 1;
    const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
    const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
    const uris: string[] = result.photoUris;
    if (uris === undefined || uris.length === 0) {
      return undefined;
    }
    return await uriToPixelMap(uris[0]);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'pickFromGallery failed: %{public}s', JSON.stringify(e));
    return undefined;
  }
}

/** 调系统相机拍一张 */
export async function takePhoto(ctx: common.UIAbilityContext): Promise<image.PixelMap | undefined> {
  try {
    const profile: cameraPicker.PickerProfile = {
      cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
    };
    const result: cameraPicker.PickerResult = await cameraPicker.pick(
      ctx, [cameraPicker.PickerMediaType.PHOTO], profile
    );
    if (result.resultCode !== 0 || result.resultUri === undefined || result.resultUri.length === 0) {
      return undefined;
    }
    return await uriToPixelMap(result.resultUri);
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'takePhoto failed: %{public}s', JSON.stringify(e));
    return undefined;
  }
}

// ---------------------------------------------------------------------------
// 识别
// ---------------------------------------------------------------------------

/** OCR 通路：返回识别到的全量文本，失败返回空串 */
async function ocrRecognize(pixelMap: image.PixelMap): Promise<string> {
  try {
    if (!ocrInited) {
      await textRecognition.init();
      ocrInited = true;
    }
    const info: textRecognition.VisionInfo = { pixelMap: pixelMap };
    const config: textRecognition.TextRecognitionConfiguration = {
      isDirectionDetectionSupported: false
    };
    const res: textRecognition.TextRecognitionResult =
      await textRecognition.recognizeText(info, config);
    return res.value;
  } catch (e) {
    // 模拟器上会走到这里——Core Vision Kit 不支持模拟器，属预期行为
    hilog.warn(DOMAIN, TAG, 'ocr unavailable: %{public}s', JSON.stringify(e));
    return '';
  }
}

/** 释放 OCR 引擎（页面销毁时调用） */
export async function releaseOcr(): Promise<void> {
  if (!ocrInited) {
    return;
  }
  try {
    await textRecognition.release();
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'ocr release failed');
  }
  ocrInited = false;
}

/**
 * 端到端：PixelMap → AI 建议。
 * 两条通路各自 try/catch，任一失败都不影响另一条。
 */
export async function classify(
  mgr: resourceManager.ResourceManager,
  pixelMap: image.PixelMap
): Promise<ClassifyDetail> {
  let vision: AiSuggestion = NO_SUGGESTION;
  let visionOk: boolean = false;
  let note: string = '';

  // 通路 A：端侧视觉模型
  if (!visionReady()) {
    note = '视觉标定表为空，仅使用文字识别通路';
  } else {
    try {
      const topK = await predictTopK(mgr, pixelMap, 5);
      vision = suggestFromVision(topK);
      visionOk = true;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'vision path unavailable: %{public}s', JSON.stringify(e));
      note = '端侧模型不可用，已降级为文字识别';
    }
  }

  // 通路 B：端侧 OCR
  const text: string = await ocrRecognize(pixelMap);
  const ocrOk: boolean = text.length > 0;
  const ocr: AiSuggestion = suggestFromOcr(text);
  if (!ocrOk && note.length === 0) {
    note = '本机未识别到可用文字';
  }

  const detail: ClassifyDetail = {
    suggestion: fuse(vision, ocr),
    ocrText: text,
    visionOk: visionOk,
    ocrOk: ocrOk,
    note: note
  };
  return detail;
}
