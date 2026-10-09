# 端侧 AI 图片识别低碳行为 —— 技术可行性调研

> 调研对象：`project/carbon-footprint`（ArkTS，`compatibleSdkVersion 5.0.0(12)`，`runtimeOS: HarmonyOS`）
> 调研日期：2026-09-30
> 调研方法：**以本机真实 SDK 的 `.d.ts` 声明文件为准**（`/Applications/DevEco-Studio.app/Contents/sdk/default`，HarmonyOS 26.0.0 / API 26，`sdk-pkg.json` 实测），交叉核对**华为官方文档**（文档版本 V241，更新时间 2026-09-23，通过 `developer.huawei.com` 文档接口逐页抓取正文）。
> **重要**：本文所有 API 名称、`@since` 版本号、错误码、标签枚举，都是我从 SDK 声明文件里**逐字核对**过的；凡是没核对到的，一律写进第 8 节「未确认清单」。

---

## 1. 结论速览（TL;DR）

**能做，但要选对方案，并且必须改产品设计。**

| 判断 | 内容 |
|---|---|
| ✅ **首选（推荐）** | **MindSpore Lite Kit（ArkTS）+ 官方可下载的 `mobilenetv2.ms` + 「输出索引→类目」标定表 + 用户一键确认**。纯 ArkTS，无需 C++，`@since 10/12`，天然离线。 |
| ✅ **并行保底** | **Core Vision Kit OCR（`textRecognition`）+ 关键词规则**。`@since 4.0.0(10)`，官方 60 行示例可直接抄，几乎不可能失败。 |
| ⚠️ **关键前置条件** | MindSpore Lite 在 HarmonyOS 工程里**必须手写 `entry/src/main/syscap.json`**，否则编不过/跑不起来（华为官方文档明确要求，见 5.1）。 |
| ❌ **不建议** | 自己采数据 + 训练 + 转 `.ms` 的 14 类定制模型。3–5 天做不完，属于 5 星级风险。 |
| ❌ **不可用** | **HarmonyOS SDK 中不存在开箱即用的通用图像分类 API**（我枚举了 hms + openharmony 全部声明文件，`grep -ri classif` 无任何图像分类接口）。理由详见 4.4。 |
| ❌ **不可用** | Core Vision Kit「多目标识别」只有 **18 个粗标签**，覆盖不了你的 14 个行为（详见 4.1）。 |
| ❌ **不可用** | HiAI Foundation / CANNKit 只有 **Native C++ API**，纯 ArkTS 用不了，且要自备 `.om` 模型。 |
| ⚠️ **必须调整的产品设计** | 模型**无法可靠区分**「步行 / 骑行 / 地铁 / 公交 / 新能源车」这 5 类中的后 3 类，也分不出「新能源车 vs 燃油车」。所以 AI 只能是**预填建议 + 用户确认**，不能是「AI 全自动判定」。这样设计反而更好答辩。 |
| 🎯 **答辩指标建议** | 不要吹「分类准确率」，改吹 **「AI 预填命中率 / 人工修正率」**——可测、诚实、且是真实产品指标。 |

**一句话给团队**：把「AI 自动识别」重新定义为**「AI 预填 + 一键确认」**，端侧 OCR 打底、MindSpore Lite 加分，3–5 天稳得住；坚持要「14 类全自动精准识别」则建议放弃。

---

## 2. 方案对比表

「端侧/离线」列含义：**端侧**＝推理在设备上完成；**离线**＝断网可用。「证据」列说明我的依据强度。

| # | 方案 | API 名称与导入路径 | 端侧 | 离线 | 支持的能力 | 难度(1-5★) | 需自备模型 | 推荐度 |
|---|---|---|---|---|---|---|---|---|
| 1 | **图像分类（自定义模型）** | `mindSporeLite.loadModelFromBuffer()` / `predict()`<br>`import { mindSporeLite } from '@kit.MindSporeLiteKit'` | ✅ | ✅ | 任意自定义分类（.ms 模型） | ★★★（抄官方示例） | **是**（官方 `mobilenetv2.ms` 可直接下载） | ⭐⭐⭐⭐⭐ **首选** |
| 2 | **端侧 OCR** | `textRecognition.recognizeText()`<br>`import { textRecognition } from '@kit.CoreVisionKit'` | ✅ | ✅（强推断，见 8.2） | 通用文字识别，5 种语言，返回文本+行+词+包围盒 | ★★ | 否（系统预置） | ⭐⭐⭐⭐⭐ **保底** |
| 3 | 端侧 NLP（配合 OCR） | `textProcessing.getWordSegment()` / `getEntity()`<br>`import { textProcessing } from '@kit.NaturalLanguageKit'` | ✅ | ✅（强推断） | 中文分词、实体识别 | ★★ | 否 | ⭐⭐⭐⭐ 增强项 |
| 4 | 多目标识别 | `objectDetection.ObjectDetector.create()` / `.process()`<br>`import { objectDetection, visionBase } from '@kit.CoreVisionKit'` | ✅ | ✅（强推断） | **仅 18 个粗标签**（见 4.1），带包围盒 | ★★ | 否 | ⭐⭐ 表达力不足，只能当辅助信号 |
| 5 | 主体分割 | `subjectSegmentation.doSegmentation()`<br>`import { subjectSegmentation } from '@kit.CoreVisionKit'` | ✅ | ✅（强推断） | 抠出显著主体 + 掩膜 + 包围盒，**无类别标签** | ★★ | 否 | ⭐⭐⭐ 只能做「有没有主体/抠图」 |
| 6 | AI 图像识别控件 | `visionImageAnalyzer.VisionImageAnalyzerController`<br>`import { visionImageAnalyzer } from '@kit.VisionKit'` | ⚠️ 部分是（"视觉搜索"疑云侧） | ❌ | UI 控件：文字分析、主体识别、视觉搜索 | ★★★★ | 否 | ⭐ 是 UI 控件不是无头 API，不适合本场景 |
| 7 | 人脸检测/比对、骨骼点、超分 | `faceDetector` / `faceComparator` / `skeletonDetection` / `imageSuperResolution` | ✅ | ✅ | 人脸框、1v1 比对、骨骼点、图像超分 | ★★ | 否 | ⭐ 与本项目无关（超分为 **API 26** 新增，见 4.4） |
| 8 | 以文搜图 | `textSearchImage.search()`<br>`import { textSearchImage } from '@kit.CoreVisionKit'` | ✅ | ✅ | 文本→图库检索（跨模态） | ★★★ | 否 | ❌ **`@since 26.0.0`，API 12 用不了** |
| 9 | HiAI Foundation | CANNKit Native C API<br>`#include <hiai_foundation/hiai_helper.h>` | ✅ | ✅ | 自定义模型推理（NPU 加速） | ★★★★★ | **是**（须自行转 `.om`） | ⭐ 纯 Native，禁止 |
| 10 | 云侧 AI（对比项） | 各种 REST / `@hms.ai.*` 云服务 | ❌ | ❌ | 强 | ★★ | 否 | ❌ **不满足硬性约束 1、2** |

---

## 3. 关于 OpenHarmony / HarmonyOS 的差异（很重要）

本项目 `runtimeOS: HarmonyOS`。我在 SDK 里发现一个**会让你们踩坑的事实**：

SDK 的 `hms/ets/api/device-define/` 下有**两套**设备能力集：

| 文件 | `SystemCapability.AI.OCR.TextRecognition`<br>（Core Vision Kit） | `SystemCapability.AI.MindSporeLite`<br>（MindSpore Lite ArkTS） |
|---|---|---|
| `phone.json`（OpenHarmony 能力集） | ❌ 无 | ✅ 有 |
| `phone-hmos.json`（HarmonyOS 能力集） | ✅ 有 | ❌ **无** |

而 `syscap-version.json` 里明确标注：`SystemCapability.AI.MindSporeLite` 的 `OS` 字段是 **`OpenHarmony`**。

**这意味着：在 `runtimeOS: HarmonyOS` 的工程里直接用 MindSpore Lite ArkTS API，会被 syscap 校验拦住。** 这不是我的猜测——**华为官方文档专门为此给了解法**：

