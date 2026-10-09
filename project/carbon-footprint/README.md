# 碳迹 —— 碳足迹记录与减排指南

第三届河南省高等学校信息技术应用创新大赛 · **赛题二**（本科组）
赛题全称：碳足迹·全民绿色生活碳积分与减排指南

---

## 一、赛题要求 ↔ 代码位置对照

> **验证状态说明**：✅ 已在 HarmonyOS 7 模拟器上实测通过（本地签名 + hdc 安装运行）；
> 🟡 代码就绪但**需要真机**才能验证。

| 赛题要求 | 状态 | 代码位置 |
|---|---|---|
| **主要功能 1** 低碳行为核算 | ✅ 实测通过 | `view/EntryPage.ets`（录入）<br>`data/CarbonRepository.ets`（存储与计算）<br>`data/FactorLibrary.ets`（因子库） |
| **主要功能 2** 数据可视化看板 | ✅ 实测通过 | `view/DashboardPage.ets`（日/周/月/年切换）<br>`view/Charts.ets`（折线/柱状/饼图） |
| **主要功能 3** 碳积分激励体系 | ✅ 实测通过 | `view/PointsPage.ets`（积分、兑换、流水）<br>`data/CarbonRepository.ets` 的 `addPoints` |
| **主要功能 4** 双碳科普专栏 | ✅ 实测通过 | `view/KnowledgePage.ets` + `data/KnowledgeBase.ets`（8 篇，可标签筛选） |
| **主要功能 5** 本地数据管理 | ✅ 实测通过 | `view/ProfilePage.ets`（备份 / 报表导出）<br>`data/CarbonRepository.ets` 的 `backupJson` / `backupCsv` |
| **创新拓展 1** 超级终端多设备同步 | 🟡 需两台真机 | `common/DistributedStore.ets`（复用组件）<br>`view/ProfilePage.ets` 的同步状态面板 |
| **创新拓展 2** 端侧 AI 图片识别 | ✅ **推理链路已实测通过**（识别类目待真机标定） | `ai/MindSporePredictor.ets`（端侧推理）<br>`ai/CategoryMapping.ets`（标定表 + OCR 规则）<br>`ai/LowCarbonClassifier.ets`（统一门面）<br>`ai/AiSelfCheck.ets`（自检工具）<br>模型：`resources/rawfile/mobilenetv2.ms` |
| **创新拓展 3** 模拟城市碳普惠接口 | ✅ 实测通过 | `data/CarbonInclusiveApi.ets`（账户/上报/权益/兑换/订单）<br>`view/PointsPage.ets` 的碳普惠专区 |
| **创新拓展 4** 智能服务与社交分享 | ✅ 实测通过 | `data/TaskEngine.ets`（任务推荐 + 生活建议）<br>`view/SmartService.ets`（分享卡 + 截图 + 存相册）<br>`view/DashboardPage.ets` 底部区块 |
| **鸿蒙特色 · 桌面服务卡片** | ✅ **已实测渲染**（万能卡片） | `cardentry/CarbonCardAbility.ets`（卡片数据服务）<br>`cardentry/pages/CarbonCard.ets`（卡片 UI）<br>`resources/base/profile/form_config.json`（三种尺寸） |

> **桌面卡片是本作品最有辨识度的鸿蒙特色**：用户不必打开应用，桌面上就能看到
> 今日减排量、碳积分、近 7 日迷你趋势与智能提示；点卡片直接进入应用。
> 已实测：长按图标出现「卡片」入口、卡片正确渲染实时数据（2.35 kg / 235 积分）。
>
> **端侧 AI 推理链路已在 HarmonyOS 7 模拟器上实测跑通**：
> 模型 11.4 MB 加载成功，输入 `[1,224,224,3]`（NHWC / RGB），
> 输出 `[1,500]`，Top-5 分数区分度明显。标定步骤见工作区《端侧AI_标定指南.md》。

---

## 二、目录结构

```
carbon-footprint/
├── AppScope/                         应用级配置（bundleName、应用名、图标）
├── entry/src/main/
│   ├── module.json5                  模块配置 + 权限声明（DISTRIBUTED_DATASYNC）
│   └── ets/
│       ├── entryability/             应用入口 Ability
│       ├── common/
│       │   └── DistributedStore.ets  ★ 可复用的分布式 KV 封装（637 行，勿改）
│       ├── model/
│       │   └── Models.ets            领域模型：Factor / BehaviorRecord / PointsEntry / Profile
│       ├── data/
│       │   ├── FactorLibrary.ets     ★ 碳排放因子库（14 条，全部标注权威出处）
│       │   ├── CarbonRepository.ets  ★ 仓储层：建在 DistributedStore 的 KV 之上
│       │   ├── CarbonInclusiveApi.ets  创新点 3：模拟城市碳普惠平台接口
│       │   ├── TaskEngine.ets          创新点 4：任务推荐 + 生活建议（纯函数，可测）
│       │   └── KnowledgeBase.ets       科普内容库（8 篇，内容负责人可直接编辑）
│       ├── pages/
│       │   └── Index.ets             主入口：初始化数据层 + 五个页签
│       └── view/
│           ├── EntryPage.ets         记一笔
│           ├── DashboardPage.ets     看板
│           ├── Charts.ets            图表组件（mpchart 封装：折线/柱状/饼）
│           ├── PointsPage.ets        积分（含碳普惠专区）
│           ├── KnowledgePage.ets     科普（支持标签筛选）
│           ├── SmartService.ets      创新点 4：今日任务 / 建议 / 分享图
│           └── ProfilePage.ets       我的（含同步面板、数据管理）
└── oh-package.json5                  依赖：@ohos/mpchart（图表库）
```