> 「工程默认设备定义的能力集可能不包含 MindSporeLite。需在 DevEco Studio 工程的 `entry/src/main` 目录下，手动创建 `syscap.json` 文件」
> ——《使用 MindSpore Lite 实现图像分类 (ArkTS)》

所以它是**能用**的，但**必须加这个配置**。同理，官方那个 ArkTS Demo 自己写的是 `"runtimeOS": "OpenHarmony"`、`compatibleSdkVersion: 11`、「支持设备：RK3568」——**它是 OpenHarmony 开发板示例，不是 HarmonyOS 手机示例**。所以「HarmonyOS 真机上到底能不能跑」必须实测（见 5.2 的门槛 0）。这是本方案**最大的单点风险**，我在第 8 节列为未确认。

另外，Core Vision Kit 是**华为闭源能力（HMS）**，官方文档明确「本 Kit 暂不支持模拟器」——**你们必须有华为真机**，模拟器上 OCR 跑不了。MindSpore Lite 反而「支持模拟器（不支持 NPU 后端）」。

---

## 4. 逐项结论（对应你提的 6 个问题）

### 4.1 HarmonyOS 官方 AI 能力：Core Vision Kit（`@kit.CoreVisionKit`）

`@kit.CoreVisionKit` 整体 `@since 4.1.0(11)`，共导出 9 个模块（SDK 实测）：

```
visionBase, textRecognition, faceDetector, faceComparator,
subjectSegmentation, objectDetection, skeletonDetection,
imageSuperResolution, textSearchImage
```

**关键结论：有 OCR，有主体分割，有目标检测，但没有任何「图像分类」能力。** 三个视觉能力的 `@since` 与输入输出：

| 能力 | `@since` | 输入 | 输出 | 能否用于本项目 |
|---|---|---|---|---|
| `textRecognition`（OCR） | `4.0.0(10)` | `{pixelMap}`（RGBA_8888） | `value` 全文 + `blocks/lines/words` + 包围盒 | ✅ **能**（保底方案） |
| `objectDetection`（多目标识别） | `5.0.0(12)` | `visionBase.Request{inputData:{pixelMap}}` | `objects[]`：`boundingBox`/`score`/`labels:number[]`/`id` | ⚠️ 勉强 |
| `subjectSegmentation` | `5.0.0(12)` | `{pixelMap}`（RGBA_8888） | `fullSubject`/`subjectDetails`：前景 PixelMap + 掩膜 + 包围盒 | ⚠️ 无标签 |

**`objectDetection` 的标签是写死的 18 类**（SDK 声明文件里逐字抄下来的注释）：

```
0: Scene, 1: Animal, 2: Plant, 3: Building, 5: PersonFace, 6: Table,
7: Text, 8: PersonHead, 9: Cathead, 10: Doghead, 11: Food, 12: Car,
13: Person, 21: Document, 22: Card
```

对照你们的 14 个行为：**只有 `Food`(11) 和 `Car`(12) 和 `Document`(21) 勉强沾边**，且 `Car` 分不出新能源车和燃油车，没有任何「自行车 / 公交车 / 地铁 / 瓶子 / 易拉罐 / 衣物」标签。**结论：单靠 Core Vision Kit 无法完成 14 类识别。**

**「端侧 / 离线」的证据强度**：
- 输入端只接受内存中的 `PixelMap`，**API 里没有任何网络参数**；
- `visionBase` 里那一整套 `on('downloadStart'/'downloadComplete'/'downloadProgress'...)` 模型下载接口，SDK 注释全部标注 **"This API is reserved and is not supported in the current version."** → 说明**模型是随系统预置的，不需要联网下载**；
- 官方文档把 `textRecognition.init()` 解释为「**加载模型**」。
- ⚠️ 但华为官方文档**并没有显式写「不联网 / 数据不出端」**。所以这是**强推断，不是官方明文**。答辩前请务必**开飞行模式实测一遍**（见 5.2 门槛 0）。

**约束与限制**（官方文档原文要点，务必看）：
- 支持设备：Phone、Tablet、PC/2in1；**仅适用于中国境内**；**不支持模拟器**。
- OCR：JPEG/JPG/PNG；简中/英/日/韩/繁中；≤10000 字符；**对印刷体好，手写体能力欠缺**；建议 720p 以上，100px<高<15210px，100px<宽<10000px，高宽比建议 10:1 以内；拍摄角度与文本平面夹角 <30°。
- 多目标识别：建议 720p 以上；物体占比需 >0.1%。
- 主体分割：物体占比 ≥ 原图 0.5% 才算主体；**"不建议用于处理包含较多文字内容的图片分析场景"**。
- **并发限制**：同一进程同一时间不能并发调用同一个特性，否则返回「系统繁忙」。

### 4.2 MindSpore Lite Kit（`@kit.MindSporeLiteKit`）—— 本项目的技术核心

**结论：能用，纯 ArkTS，不需要写一行 C++。**

- 导入：`import { mindSporeLite } from '@kit.MindSporeLiteKit'`（kit 文件在 SDK 的 `openharmony/ets/kits/@kit.MindSporeLiteKit.d.ts`，底层模块 `@ohos.ai.mindSporeLite`）
- syscap：`SystemCapability.AI.MindSporeLite`（**注意 3. 节说的 HarmonyOS 工程需 `syscap.json`**）
- **格式：`.ms`**（官方原文：「MindSpore Lite 使用 `.ms` 格式模型进行推理」）。我实际下载了官方模型验证，文件头魔数是 `MSL2`（MindSpore Lite v2 格式）。
- 官方定位（文档原文）：「MindSpore Lite 是 **HarmonyOS 内置的**轻量化 AI 引擎」「已作为系统部件在 **HarmonyOS 标准系统内置**」。
- 支持设备：Phone、Tablet、PC/2in1、TV、Wearable。**支持模拟器**（不支持 NPU 后端）。
- 可用后端：CPU / GPU / NNRt（NPU）。`context.target = ['cpu']`。

**ArkTS 侧 API（全部从 SDK 逐字核对，`@since` 版本见括号）：**

```ts
// 加载模型（三选一）
mindSporeLite.loadModelFromFile(model: string, context?: Context): Promise<Model>   // @since 10
mindSporeLite.loadModelFromBuffer(model: ArrayBuffer, context?: Context): Promise<Model>  // @since 10
mindSporeLite.loadModelFromFd(model: number, context?: Context): Promise<Model>     // @since 10

// Model（@since 10）
model.getInputs(): MSTensor[]
model.predict(inputs: MSTensor[]): Promise<MSTensor[]>       // 也有 callback 重载
model.resize(inputs: MSTensor[], dims: Array<Array<number>>): boolean

// MSTensor（@since 10）
tensor.name: string; tensor.shape: number[]; tensor.elementNum: number
tensor.dataSize: number; tensor.dtype: DataType; tensor.format: Format
tensor.getData(): ArrayBuffer
tensor.setData(inputArray: ArrayBuffer): void

// Context（@since 10）
context.target?: string[]        // ['cpu'] / ['nnrt'] / ...
context.cpu?: { threadNum?, threadAffinityMode?, threadAffinityCoreList?, precisionMode? }
context.nnrt?: { deviceID?: bigint, performanceMode?, priority?, extensions? }   // @since 12
```

**全部核心推理 API 是 `@since 10`，`compatibleSdkVersion 5.0.0(12)` 完全够用。** ✅

**有没有现成的图像分类模型可下载？有，而且我验证过链接可用：**

| 项目 | 值 |
|---|---|
| 官方模型名 | `mobilenetv2.ms`（MobileNetV2，Open Images 训练） |
| 官方下载地址 | `https://download.mindspore.cn/model_zoo/official/lite/mobilenetv2_openimage_lite/1.5/mobilenetv2.ms` |
| 实测结果 | HTTP 200，**11,447,840 字节（≈10.9 MiB）**，`Content-Type: application/octet-stream`，文件头 `28 00 00 00 4D 53 4C 32`（`MSL2`）✅ |
| 同目录还有 | `mobilenetv2.mindir`（11.3 MiB）、`mobilenetv2_1_5.ckpt`（11.1 MiB） |
| 官方示例工程 | `gitee.com/openharmony/applications_app_samples` → `code/DocsSample/ApplicationModels/MindSporeLiteArkTSDemo/`（ArkTS 版，模型已随仓库带）<br>另有 C/C++ 版 `MindSporeLiteCDemo` |
| 放哪 | `entry/src/main/resources/rawfile/mobilenetv2.ms` |

⚠️ **该模型的类别数与官方标签文件我没找到**（见 8.1）。但**这不影响可行性**——见 5.3 的「标定表」做法。

**如果要自己转模型**（不建议在 3–5 天内做，但列出来供答辩备问）：
- 工具：`converter_lite`，从 `mindspore-lite-2.7.0-linux-x64.tar.gz` 获取（官方文档给的就是这个版本号）。
- `--fmk` 支持 `MINDIR / CAFFE / TFLITE / TF / ONNX / PYTORCH / MSLITE`。
- ⚠️ **两个大坑**：(a) **转换工具是 Linux x86_64 的**（官方推荐 Ubuntu 18.04），你们如果是 mac/Windows 得开虚拟机或 WSL；(b) 下载的安装包**不支持转 PyTorch 模型**，必须源码编译并 `export MSLITE_ENABLE_CONVERT_PYTORCH_MODEL=on`。
- ⚠️ 华为文档另有提醒：「若需基于本 Demo 适配自有模型，请**优先选择静态 Shape 模型**。注意：**ArkTS 接口不支持 NPU 后端动态 Shape 模型推理**。」

### 4.3 HiAI Foundation / `@hms.ai.*` 系列

SDK 实测，`hms/ets/api/` 下 `@hms.ai.*` 全部模块：

```
A2A, AICaption, AgentFramework, CardRecognition, DocumentScanner, appController,
face.faceComparator, face.faceDetector, insightIntent.*, interactiveLiveness,
nlp.textProcessing, ocr.textRecognition, speechRecognizer, textReader,
textToSpeech, vision.imageSuperResolution, vision.objectDetection,
vision.skeletonDetection, vision.subjectSegmentation, vision.textSearchImage,
vision.visionBase, visionImageAnalyzer
```

**逐项判定：**

| 模块 | 判定 |
|---|---|
| `faceDetector` / `faceComparator` / `skeletonDetection` | 端侧可用（`5.0.0(12)`），但**与本项目无关** |
| `imageSuperResolution` | ✅ 端侧，但 **`@since 26.0.0`** → API 12 用不了 |
| `textSearchImage` | ✅ 端侧，但 **`@since 26.0.0`** → API 12 用不了 |
| `visionImageAnalyzer` | UI 控件（要挂在 Image 组件上），`startObjectSearch()` 是「视觉搜索」面板，**疑似云侧/系统级能力**，不适合无头推理 |
| `CardRecognition` / `DocumentScanner` / `interactiveLiveness` | 都是**带 UI 的卡片/文档扫描控件**，不是分类能力 |
| `AICaption` / `textReader` / `textToSpeech` | 音频字幕/朗读，无关 |
| `speechRecognizer` | 端侧语音识别，`@since 4.1.0(11)`，**可做「AI 语音输入」替代方案**（见 7.3） |
| **HiAI Foundation** | syscap `SystemCapability.AI.HiAIFoundation`，`OS=HarmonyOS`，`5.0.0(12)` 起可用。**但 SDK 里只有 Native C 头文件**：`hms/native/sysroot/usr/include/hiai_foundation/{hiai_helper.h, hiai_tensor.h, hiai_options.h, hiai_aipp_param.h, hiai_single_op.h}` 和动态库 `libhiai_foundation.so`，Kit 名为 **CANNKit**。**没有 ArkTS 接口。**且要自备 `.om` 离线模型。**纯 ArkTS 工程用不了，直接排除。** |

### 4.4 HarmonyOS 是否提供开箱即用的图像分类 API？—— ❌ **不提供**

我在整个 SDK（`hms/ets/api/` + `openharmony/ets/api/`）里跑 `grep -ril "classif"`，命中的全是无关模块（蓝牙设备 class、音频、DLP、`identifySensitiveContent` 内容分级等）。**没有任何图像分类 API。**

官方文档里能提供的「开箱即用」只有这些，全都**不是**通用图像分类：
- OCR（`textRecognition`）
- 多目标识别（`objectDetection`，18 类）
- 主体分割（`subjectSegmentation`，无类别）
- 人脸 / 骨骼点 / 超分 / 以文搜图

**所以：想识别「自行车 / 瓶子 / 衣物」这类具体物体，只有两条路——Core Vision Kit 的 18 类（覆盖不了），或者自己上 MindSpore Lite 跑模型。** 这正是我把 MindSpore Lite 列为首选的原因。

### 4.5 端侧 OCR（兜底方案）

✅ **可用，而且是本场景**最稳**的一环。**

- `textRecognition.recognizeText()` `@since 4.0.0(10)`；`textRecognition.init()` / `release()` `@since 5.0.0(12)`。
- 返回 `TextRecognitionResult`：`value`（整图文本）、`blocks[].lines[].words[].cornerPoints`（层层带包围盒）。
- 支持简中/英/日/韩/繁中；有 `getSupportedLanguages()` 可查询。
- 错误码：`1001400001`（识别失败）、`1001400002`（服务异常）、`200`（超时）、`401`（参数错误）。
- `TextRecognitionConfiguration.isDirectionDetectionSupported` 默认 `true`；已知图片方向正确时设 `false` 可提性能。

**为什么它对本项目特别好用**：你们的 14 个行为在真实照片里**大量伴随文字**——地铁站牌/线路图（地铁出行）、公交车头/站牌（公交出行）、回收箱标识（可回收物/塑料/纸类/织物）、餐厅菜单或小票（光盘行动）、电费水费单（节约用电/用水）、共享单车车身上的字样（骑行）。OCR + 关键词命中，**可解释性极强**，答辩时能当场展示「AI 读到了『可回收物·塑料』所以我填了回收塑料」。这比一个黑盒 1000 类模型的输出**更好讲**。

### 4.6 调用系统相机/相册的 API，以及图片怎么传给推理引擎

**相册（推荐用这个，无需申请权限）——官方 OCR/分类示例都用它：**

```ts
import { photoAccessHelper } from '@kit.MediaLibraryKit';

let options = new photoAccessHelper.PhotoSelectOptions();
options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE; // 只要图片
options.maxSelectNumber = 1;
let picker = new photoAccessHelper.PhotoViewPicker();
let result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
let uri: string = result.photoUris[0];
```
`@ohos.file.picker` 里的旧版 `PhotoViewPicker` 已被标注 `@useinstead @ohos.file.photoAccessHelper`，**请直接用 `photoAccessHelper`**。

**相机：** `import { cameraPicker } from '@kit.CameraKit'`
```ts
cameraPicker.pick(context, [cameraPicker.PickerMediaType.PHOTO], {
  cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
}): Promise<cameraPicker.PickerResult>   // @since 11
// → result.resultUri  (resultCode === 0 表示成功)
```
`cameraPicker` `@since 11`，**在 API 12 可用** ✅。官方注释明确：**必须在 UIAbility 内调用**，否则拉不起来。用 `cameraPicker` 的好处是**完全不用管相机权限、不用管 CameraKit 的 session 生命周期**——对 3–5 天工期这是最优解。若要从零搭建 `@ohos.multimedia.camera` 预览/拍照会话，工作量会翻几倍，**不建议**。

**URI → PixelMap（所有方案的公共前置）：**
```ts
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

let file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
let imageSource = image.createImageSource(file.fd);   // 也有 createImageSource(uri: string)
let pixelMap = await imageSource.createPixelMap();     // ← Core Vision Kit / MindSpore Lite 的统一输入
await fileIo.close(file);
```

**推理引擎的输入格式（关键差异！）：**
- **Core Vision Kit（OCR / 目标检测 / 主体分割）**：直接吃 `PixelMap`，**只支持 RGBA_8888 彩色格式**，要求 `readonly pixelMap` / `{ pixelMap }` 包一层。
- **MindSpore Lite**：吃 `ArrayBuffer`。需要自己把 `PixelMap` 预处理成模型要的张量——官方示例做法是 `scale` → `crop` 到 224×224 → `readPixelsToBuffer()` 拿 RGBA → 手工归一化成 `Float32Array`（详见 6.2 代码）。