工作区根目录另有配套工程脚本：

| 脚本 | 用途 |
|---|---|
| `tools/build.sh` | 同步源码 + 编译（约 3 秒） |
| `tools/sign.sh` | 本地签名，产出可安装的 HAP（**不需要 DevEco 图形界面**） |
| `tools/emulator.sh` | 模拟器镜像下载 / 建实例 / 启动 / 装应用（纯命令行） |
| `tools/test-logic.sh` | 纯逻辑单元测试（40 项断言，不需要设备） |
| `tools/icon/make_icons.py` | 生成应用图标 |

---

## 三、关键技术决策

### 1. 数据层建在 KV 上，不用 relationalStore

原因：创新拓展 1 要直接复用 `DistributedStore`，而它建在 **distributedKVStore** 上，与关系型库不通用。若用 `relationalStore`，接同步时数据层需整体重写。

键设计（store 已带 `carbon:` 前缀）：

| 键 | 值 |
|---|---|
| `behavior:<id>` | `BehaviorRecord` JSON |
| `points:<id>` | `PointsEntry` JSON（只增不改，天然免冲突） |
| `profile` | `Profile` JSON（单例） |

### 2. 图表用 `@ohos/mpchart`（OpenHarmony-TPC 官方库）

选型调研见工作区 `图表方案选型调研.md`，**务必先读该文档开头的「勘误」一节**——报告里 `rgb` 的用法有误，实测已更正。

三个必须遵守的约束：
1. 数据集合用 `JArrayList`，不是 `Array`
2. **换数据不能重新赋值 model**，必须 `setData()` → `notifyDataSetChanged()` → `invalidate()`
3. 颜色有两个 `rgb`：`ChartColor.rgb(r,g,b)` 收 3 个数字，`ColorTemplate.rgb(hex)` 收 1 个字符串

### 3. ⚠️ 工程必须放在纯英文路径

工作区路径含中文，hvigor 会**硬性拒绝构建**。所以：
- **源码正本**：工作区 `project/carbon-footprint/`
- **构建/运行目录**：`~/DevEcoStudioProjects/carbon-footprint`（纯英文）

用工作区的 `tools/build.sh` 一键同步 + 编译，不要直接在工作区里构建。

---

## 四、构建与运行

```bash
# 在工作区根目录执行：同步源码 + 编译
./tools/build.sh

# 只同步不编译
./tools/deploy.sh
```

然后在 DevEco Studio 里打开 `~/DevEcoStudioProjects/carbon-footprint`：

1. `File → Project Structure → Signing Configs` → 勾选 **Automatically generate signature**（需已登录华为开发者账号）
2. 确认设备：`hdc list targets` 应能看到设备
3. 点击 **Run**

---

## 五、⚠️ 交付前必须处理的事项

### 1. 碳排放因子数据待核对

`data/FactorLibrary.ets` 里标记为 **[B] 待核对** 的 6 条因子（回收类 4 条、光盘行动 2 条）**数值必须查证原始文件后确认**。文件头注释里列了具体是哪几条。答辩时因子来源会被追问，数值说不清出处比没有这个条目更糟。

标记为 **[A]** 的 8 条已有明确权威来源，可直接使用。

### 2. 运行验证尚未完成

当前状态：**编译通过，但从未在真机或模拟器上运行过。**

- 本机 `hdc list targets` 为空，无真机
- 模拟器镜像未下载
- 因此以下都存在运行时风险，必须在设备上实测：
  - mpchart 图表能否正常渲染（「编译通过」≠「渲染正确」）
  - distributedKVStore 读写是否正常
  - 权限弹窗、文件导出是否可用

### 3. 签名尚未配置

`build-profile.json5` 中 `signingConfigs: []`，当前只能产出 **unsigned HAP**，装不上任何真机。

---

## 六、材料合规提醒

提交的所有材料（Word / PPT / 视频 / 代码注释）**均不得出现参赛团队、指导老师、院校信息**。
本工程的代码注释里目前没有此类信息，新增内容时请保持。