---

## 5. 首选方案 + 具体的可行性判断

### 5.1 首选方案（推荐组合）

```
拍照/选图 (cameraPicker / PhotoViewPicker)
        │
        ├─► 通路 A（主力，加分项）：MindSpore Lite + mobilenetv2.ms
        │      PixelMap → scale/crop 224×224 → Float32Array(RGB, 归一化)
        │      → mindSporeLite.predict() → 1000 维分数 → top-K 索引
        │      → 【标定表】索引 → 你们的 factorId → 置信度
        │
        └─► 通路 B（保底，稳）：Core Vision Kit OCR
               PixelMap → textRecognition.recognizeText() → 全文
               → 关键词规则匹配 → factorId → 置信度
        │
        ▼
   融合决策：两路都出结果就投票/取高置信；
   命中 → 表单预填 factorId + 显示「AI 建议」+ 置信度
   未命中 / 置信度低 → 不预填，提示用户手选
        │
        ▼
   用户在录入表单里「一键确认 / 改一下」→ 落库
```

**这个设计为什么能站住脚：**
1. **端侧**：两条通路都在本机推理，无网络调用；MindSpore Lite 跑本地 `.ms` 文件，**物理上没有上传通道**。
2. **离线**：模型文件打包进 `rawfile`，OCR 模型随系统预置。
3. **纯 ArkTS**：零 Native C++，零 CMake，符合「纯北向」。
4. **隐私故事硬**：可以现场**开飞行模式演示**，并展示「我们把模型文件打包进 App，11 MB，跟着安装包走」。
5. **失败可控**：通路 B 只有几十行代码，几乎不可能失败；通路 A 挂了，产品照常能用。

### 5.2 「能不能做」的判断标准（Go / No-Go 门槛）

**请严格按这个顺序做，每一关不过就立刻降级，不要恋战。**

| 门槛 | 内容 | 预算 | 通过标准 | 不过怎么办 |
|---|---|---|---|---|
| **G0** | **环境关卡**：① 确认手上有**华为 HarmonyOS 真机**；② 建 `entry/src/main/syscap.json`；③ 真机跑通「加载 `mobilenetv2.ms` → `predict` 返回非空 `MSTensor`」；④ 开飞行模式跑通 OCR | **0.5 天** | ①②必过；③④只要有一个过就继续 | ③④**全不过** → 环境/机型问题，**放弃通路 A 和 OCR，走第 7 节替代方案** |
| **G1** | **模型关卡**：用官方 `mobilenetv2.ms`，对你们自己拍的 **20 张**低碳行为照片，打印 top-5 输出**索引** | **1 天** | 在 14 类里，**≥ 8 类**能找到稳定的高置信索引（同一类目多张照片 top-5 里反复出现同一批索引） | < 8 类 → **放弃通路 A**，只做 OCR 通路 |
| **G2** | **OCR 关卡**：对同样 20 张照片跑 OCR，看关键词命中 | **0.5 天** | **≥ 6 类**能靠关键词唯一命中 | 命中太少 → 回到产品设计：把 AI 降级为「辅助提示」，或走 7.2 |
| **G3** | **集成关卡**：融合两路 + 预填表单 + 用户可改 | **1.5–2.5 天** | 录入流程端到端可用 | — |

**总投入 3.5–4.5 天**，与你们「3–5 天」的预算吻合。**任意一个门槛不过，就砍掉对应通路，产品仍然完整。**

### 5.3 关于「拿不到标签文件」怎么办 —— 标定表（这是本方案的关键技巧）

官方 `mobilenetv2.ms` 我**没能找到**配套的官方标签文件（见 8.1）。**不要卡在这里**，用工程办法绕过去：

> **不需要知道模型的 1000 个类名叫什么，只需要知道「哪些输出索引对应哪一类低碳行为」。**

做法（这正是 G1 要干的活）：
1. 每个类目拍 **2–3 张典型照片**（如「回收塑料」拍几个塑料瓶）；
2. 跑一次 `predict`，把 top-5 的**索引号**打出来；
3. 统计：如果「塑料瓶」这组照片反复在 index `A`、`B` 上给出高分，就把 `A`、`B` 记进「回收塑料（`recycle.plastic`）」；
4. 汇总成一张表（代码见 6.3 的 `INDEX_TO_FACTOR`），并把**没标定到的索引全部视作「无法判定」**。

**答辩话术**：「模型的原始类目空间是通用的（Open Images），我们在端侧做了一层**类目标定**，把它映射到本应用的 4 大类 14 个低碳行为，并只在高置信时预填，低置信交给用户确认——这样既保证体验，也避免 AI 误判污染用户的碳账本。」

这个说法**完全成立**，而且体现了你们真的懂工程取舍。

### 5.4 一句必要的实话：模型能力的天花板

基于对 MobileNetV2 + Open Images 常见类目的语义判断（**未实测**，属我的推断，非官方结论）：

| 类目 | 预期可识别度 | 说明 |
|---|---|---|
| 回收塑料 / 回收易拉罐 / 回收废纸 / 回收旧衣物 | 🟢 较好 | 瓶子、罐子、纸箱、衣服/鞋 这类物体在通用模型里通常有对应或近似类别 |
| 光盘行动 / 减少食物浪费 | 🟢 较好 | 餐盘、食物、餐桌场景特征明显 |
| 公交出行 | 🟡 中等 | 公交车是显著目标，可能有对应类 |
| 骑行 | 🟡 中等 | 自行车通常有对应类 |
| 地铁出行 | 🔴 较差 | 地铁车厢/站台不是通用类目；建议**靠 OCR 读站名/线路图** |
| 新能源车出行 | 🔴 差 | 通用模型**区分不了新能源车与燃油车**；建议靠 OCR（车牌/充电桩标识）或让用户手选 |
| 步行 | 🔴 差 | 通用分类器没有「人在走路」这一语义类别，只有「人」 |
| 节约用电 / 少开空调 / 节约用水 | 🔴 差 | 这三个是**行为/账单**语义，不是物体类别；**几乎只能靠 OCR 读电费水费单/空调面板** |

**结论：14 类里大约 6–8 类可依赖视觉模型，其余必须靠 OCR 或用户手选。所以「AI 预填 + 用户确认」不是妥协，而是这个问题的正确答案。**

---

## 6. 最小可运行代码骨架（ArkTS）

> 以下代码严格按**华为官方文档的示例**与**本机 SDK 的 `.d.ts` 签名**编写。标注 `// TODO(团队)` 的地方需要你们补。
> 目录按你们现有工程结构（`entry/src/main/ets/{model,data,view,...}`）安排。

### 6.1 【必做】`entry/src/main/syscap.json` —— 不加这个 MindSpore Lite 用不了

```json
{
  "devices": {
    "general": [
      "phone",
      "tablet",
      "2in1"
    ]
  },
  "development": {
    "addedSysCaps": [
      "SystemCapability.AI.MindSporeLite"
    ]
  }
}
```
- `general` 数组**必须与你们 `entry/src/main/module.json5` 里的 `deviceTypes` 完全一致**（你们现在是 `["phone","tablet","2in1"]`）。华为官方文档对此有明确要求。
- 位置：`entry/src/main/`（与 `module.json5` 同级）。

### 6.2 `entry/src/main/ets/ai/MindSporePredictor.ets` —— 模型加载 + 预处理 + 推理

```ts
/**
 * 端侧图像分类推理器（MindSpore Lite ArkTS）
 * 全离线：模型来自 resources/rawfile/mobilenetv2.ms，无任何网络调用。
 *
 * 官方参考：《使用 MindSpore Lite 实现图像分类 (ArkTS)》
 * 模型下载：https://download.mindspore.cn/model_zoo/official/lite/mobilenetv2_openimage_lite/1.5/mobilenetv2.ms
 */
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { image } from '@kit.ImageKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'MindSporePredictor';
const MODEL_NAME = 'mobilenetv2.ms';

/** 模型输入尺寸。TODO(团队)：若换模型，改成新模型的输入尺寸 */
const INPUT_W = 224;
const INPUT_H = 224;

/** 归一化参数。TODO(团队)：必须与模型训练时一致，否则结果全错 */
const MEANS = [0.485, 0.456, 0.406];
const STDS = [0.229, 0.224, 0.225];

let cachedModel: mindSporeLite.Model | undefined = undefined;

/** 从 rawfile 加载模型（只加载一次，常驻内存） */
async function ensureModel(mgr: resourceManager.ResourceManager): Promise<mindSporeLite.Model> {
  if (cachedModel !== undefined) {
    return cachedModel;
  }
  // 1. 读 rawfile
  const raw: Uint8Array = await mgr.getRawFileContent(MODEL_NAME);
  // 2. 创建上下文：CPU 推理，2 线程。本模型不支持 nnrt
  const context: mindSporeLite.Context = {};
  context.target = ['cpu'];
  context.cpu = {};
  context.cpu.threadNum = 2;
  context.cpu.threadAffinityMode = 1;
  context.cpu.precisionMode = 'enforce_fp32';
  // 3. 从内存加载
  cachedModel = await mindSporeLite.loadModelFromBuffer(raw.buffer.slice(0), context);
  hilog.info(0, TAG, 'model loaded');
  return cachedModel;
}

/**
 * PixelMap → 模型输入张量（Float32Array）
 * 流程与官方示例一致：等比缩放到 256 → 中心裁剪 224×224 → 读 RGBA → 归一化
 */
async function preprocess(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
  const info = await pixelMap.getImageInfo();
  const w = info.size.width;
  const h = info.size.height;
  // 缩放到短边 256（官方示例做法）
  await pixelMap.scale(256.0 / w, 256.0 / h);
  // 中心裁剪 224×224
  await pixelMap.crop({
    x: 16,
    y: 16,
    size: { width: INPUT_W, height: INPUT_H }
  });

  const rgba = new ArrayBuffer(INPUT_W * INPUT_H * 4);
  await pixelMap.readPixelsToBuffer(rgba);
  const u8 = new Uint8Array(rgba);

  // RGBA → 归一化浮点
  // TODO(团队)【高风险】：官方示例把分量注释成 B/G/R，但 PixelMap 读出来是 RGBA。
  //   请先用一张纯红色图跑一遍，确认模型要的是 RGB 还是 BGR、是 CHW 还是 NHWC。
  //   若 top-1 明显乱跳，八成就是这里错了。
  const out = new Float32Array(INPUT_W * INPUT_H * 3);
  let idx = 0;
  for (let i = 0; i < u8.length; i++) {
    if ((i + 1) % 4 === 0) {
      out[idx]     = (u8[i - 3] / 255.0 - MEANS[0]) / STDS[0]; // R
      out[idx + 1] = (u8[i - 2] / 255.0 - MEANS[1]) / STDS[1]; // G
      out[idx + 2] = (u8[i - 1] / 255.0 - MEANS[2]) / STDS[2]; // B
      idx += 3;
    }
  }
  return out.buffer;
}

/** 一条候选：类别索引 + 分数 */
export interface ClassScore {
  index: number;
  score: number;
}

/**
 * 端侧推理主入口
 * @returns top-K（按分数降序）。索引含义由标定表决定，见 CategoryMapping.ets
 */
export async function predictTopK(
  mgr: resourceManager.ResourceManager,
  pixelMap: image.PixelMap,
  k: number = 5
): Promise<ClassScore[]> {
  const model = await ensureModel(mgr);
  const inputBuffer = await preprocess(pixelMap);

  const inputs: mindSporeLite.MSTensor[] = model.getInputs();
  if (inputs.length < 1) {
    throw new Error('model has no input tensor');
  }
  inputs[0].setData(inputBuffer);

  const outputs: mindSporeLite.MSTensor[] = await model.predict(inputs);
  if (outputs.length < 1) {
    throw new Error('model returned no output');
  }
  const logits = new Float32Array(outputs[0].getData());

  // 取 top-K（模型输出已是概率/分数，未做 softmax；如需置信度请自行 softmax）
  const all: ClassScore[] = [];
  for (let i = 0; i < logits.length; i++) {
    all.push({ index: i, score: logits[i] });
  }
  all.sort((a, b) => b.score - a.score);
  return all.slice(0, k);
}

/** 打印模型输出维度 —— 首次接入时用它确认类别数 */
export async function debugOutputShape(
  mgr: resourceManager.ResourceManager,
  pixelMap: image.PixelMap
): Promise<string> {
  const model = await ensureModel(mgr);
  const inputBuffer = await preprocess(pixelMap);
  const inputs = model.getInputs();
  inputs[0].setData(inputBuffer);
  const outputs = await model.predict(inputs);
  return `input.shape=${JSON.stringify(inputs[0].shape)} dtype=${inputs[0].dtype} ` +
         `output.shape=${JSON.stringify(outputs[0].shape)} output.len=${outputs[0].elementNum}`;
}
```

### 6.3 `entry/src/main/ets/ai/CategoryMapping.ets` —— 索引标定表 + OCR 关键词规则

```ts
/**
 * 端侧识别的「业务翻译层」：
 *   1) 视觉模型的输出索引 → 你们 14 个 factorId（标定表）
 *   2) OCR 文本 → factorId（关键词规则）
 *
 * factorId 全部来自 data/FactorLibrary.ets，请勿改动拼写。
 */

export interface AiSuggestion {
  factorId: string;
  /** 0~1，AI 对该建议的把握 */
  confidence: number;
  /** 依据，用于 UI 展示和答辩演示 */
  reason: string;
  /** 来源通路 */
  source: 'vision' | 'ocr' | 'none';
}

/** 无结果时的返回值 */
export const NO_SUGGESTION: AiSuggestion = {
  factorId: '', confidence: 0, reason: '未能识别，请手动选择', source: 'none'
};

/* ------------------------------------------------------------------ *
 * 1) 视觉模型：输出索引 → factorId
 *
 * ⚠️ TODO(团队)【必须在 G1 门槛里填】：
 *    下表是**空表**，不是猜的。请按 5.3 的方法，
 *    用你们自己拍的照片跑 predictTopK()，把反复出现的高分索引填进来。
 *    一张索引可以被多个 factorId 引用（分数接近时靠 score 排序）。
 *    没填进来的索引 = 不识别。
 * ------------------------------------------------------------------ */
export const INDEX_TO_FACTOR: Record<number, string> = {
  // 示例（**请替换为你们实测出的真实索引**）：
  // 440: 'recycle.plastic',
  // 720: 'travel.bus',
  // 301: 'recycle.cloth',
};

/** 视觉通路：把 top-K 变成建议 */
export function suggestFromVision(topK: Array<{ index: number; score: number }>): AiSuggestion {
  for (const item of topK) {
    const factorId = INDEX_TO_FACTOR[item.index];
    if (factorId !== undefined && factorId !== '') {
      return {
        factorId,
        // 注意：模型输出不是归一化概率，这里只是相对把握，仅用于「是否值得预填」
        confidence: Math.max(0, Math.min(1, item.score)),
        reason: `端侧模型识别到「${factorId}」（索引 ${item.index}，得分 ${item.score.toFixed(3)}）`,
        source: 'vision'
      };
    }
  }
  return NO_SUGGESTION;
}

/* ------------------------------------------------------------------ *
 * 2) OCR 通路：关键词 → factorId
 *
 * 规则按「先具体后宽泛」匹配，命中即返回。
 * 关键词可自由扩充，改这里不用重新编译模型，非常适合快速迭代。
 * ------------------------------------------------------------------ */
interface KeywordRule {
  keywords: string[];
  factorId: string;
}

export const OCR_RULES: KeywordRule[] = [
  // —— 出行 ——
  { keywords: ['地铁', '轨道交通', 'metro', 'subway', '号线', '乘车码'], factorId: 'travel.metro' },
  { keywords: ['公交', '巴士', 'bus', '公交站', '快速公交', 'BRT'], factorId: 'travel.bus' },
  { keywords: ['共享单车', '骑行', '自行车', '哈啰', '美团单车', '青桔'], factorId: 'travel.bike' },
  { keywords: ['新能源汽车', '充电桩', '电动车充电', '国网电动'], factorId: 'travel.nev' },
  { keywords: ['步数', '健走', '步行', '万步'], factorId: 'travel.walk' },
  // —— 节水节电 ——
  { keywords: ['电费', '用电量', '千瓦时', 'kWh', '度电', '国网', '电表'], factorId: 'energy.power' },
  { keywords: ['水费', '用水量', '立方米', '吨水', '水表'], factorId: 'energy.water' },
  { keywords: ['空调', '制冷', '26℃', '温度设定'], factorId: 'energy.ac' },
  // —— 旧物回收 ——
  { keywords: ['可回收物', '回收塑料', '塑料瓶', 'PET', '饮料瓶'], factorId: 'recycle.plastic' },
  { keywords: ['废纸', '纸箱', '报纸', '纸类回收', '纸板'], factorId: 'recycle.paper' },
  { keywords: ['易拉罐', '铝罐', '金属回收', '铝制品', '罐'], factorId: 'recycle.can' },
  { keywords: ['旧衣物', '旧衣服', '纺织', '织物回收', '捐衣'], factorId: 'recycle.cloth' },
  // —— 光盘行动 ——
  { keywords: ['光盘行动', '光盘', '剩菜打包', '打包盒'], factorId: 'food.cleanplate' },
  { keywords: ['食物浪费', '厨余', '按需点餐', '小份菜'], factorId: 'food.waste' }
];

/** OCR 文本 → 建议。命中多条时取最先匹配（规则表已按具体度排序） */
export function suggestFromOcr(text: string): AiSuggestion {
  if (text === undefined || text === null || text.length === 0) {
    return NO_SUGGESTION;
  }
  const lower = text.toLowerCase();
  for (const rule of OCR_RULES) {
    for (const kw of rule.keywords) {
      if (lower.includes(kw.toLowerCase())) {
        return {
          factorId: rule.factorId,
          confidence: 0.75, // 关键词命中给固定中等置信度
          reason: `识别到文字「${kw}」`,
          source: 'ocr'
        };
      }
    }
  }
  return NO_SUGGESTION;
}

/** 两路融合：谁置信度高用谁；同 factorId 则加成 */
export function fuse(vision: AiSuggestion, ocr: AiSuggestion): AiSuggestion {
  if (vision.factorId === '' && ocr.factorId === '') {
    return NO_SUGGESTION;
  }
  if (vision.factorId === '') {
    return ocr;
  }
  if (ocr.factorId === '') {
    return vision;
  }
  if (vision.factorId === ocr.factorId) {
    return {
      factorId: vision.factorId,
      confidence: Math.min(1, vision.confidence + ocr.confidence * 0.5),
      reason: `图像与文字双路一致：${vision.reason}；${ocr.reason}`,
      source: 'vision'
    };
  }
  // 两路冲突：取置信度高者，但降低置信度（提示用户确认）
  const winner = vision.confidence >= ocr.confidence ? vision : ocr;
  return {
    factorId: winner.factorId,
    confidence: winner.confidence * 0.6,
    reason: `图像与文字结果不一致，倾向：${winner.reason}`,
    source: winner.source
  };
}
```

### 6.4 `entry/src/main/ets/ai/LowCarbonClassifier.ets` —— 统一门面（拍照/选图 → 识别 → 结果）

```ts
/**
 * 端侧 AI 识别的统一入口。
 * 全程离线：不发起任何网络请求，图片不会离开设备。
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { cameraPicker } from '@kit.CameraKit';
import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { predictTopK } from './MindSporePredictor';
import { AiSuggestion, fuse, NO_SUGGESTION, suggestFromOcr, suggestFromVision } from './CategoryMapping';

const TAG = 'LowCarbonClassifier';

/** 1. 从相册选一张图，返回 PixelMap */
export async function pickFromGallery(): Promise<image.PixelMap | undefined> {
  const options = new photoAccessHelper.PhotoSelectOptions();
  options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
  options.maxSelectNumber = 1;
  const picker = new photoAccessHelper.PhotoViewPicker();
  const result = await picker.select(options);
  if (result.photoUris === undefined || result.photoUris.length === 0) {
    return undefined;
  }
  return uriToPixelMap(result.photoUris[0]);
}

/** 1b. 调系统相机拍一张，返回 PixelMap */
export async function takePhoto(context: common.UIAbilityContext): Promise<image.PixelMap | undefined> {
  const profile: cameraPicker.PickerProfile = {
    cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
  };
  const result = await cameraPicker.pick(
    context,
    [cameraPicker.PickerMediaType.PHOTO],
    profile
  );
  if (result.resultCode !== 0 || result.resultUri === undefined || result.resultUri === '') {
    return undefined;
  }
  return uriToPixelMap(result.resultUri);
}

/** URI → PixelMap（Core Vision Kit 与 MindSpore Lite 的公共输入） */
async function uriToPixelMap(uri: string): Promise<image.PixelMap | undefined> {
  try {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    const source = image.createImageSource(file.fd);
    const pixelMap = await source.createPixelMap();
    await fileIo.close(file);
    return pixelMap;
  } catch (e) {
    hilog.error(0, TAG, `uriToPixelMap failed: ${JSON.stringify(e)}`);
    return undefined;
  }
}

/** 2. OCR 通路 */
async function ocrRecognize(pixelMap: image.PixelMap): Promise<string> {
  try {
    const info: textRecognition.VisionInfo = { pixelMap: pixelMap };
    const config: textRecognition.TextRecognitionConfiguration = {
      isDirectionDetectionSupported: false
    };
    const res = await textRecognition.recognizeText(info, config);
    return res.value;
  } catch (e) {
    hilog.error(0, TAG, `ocr failed: ${JSON.stringify(e)}`);
    return '';
  }
}

/**
 * 3. 端到端：PixelMap → AI 建议
 * @param mgr  resourceManager，用于读 rawfile 里的 .ms 模型
 */
export async function classify(
  mgr: resourceManager.ResourceManager,
  pixelMap: image.PixelMap
): Promise<AiSuggestion> {
  // 通路 A：视觉模型（失败不影响整体）
  let vision: AiSuggestion = NO_SUGGESTION;
  try {
    const topK = await predictTopK(mgr, pixelMap, 5);
    vision = suggestFromVision(topK);
  } catch (e) {
    hilog.warn(0, TAG, `vision path unavailable: ${JSON.stringify(e)}`);
  }

  // 通路 B：OCR（失败不影响整体）
  const text = await ocrRecognize(pixelMap);
  const ocr = suggestFromOcr(text);

  return fuse(vision, ocr);
}
```

### 6.5 在录入页里用（UI 片段）

```ts
// 在你们的录入页（view/ 或 pages/）里
import { classify, pickFromGallery, takePhoto } from '../ai/LowCarbonClassifier';
import { AiSuggestion } from '../ai/CategoryMapping';

@State aiSuggestion: AiSuggestion = { factorId: '', confidence: 0, reason: '尚未识别', source: 'none' };
@State previewPixelMap: PixelMap | undefined = undefined;

// 选图 → 识别 → 预填
async doAiRecognize(): Promise<void> {
  const pm = await pickFromGallery();
  if (pm === undefined) {
    return;
  }
  this.previewPixelMap = pm;
  // 官方要求：OCR 使用前 init()，页面销毁时 release()
  await textRecognition.init();
  const mgr = this.getUIContext()?.getHostContext()?.getApplicationContext().resourceManager;
  if (mgr === null || mgr === undefined) {
    return;
  }
  this.aiSuggestion = await classify(mgr, pm);

  // 关键产品设计：高置信才预填，低置信交给用户
  if (this.aiSuggestion.confidence >= 0.5 && this.aiSuggestion.factorId !== '') {
    this.selectedFactorId = this.aiSuggestion.factorId; // ← 你们表单里绑定 factorId 的状态变量
  }
}

// UI 上一定要展示 reason，这是答辩时最好讲的部分
// Text(`AI 建议：${this.aiSuggestion.reason}（把握 ${(this.aiSuggestion.confidence * 100).toFixed(0)}%）`)
```

### 6.6 需要团队自己补的清单

| # | 事项 | 在哪 | 为什么 |
|---|---|---|---|
| 1 | **`syscap.json`** | `entry/src/main/syscap.json` | 不加 MindSpore Lite 用不了（6.1） |
| 2 | **下载 `mobilenetv2.ms` 放进工程** | `entry/src/main/resources/rawfile/` | 官方链接见 4.2；约 11 MB，注意安装包体积 |
| 3 | **确认模型输入 layout 与通道序** | `MindSporePredictor.preprocess()` | 官方示例注释与 PixelMap 的 RGBA 顺序存在矛盾，**这是最容易白干一天的地方**，先做做 6.7 的自检 |
| 4 | **填 `INDEX_TO_FACTOR` 标定表** | `CategoryMapping.ets` | 我没有官方标签文件，**只有你们实测才能填**（5.3） |
| 5 | **扩充 `OCR_RULES` 关键词** | `CategoryMapping.ets` | 结合你们演示用的真实照片反复调 |
| 6 | **接入你们真实的 `resourceManager`** | `LowCarbonClassifier.ets` | 示例里用 `getUIContext()?.getHostContext()?.getApplicationContext().resourceManager` 取，路径与你们工程一致即可 |
| 7 | **`textRecognition.release()`** | 页面 `aboutToDisappear` | 官方要求成对调用，否则占资源 |
| 8 | **UI 文件里导入 `image`** | 录入页 | 用到 `PixelMap` 类型时记得 `import { image } from '@kit.ImageKit'` |
| 9 | **`oh-package.json5` 无需新增依赖** | — | CoreVisionKit / MindSporeLiteKit / MediaLibraryKit / CameraKit 都是系统 Kit，不需要 `dependencies` |

### 6.7 半天就能做完的自检脚本（强烈建议先做这个）

在写业务逻辑之前，先用它把「模型到底能不能用」钉死：

```ts
// 在一张**纯红色**图片上跑，检查通道序；
// 再用 3 张典型照片跑，把索引和分数 print 出来。
const topK = await predictTopK(mgr, pixelMap, 10);
for (const s of topK) {
  hilog.info(0, TAG, `idx=${s.index} score=${s.score.toFixed(4)}`);
}
// 另外调一次 debugOutputShape()，确认输出维度（也就是类别数）
```
- 如果 top-1 在不同照片之间**毫无区分度**（每次都是同一批索引）→ 通道序或归一化参数错了。
- 如果像「塑料瓶」「餐盘」这种明显物体**能稳定聚到某几个索引** → 通路 A 成立，继续做 G1。

---

## 7. 如果方案 A 过不了门槛：替代方案

**先说结论：即使 MindSpore Lite 完全不工作，你们依然可以保留「端侧 AI 图片识别」这个创新点**，因为 Core Vision Kit OCR 本身就是端侧 AI（一个 CV 深度模型）。以下按推荐度排序。

### 7.1 方案 B（强烈推荐，最稳）：端侧 OCR + 关键词 + 端侧中文 NLP

**做什么**：拍照/选图 → `textRecognition.recognizeText()` → 全文 → 关键词/正则规则 → 预填 + 用户确认。

**为什么算「端侧 AI」**：OCR 是一个在设备上运行的深度神经网络（检测 + 识别两个模型），输入 `PixelMap`、输出文本，全程无网络。这是货真价实的端侧 AI，不是文字游戏。

**加分升级**：叠加 `@kit.NaturalLanguageKit` 的端侧 NLP（`@since 5.0.0(12)`）：
```ts
import { textProcessing } from '@kit.NaturalLanguageKit';
const segments = await textProcessing.getWordSegment(ocrText); // 中文分词
const entities = await textProcessing.getEntity(ocrText);      // 实体识别
```
用「端侧 OCR + 端侧分词 + 规则」三层，答辩时讲成**「多级端侧 AI 流水线」**，比单模型更有层次感，而且**每一层都可当场演示、可解释**。

**工期**：0.5–1 天。**风险**：几乎为零。

**唯一约束**：演示照片里得有文字。**这一条你们完全可以主动设计演示脚本**——准备一组必定带字的照片（地铁站牌、公交站牌、回收箱标识、餐盘小票、电费单）。这是**合理的产品定位**（这些场景本来就是低碳行为的凭证），不是造假。

### 7.2 方案 C（并列备选）：主体分割 + 规则 + 「是否拍到有效主体」的校验

`subjectSegmentation.doSegmentation()`（`@since 5.0.0(12)`）能给出显著主体 + 掩膜 + 包围盒，但**没有类别**。可用它做两件事：
1. **有效性校验**：「你这张图里没有明显主体，请重拍/靠近一点」——作为 AI 体验的一环，很讨喜；
2. **辅助裁剪**：把主体抠出来再喂给 OCR，提高 OCR 命中率（对杂乱背景的照片有效）。

⚠️ 但官方文档明确「**不建议用于处理包含较多文字内容的图片分析场景**」，所以它更适合做 OCR 的前置，而不是替代分类。**单独用不够，作为方案 B 的增强项最合适。**

### 7.3 方案 D：端侧 AI 语音输入（换一个「端侧 AI」卖点）

用 `@kit.CoreSpeechKit` 的端侧语音识别（`speechRecognizer`，SDK 实测 `@since 4.1.0(11)`、syscap `SystemCapability.AI.SpeechRecognizer`）：

> 用户按住说话：「今天坐地铁上班」→ 端侧 ASR → 文本 → 同一套关键词规则 → 预填。

**优点**：纯端侧、离线、演示效果比拍照更抓人（现场说话就出结果）。
**缺点**：`speechRecognizer` 需要 `createEngine` 指定引擎，**「是否完全离线」我没能确认**（部分厂商语音引擎走云侧），见 8.5。若要用，**必须先开飞行模式实测**。
**工期**：1–1.5 天。

### 7.4 不建议的替代路径

| 路径 | 为什么不做 |
|---|---|
| 云端 API 识别（各种云厂商图像识别） | ❌ 直接违反硬性约束 1、2；路演断网就废 |
| HiAI Foundation / CANNKit（Native） | ❌ 纯 C++ + 要自己转 `.om` 模型，5 周项目里不值当 |
| 自己训练 14 类模型 | ❌ 数据采集+标注+训练+转换，3–5 天绝对不够 |
| `visionImageAnalyzer` UI 控件 | ❌ 是挂在 Image 上的 UI 控件，不是无头 API；`startObjectSearch` 疑似云侧 |
| 用手机传感器（计步）冒充 AI 识别 | ⚠️ 不算图像识别，答辩容易被问穿，不建议 |

---

## 8. 【未确认】清单

**以下内容我没有核实到，请不要当成事实使用。** 每一条都给了验证方法。

| # | 未确认事项 | 我的依据 / 为什么没确认 | 怎么验证 |
|---|---|---|---|
| **8.1** | **`mobilenetv2.ms` 的确切类别数与官方标签文件** | 我在 `download.mindspore.cn`（`1.5/`、`1.1/`）、`mindspore/mindspore`、`mindspore/models`、`mindspore/mindspore-lite` 仓库中**均未找到**标签文件；模型二进制里也**没有内嵌类名**（`strings` 扫描过）。**只知道名字里带 `openimage`，推测基于 Open Images，但类别数是 1000 还是其他，未确认。** | 跑 `debugOutputShape()`（见 6.2）打印 `outputs[0].elementNum`，即类别数；或按 5.3 用标定表绕开 |
| **8.2** | **Core Vision Kit（OCR/目标检测/主体分割）是否 100% 不联网** | 官方文档**没有**显式写「端侧/离线/数据不出端」。我的判断来自：输入只有 `PixelMap`、无网络参数、模型下载接口被标为 `reserved and is not supported`。**属强推断，非官方明文。** | **开飞行模式**在真机上跑 OCR，能出结果即证明不依赖网络。（建议答辩前必做，这也是最好的答辩素材） |
| **8.3** | **MindSpore Lite ArkTS 在 HarmonyOS 真机（华为手机）上的实测可用性** | `syscap-version.json` 把 `SystemCapability.AI.MindSporeLite` 标为 `OS=OpenHarmony`；官方 ArkTS Demo 自己写 `runtimeOS: OpenHarmony` / `compatibleSdkVersion 11` /「支持设备：RK3568」。虽然华为 HarmonyOS 文档给了 `syscap.json` 的解法（说明官方认可可用），但**我没能在真机上验证**。 | 按 G0 门槛做：加 `syscap.json`，在**华为真机**上跑 `loadModelFromBuffer` + `predict`。另可用 `canIUse('SystemCapability.AI.MindSporeLite')` 打印结果 |
| **8.4** | **模型输入的通道序（RGB/BGR）与 layout（CHW/NHWC）** | 官方 ArkTS 示例把分量注释为 `B/G/R`，但 `PixelMap.readPixelsToBuffer()` 读出的顺序是 RGBA。**两者矛盾，我无法从文档判定哪个对。** | 6.7 的自检：纯红图 + 多张典型图看索引是否稳定 |
| **8.5** | **`speechRecognizer` 是否完全离线** | SDK 只给了 `createEngine` 签名，**没有说明引擎是本机还是云侧**；部分华为语音能力走云。 | 飞行模式下实测 ASR 能否出结果 |
| **8.6** | **你们比赛现场用的具体机型与 HarmonyOS 版本** | 这直接决定 Core Vision Kit / MindSpore Lite 是否可用（Core Vision Kit 仅在**华为 HarmonyOS 真机**上有，且官方称**不支持模拟器**、仅中国境内）。 | 赛前确认机型，并**带备用机 + 录屏兜底** |
| **8.7** | **`mobilenetv2.ms` 是否含 NPU/NNRt 优化、是否静态 Shape** | 官方示例注释说「本模型不支持其他 shape resize」、`context.target=['cpu']`，但这不等于我确认了它的图结构。 | 试 `context.target=['nnrt']`，失败就老实用 CPU |
| **8.8** | 模型对你们 14 类的**实际识别效果** | 5.4 那张表是我**基于类目语义的推断，完全没有实测**。 | G1 门槛：20 张自拍照片跑 top-5 |
| **8.9** | 文档/SDK 版本时效性 | 本文基于**本机 HarmonyOS 26.0.0 / API 26 SDK** 与**华为文档 V241（2026-09-23 更新）**。你们若换机器或升级 SDK，结论需复核。 | 重新核对 `sdk-pkg.json` 与官方文档 |

**已确认、不需怀疑的（供反向对照）**：
- ✅ `textRecognition` `@since 4.0.0(10)`、`init/release` `@since 5.0.0(12)`、`objectDetection`/`subjectSegmentation`/`visionBase` `@since 5.0.0(12)`、`mindSporeLite` 核心 API `@since 10` → **全部 ≤ API 12，`compatibleSdkVersion 5.0.0(12)` 可用**。
- ✅ `textSearchImage` 与 `imageSuperResolution` **`@since 26.0.0`**，**API 12 上不可用**（要升 `compatibleSdkVersion` 才行，但那会违反赛题「API 12 及以上」的下限要求反而没问题——只是没必要）。
- ✅ HarmonyOS SDK **没有**通用图像分类 API。
- ✅ `objectDetection` 的 18 个标签就是上面列的那些，没有更多。
- ✅ `cameraPicker` `@since 11`，可用；必须在 UIAbility 内调用。
- ✅ HiAI Foundation / CANNKit **只有 Native C API**。
- ✅ 官方 `mobilenetv2.ms` 下载链接可用，11,447,840 字节，魔数 `MSL2`。

---

## 9. 参考链接（均为我实际抓取/核对过的来源）

**官方文档（华为，文档版本 V241，更新至 2026-09-23）**
- [Core Vision Kit 简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-introduction) — 能力清单、约束与限制、不支持模拟器
- [通用文字识别](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-text-recognition) — OCR 完整 ArkTS 示例
- [多目标识别](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-object-detection) — `objectDetection` 示例
- [主体分割](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-subject-segmentation) — `subjectSegmentation` 示例
- [MindSpore Lite Kit 简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/mindspore-lite-kit-introduction) — 「HarmonyOS 内置的轻量化 AI 引擎」、`.ms`、设备支持
- [使用 MindSpore Lite 实现图像分类 (ArkTS)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/mindspore-guidelines-based-js) — **含 `syscap.json` 要求、完整预处理与推理代码**
- [使用 MindSpore Lite 进行模型转换](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/mindspore-lite-converter-guidelines) — `converter_lite` 参数、Linux x86_64、PyTorch 限制
- [MindSpore Lite Kit 附录](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/mindspore-lite-appendix)

**官方模型与示例代码**
- 模型下载：`https://download.mindspore.cn/model_zoo/official/lite/mobilenetv2_openimage_lite/1.5/mobilenetv2.ms`（实测 11,447,840 B，`MSL2`）
- ArkTS 官方 Demo：[applications_app_samples / MindSporeLiteArkTSDemo](https://gitee.com/openharmony/applications_app_samples/tree/master/code/DocsSample/ApplicationModels/MindSporeLiteArkTSDemo)
- C/C++ 官方 Demo：`applications_app_samples / code/DocsSample/ApplicationModels/MindSporeLiteCDemo`

**本机 SDK（最权威，建议团队直接自己查一遍）**
- 根目录：`/Applications/DevEco-Studio.app/Contents/sdk/default`
- 版本：`sdk-pkg.json` → `apiVersion: 26`, `displayName: HarmonyOS 26.0.0`
- 关键声明文件：
  - `hms/ets/kits/@kit.CoreVisionKit.d.ts`
  - `hms/ets/api/@hms.ai.ocr.textRecognition.d.ts`
  - `hms/ets/api/@hms.ai.vision.objectDetection.d.ts` / `.subjectSegmentation.d.ts` / `.visionBase.d.ts`
  - `openharmony/ets/kits/@kit.MindSporeLiteKit.d.ts`
  - `openharmony/ets/api/@ohos.ai.mindSporeLite.d.ts`
  - `hms/ets/api/device-define/{phone.json, phone-hmos.json, syscap-version.json}` ← 3. 节 OpenHarmony/HarmonyOS 差异的依据

**查文档的小技巧（本机可复现）**：华为文档站是 Angular SPA，直接 `curl` 只能拿到空壳。正文通过这个接口取：
```bash
curl -s -X POST \
  "https://svc-drcn.developer.huawei.com/community/servlet/consumer/cn/documentPortal/getDocumentById" \
  -H "Content-Type: application/json" \
  -d '{"objectId":"mindspore-guidelines-based-js","language":"cn"}'
```
把 `objectId` 换成 URL 最后一段即可。

---

## 10. 给团队的行动清单（照着做就行）

**Day 1（G0 + 启动）**
1. 确认手上有**华为 HarmonyOS 真机**（模拟器跑不了 Core Vision Kit）。
2. 建 `entry/src/main/syscap.json`（6.1，`general` 要与 `module.json5` 的 `deviceTypes` 一致）。
3. 下载 `mobilenetv2.ms` 放进 `entry/src/main/resources/rawfile/`。
4. 抄 6.2 的 `MindSporePredictor.ets`，用 6.7 的自检脚本跑通 `predict` 并确认输出维度。
5. **开飞行模式**跑一遍 OCR，确认离线可用（顺便录屏，答辩素材）。
6. 同时写 6.3 的 OCR 通路（半天，不要等模型）。

**Day 2（G1 + G2）**
7. 拍 20 张典型照片，跑 top-10，填 `INDEX_TO_FACTOR` 标定表。
8. 用同样 20 张跑 OCR，调 `OCR_RULES` 关键词。
9. **判门槛**：视觉 ≥8 类 / OCR ≥6 类？不达标就砍掉对应通路。

**Day 3–4（G3 集成）**
10. 写 `LowCarbonClassifier.ets` 门面 + 录入页「AI 预填 + 一键确认」。
11. UI 上**务必显示 `reason`**（「识别到文字『可回收物·塑料』」）——这是答辩最亮的部分。
12. 记得 `textRecognition.release()`。

**Day 5（收尾）**
13. 准备演示脚本：**飞行模式 + 一组必定命中的照片**。
14. 量化指标：**AI 预填命中率 / 人工修正率**（别吹「准确率」）。
15. 准备一句兜底话术：「端侧 AI 在本项目是**预填加速**能力，不参与碳核算，用户确认后才落库——保证碳账本准确性的同时把录入从 6 步降到 2 步。」
