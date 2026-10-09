# 鸿蒙碳足迹 App 视觉改造调研报告

> 目标工程：ArkTS + ArkUI 声明式开发，`compatibleSdkVersion 5.0.0(12)` = **API 12**
> 现状：`#F5F7FA` 浅灰底 + 白色圆角卡（radius 14）+ 单一主色绿 `#1F9A4E` + 纯文字无图标

---

## 0. 来源与可信度声明（请先读这一节）

### 本次实际取到的官方来源

华为文档站是 Angular SPA，直接爬只能拿到空壳。本次调研逆出了官方**正文接口**并据此抓取，所有官方数值均来自该接口返回的正文，可复现：

```bash
curl -s -X POST "https://svc-drcn.developer.huawei.com/community/servlet/consumer/cn/documentPortal/getDocumentById" \
  -H "Content-Type: application/json" \
  -H "Origin: https://developer.huawei.com" -H "Referer: https://developer.huawei.com/" \
  -d '{"objectId":"corner-radius-parameter-0000002556468705","language":"cn","catalogName":"design-guides"}'
# 正文 HTML 在 value.content.content
```

目录树接口（用来枚举 `design-guides` 全部 168 篇文档）：
`.../documentPortal/getCatalogTree`，body `{"language":"cn","catalogName":"design-guides"}`

**本报告标记为「官方」的内容，全部来自下表文档的正文，逐字核对，未做任何推测性填充：**

| 文档 | objectId | 版本 |
|---|---|---|
| 圆角参数 | `corner-radius-parameter-0000002556468705` | V2 |
| 间隔参数 | `interval-parameter-0000002562577161` | V2 |
| 布局基础 | `design-layout-basics-0000001795579413` | V15 |
| 文本排版 | `typography-0000002622688363` | V5 |
| 色彩 | `color-0000001776857164` | V20 |
| 鸿蒙黑体 | `font-0000001828772001` | V14 |
| HarmonyOS Symbol | `system-icons-0000001929854962` | V16 |
| 服务卡片 | `system-features-service-widget-0000002087671904` | V9 |
| 鸿蒙卡片 | `harmonyos-widget2-0000002731312633` | — |
| 数据可视化 | `datapanel-0000001956815481` | V6 |
| 深色模式 | `dark-mode-0000001823255497` | — |
| 沉浸光感 | `immersivelight-0000002612101053` | — |
| 便捷生活类（官方案例） | `convenient-life-0000001957252465` | — |
| ArkUI 颜色渐变 | `ts-universal-attributes-gradient-color` | V242 |
| ArkUI 图像效果（阴影） | `ts-universal-attributes-image-effect` | V242 |
| ArkUI 背景设置（模糊） | `ts-universal-attributes-background` | V242 |
| ArkUI Progress | `ts-basic-components-progress` | — |
| ArkUI SymbolGlyph | `ts-basic-components-symbolglyph` | V242 |
| ArkUI animateTo | `ts-explicit-animation` | — |
| ArkUI 弹簧曲线 / 传统曲线 | `arkts-spring-curve` / `arkts-traditional-curve` | — |
| 图标小符号开发指导 | `arkts-common-components-symbol` | V243 |
| 选项卡 (Tabs) | `arkts-navigation-tabs` | — |

**额外拿到的一手数据**：华为官方 Symbol 图标库的完整索引文件（579 个图标名 + 中文释义 + 支持版本），来源
`https://developer.huawei.com/allianceCmsResource/resource/HUAWEI_Developer_VUE/template/resources/hm-symbol/name_map_new.json`
（version 2.3）。全量清单见同目录 `HarmonyOS-Symbol-全量图标清单.md`。

### 本次**没有**拿到的

- **竞品 App 的真实截图与官方色值。** 搜索通道受限（详见第四部分），我没有取得任何可验证的竞品设计稿、色值或界面标注。
- **官方是否存在"阴影 Token 全量表"。** 我找到了 `ShadowStyle` 枚举（官方 elevation 分级，见 1.6），但**没有**找到像圆角/间隔那样的"阴影 Token 全量表"文档。不确定是文档不含此表，还是我没找对文档。

**因此：第一部分（官方参数）请直接照用；第四部分（视觉参考）我明确区分了「官方来源」和「我的设计建议」，后者不要当成事实引用。**

---

# 第一部分 · 官方设计参数表

## 1.1 圆角规范（官方，可直接照改）

**两条硬性原则：**

1. **同层统一** —— 同一功能层级、同一类型的控件或容器，必须用一致的圆角半径。
2. **层级正相关** —— 圆角半径与视觉/功能层级**正相关，层级越高圆角越大**。例：半模态、弹出框等顶层元素的圆角 > 图片、标签、角标等小控件。

**五个通用尺寸（官方明确列出的"最常使用"档位）：**

| 圆角 | 官方定位 | 官方适用场景 |
|---|---|---|
| **4vp** | 系统通用超小圆角 | 标签、角标、小型状态标识、迷你图标背景、细小型控件 |
| **8vp** | 系统通用小圆角（基础圆角） | 各类图片、图标、小尺寸容器、列表内模块、基础功能控件 |
| **16vp** | 系统通用圆角 | 通知卡片、普通卡片、内容容器、中型功能面板 |
| **20vp** | 系统通用大圆角 | 按钮、菜单、选项卡、功能入口、常用交互控件 |
| **32vp** | 系统通用超大圆角 | 半模态弹窗、大型弹出框、顶层浮层、重点展示容器 |

**完整圆角 Token 表（官方全量）：**

| Token | 值 | | Token | 值 | | Token | 值 |
|---|---|---|---|---|---|---|---|
| `corner_radius_none` | 0 | | `corner_radius_level6` | 12 | | `corner_radius_level12` | 24 |
| `corner_radius_level1` | 2 | | `corner_radius_level7` | **14** | | `corner_radius_level13` | 26 |
| `corner_radius_level2` | **4** | | `corner_radius_level8` | **16** | | `corner_radius_level16` | **32** |
| `corner_radius_level3` | 6 | | `corner_radius_level9` | 18 | | `corner_radius_level18` | 36 |
| `corner_radius_level4` | **8** | | `corner_radius_level10` | **20** | | | |
| `corner_radius_level5` | 10 | | `corner_radius_level11` | 22 | | | |

> ⚠️ **对现状的直接结论**：你的卡片用了 **14vp**。14 在 Token 表里是 `level7`，但它**不在官方推荐的五档场景表里**。官方对"普通卡片/内容容器"给的是 **16vp**。建议全量替换。
> ⚠️ ArkUI `borderRadius()` **默认单位就是 vp**，可以直写 `16`。

---

## 1.2 间隔规范（官方，可直接照改）

**四条使用规则（官方原文要点）：**

1. **遵循统一栅格体系**：界面内所有间距优先使用固定基数的倍数（**如 4vp、8vp 体系**），避免随意数值。
2. **按照层级区分间距**：层级越高、独立性越强，间距越大；同级元素间距保持一致。
3. **同类元素间距一致**：按钮组间距、列表间距、卡片间距等保持统一。
4. **屏幕边缘间距固定**：内容不贴边。

**手机端屏幕边缘间隔（官方数值）：**

| 位置 | 手机 | 折叠屏 | 平板 | 智慧屏 | 穿戴 | PC |
|---|---|---|---|---|---|---|
| 屏幕**左右**两侧边距 | **16vp** | 24vp | 32vp | 48vp | 26vp | 40vp |
| 屏幕**顶部**边距 | 36vp | 36vp | 36vp | 27vp | 20vp | / |
| 屏幕**底部**边距 | 28vp | 28vp | 28vp | 27vp | 20vp | / |

**手机端元素间 / 文本间间隔（官方"泛手机"示例）：**

| 场景 | 官方数值 |
|---|---|
| **卡片之间的间隔** | **12vp** |
| 控件间上下方向**较大**间隔（有明显边界元素之间） | **16vp** |
| 控件间上下方向**普通**间隔（无明显边界元素之间） | **8vp** |
| 控件间左右方向**较大**间隔 | **16vp** |
| 控件间左右方向**普通**间隔 | **8vp** |
| **主次文本上下**间隔 | **2vp** |
| **主次文本左右**间隔 | **8vp** |

**完整间隔 Token 表（官方全量，单位 vp）：**

```
Padding_level0=0   level1=2   level2=4   level3=6   level4=8   level5=10
level6=12  level7=14  level8=16  level9=18  level10=20 level11=22 level12=24
level13=26 level16=32 level17=34 level18=36 level19=38 level20=40 level21=42
level22=44 level23=46 level25=50 level26=52 level27=54 level28=56 level29=58
level30=60 level32=64 level33=66 level34=68 level35=70 level36=72
```

> ⚠️ **对现状的直接结论**：卡片间距用 **12vp**（不是 16），卡片内边距用 **16vp**，屏幕左右边距 **16vp**，主次文本上下间距 **2vp**。

---

## 1.3 8vp 网格与栅格系统（官方）

**8vp 网格 —— 官方原文：**

> "基于 **8vp** 为网格的基本单位可以对 UI 界面上元素的大小，位置，对齐方式进行更好的规划，可以构建更有层次感、秩序感，以及多设备上一致的布局效果。**一些更小的控件，例如图标大小也可以对齐 4vp 的网格大小。**"

✅ 所以"8vp 基准"是**官方明确写了的**，而且官方同时给了 4vp 作为小控件的次级网格。

**栅格系统（官方）：**

| 窗口水平宽度 | 栅格数 | margin | gutter |
|---|---|---|---|
| `0 ≤ w < 600vp` | **4 Columns** | 16vp（通用型）/ 16vp（宽松型） | **8vp**（通用型）/ 16vp（宽松型） |
| `600 ≤ w < 840vp` | **8 Columns** | 24vp | 12vp |
| `840vp ≤ w` | **12 Columns** | 32vp | 16vp 或 20vp |

- 栅格三要素：**Margins（边距）/ Gutters（间距）/ Columns（栅格）**
- **栅格最大使用宽度 2220vp**，超出后内容区不再变化，左右留白
- 手机设备 vp 尺寸参考（官方表）：Mate 60 = 374×826vp，Mate 80 = 366×809vp，Pura 80 = 359×789vp
  → **做设计稿时按 ~360–390vp 宽校验**

---

## 1.4 字体阶梯（官方，手机列）

官方把排版分为「**展示 / 标题 / 子标题 / 正文 / 说明**」五大类共 14 档。**手机（phone）列如下**：

| 类别 | 层级 Token | 字重 Weight | **手机 Size** | PC | 手表 |
|---|---|---|---|---|---|
| **展示性文本** Display | `Display_L` | Light | **56vp** | 54 | 56 |
| | `Display_M` | Light | **48vp** | 46 | 48 |
| | `Display_S` | Light | **38vp** | 36 | 38 |
| **标题文本** Title | `Title_L` | **Bold** | **30vp** | 28 | 30 |
| | `Title_M` | **Bold** | **24vp** | 22 | 24 |
| | `Title_S` | **Bold** | **20vp** | 18 | 20 |
| **副标题文本** Subtitle | `Subtitle_L` | **Medium** | **18vp** | 16 | 18 |
| | `Subtitle_M` | **Medium** | **16vp** | 14 | 16 |
| | `Subtitle_S` | **Medium** | **14vp** | 12 | 14 |
| **正文文本** Body | `Body_L` | **Medium** | **16vp** | 14 | 16 |
| | `Body_M` | Regular | **14vp** | 14 | 14 |
| | `Body_S` | Regular | **12vp** | 14 | 12 |
| **说明文本** Caption | `Caption_L` | Medium | **12vp** | 12 | 12 |
| | `Caption_M` | Medium | **10vp** | 9 | 10 |

> 📌 **注意单位**：官方表里写的是 **vp**，不是 fp。ArkUI 里字号用 `.fontSize()`（默认单位 **fp**）。官方在别处定义 `1 fp = 1 vp × scale`，所以 1:1 对应即可。

**官方排版体验要求（5 条）：**
1. 字号应大于用户可阅读的最小字号
2. 选择适当颜色并确保足够对比度
3. 保持字体一致性（字重 + 字体风格）
4. **避免过度使用字号、粗细和颜色**，避免层级过多
5. 支持系统大字体（无障碍）

**字体家族（官方）**：`HarmonyOS Sans` 是系统默认字体，完整支持简繁中文 + 拉丁/希腊/西里尔/阿拉伯语系。
**可用字重（官方列出 9 档）**：`Thin / UltraLight / Light / Regular / Medium / SemiBold / Bold / Heavy / Black`
另有 **Condensed**（窄字宽）与 **Italic** 风格，以及 **VF 可变字体**（字重可在连续轴上调节）。

**鸿蒙卡片（应用内卡片）的排版官方建议：**
- **标题 20vp 以上，正文 8vp 以上，两者保持 12.5% 梯度关系**
- 文字组合需控制在 **3 组以内**，每组字数建议**不超过 13 字**
- 页面内特殊字体应继承性使用，**避免使用 2 种以上字体**
- 文字与背景对比度应保证在 **1:3 以上**

---

## 1.5 官方色彩 Token 全量表（官方，ARGB 格式，前两位是透明度）

### 基础与语义色

| Token | 场景 | Light | Dark |
|---|---|---|---|
| `brand` | 品牌色 | `#ff0a59f7` | `#ff317af7` |
| `warning` | 一级警示色 | `#ffe84026` | `#ffd94838` |
| `alert` | 二级警示色 | `#ffed6f21` | `#ffdb6b42` |
| `confirm` | **确认色（成功）** | `#ff64bb5c` | `#ff5ba854` |
| `background_emphasize` | 高亮背景 | `#ff0a59f7` | `#ff317af7` |

### 文本色（4 级 + 高亮 + 反色）

| Token | 场景 | Light | Dark |
|---|---|---|---|
| `font_primary` | 一级文本 | `#e5000000` | `#e5ffffff` |
| `font_secondary` | 二级文本 | `#99000000` | `#99ffffff` |
| `font_tertiary` | 三级文本 | `#66000000` | `#66ffffff` |
| `font_fourth` | 四级文本 | `#33000000` | `#33ffffff` |
| `font_emphasize` | 高亮文本 | `#ff0a59f7` | `#ff317af7` |
| `font_on_primary` | 一级文本反色 | `#ffffffff` | `#ffffffff` |
| `font_on_secondary` | 二级文本反色 | `#99ffffff` | `#99ffffff` |

### 图标色

| Token | Light | Dark |
|---|---|---|
| `icon_primary` | `#e5000000` | `#e5ffffff` |
| `icon_secondary` | `#99000000` | `#99ffffff` |
| `icon_tertiary` | `#66000000` | `#66ffffff` |
| `icon_fourth` | `#33000000` | `#33ffffff` |
| `icon_emphasize` | `#ff0a59f7` | `#ff317af7` |
| `icon_sub_emphasize` | `#660a59f7` | `#66317af7` |

### 界面背景色

| Token | 场景 | Light | Dark |
|---|---|---|---|
| `background_primary` | 界面一级背景（实色） | **`#ffffffff`** | `#ffe5e5e5` |
| `background_secondary` | 界面二级背景（实色） | **`#fff1f3f5`** | `#ff191a1c` |
| `background_tertiary` | 三级背景 | `#ffe5e5ea` | `#ff202224` |
| `background_fourth` | 四级背景 | `#ffd1d1d6` | `#ff2e3033` |

### 组件容器色

| Token | 场景 | Light | Dark |
|---|---|---|---|
| `comp_foreground_primary` | 前背景 | `#ff000000` | `#ffe5e5e5` |
| `comp_background_primary` | 白色背景 | `#ffffffff` | `#ff202224` |
| `comp_background_primary_contrary` | 常亮背景 | `#ffffffff` | `#ffe5e5e5` |
| `comp_background_gray` | 灰色背景 | `#fff1f3f5` | `#ffe5e5ea` |
| `comp_background_secondary` | 二级背景 | `#19000000` | `#19ffffff` |
| `comp_background_tertiary` | 三级背景 | `#0c000000` | `#0cffffff` |
| `comp_background_emphasize` | 高亮背景 | `#ff0a59f7` | `#ff317af7` |
| `comp_background_neutral` | 黑色中性高亮背景 | `#ff000000` | `#ffffffff` |
| `comp_emphasize_secondary` | **20% 高亮背景** | `#330a59f7` | `#33317af7` |
| `comp_emphasize_tertiary` | **10% 高亮背景** | `#190a59f7` | `#19317af7` |
| `comp_divider` | **分割线颜色** | `#33000000` | `#33ffffff` |
| `comp_common_contrary` | 通用反色 | `#ffffffff` | `#ff000000` |

### 交互事件色

| Token | 场景 | Light | Dark |
|---|---|---|---|
| `interactive_hover` | 悬停 | `#0c000000` | `#0cffffff` |
| `interactive_pressed` | 按压 | `#19000000` | `#19ffffff` |
| `interactive_focus` | 获焦 | `#ff0a59f7` | `#ff317af7` |
| `interactive_select` | 选中 | `#330a59f7` | `#33317af7` |
| `interactive_disable` | 禁用 | — | — |

### 色彩体系的三层结构与关键约束（官方）

- **三层**：控件私有参数 → **通用语义参数** → **通用基础参数**
- **基础 Token**：`primary` / `on_primary` / `brand` / `container` / `background`。**"基于常规色四件套便可搭建系统整体的色彩风格"**
- **透明度映射**：基础 Token 会**基于透明度系数分别映射出 12 个不同的色彩参数**
- **对比度硬指标**：系统默认颜色保障**最小 3:1 对比度**
- **命名规则**：文本/图标分 `font_primary/secondary/tertiary/fourth` 四级 + `font_emphasize` 高亮；反色用 `font_on_*` / `icon_on_*`

**深色模式的额外对比度要求（官方，来自《深色模式》）：**

| 指标 | 要求 |
|---|---|
| 正文与背景对比度 | **不低于 5:1** |
| 辅助文本与背景对比度 | **不低于 5:1** |
| 可点击控件背景填充色与页面背景对比度 | **不低于 2.2:1** |
| 相邻/需区分的两个颜色，色彩差异 | **ΔEuv ≥ 20**（含色盲模拟器校验） |
| 大字号（17fp 或 15fp 以上粗体）、辅助文本、功能性图标 | 浅色 >4.5:1，深色 >5:1 |

> ⚠️ **对现状的直接结论（重要）**：
> 1. 你的 `#F5F7FA` 与官方 `background_secondary` **`#fff1f3f5`** 极其接近 —— 方向对了，但**建议换成官方值**以便和系统组件观感对齐。
> 2. 你的主色绿 `#1F9A4E` **不是**官方品牌色。官方 `brand` 是**宇宙蓝 `#0a59f7`**；官方的**绿色 `#64bb5c` 是 `confirm`（确认/成功）语义色**。
> 3. 你**缺的正是"语义色"这一层**：`warning #e84026` / `alert #ed6f21` / `confirm #64bb5c`。补上这三个，界面立刻有"系统感"。
> 4. 你**缺"文本/图标分级"**：现在大概率所有文字都是同一个黑。官方是 `#e5000000` / `#99000000` / `#66000000` / `#33000000` **四级**，这是"平庸 vs 精致"最便宜的杠杆。
> 5. 官方高亮背景的**20% / 10% 透明度**做法（`#330a59f7` / `#190a59f7`）可以直接用来做"选中态标签底色"，比纯色块高级。

---

## 1.6 阴影与层级（官方 elevation 分级）—— 有，但形式和你预期的不一样

**官方确实有 elevation 分级**，但它是**枚举**形式，不是"阴影 Token 数值表"。在 ArkUI 里就是 `ShadowStyle`：

### `ShadowStyle` 枚举（API 10+ 起支持）

| 名称 | 值 | 说明 |
|---|---|---|
| `OUTER_DEFAULT_XS` | 0 | 超小阴影 |
| `OUTER_DEFAULT_SM` | 1 | 小阴影 |
| `OUTER_DEFAULT_MD` | 2 | 中阴影 |
| `OUTER_DEFAULT_LG` | 3 | 大阴影 |
| `OUTER_FLOATING_SM` | 4 | 浮动小阴影 |
| `OUTER_FLOATING_MD` | 5 | 浮动中阴影 |

**这就是官方的层级语言**：`XS→SM→MD→LG` 是一档档加深的静态层级；`FLOATING_*` 是"浮起来"的一档（对应悬浮元素）。

### `ShadowOptions` 自定义（`shadow()` 入参）

| 属性 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `radius` | `number \| Resource` | — | 阴影模糊半径。**单位 px**（不是 vp！） |
| `type` | `ShadowType` | `COLOR` | 阴影类型（API 10+） |
| `color` | `Color \| string \| Resource \| ColoringStrategy` | **黑色** | 阴影颜色。API 11+ 支持 `'average'`（智能平均取色）/ `'primary'`（智能主色取色） |
| `offsetX` | `number \| Resource` | 0 | X 轴偏移。**单位 px** |
| `offsetY` | `number \| Resource` | 0 | Y 轴偏移。**单位 px** |
| `fill` | `boolean` | `false` | 是否内部填充（API 11+）。`true`=内阴影，`false`=外阴影 |

> ⚠️ **关键坑（官方原文）**：`radius` / `offsetX` / `offsetY` 的**单位是 px**，"如需使用 vp 单位的数值可用 `vp2px` 进行转换"。这就是很多人写 `shadow({radius: 8})` 却发现阴影几乎看不见的原因 —— 8px 在 3x 屏上只有约 2.7vp 的模糊。
>
> ⚠️ **官方关于层级手段的另一条线索**：在《弹出框》文档中提到，**电脑设备上"弹出框会自带阴影，分为获焦态与失焦态，用来区分当前操作的窗口层级"**；而移动端"通常使用**全屏蒙层或窗口蒙层**来解决弹出框与界面背景的层级差异"。也就是说，**官方在移动端并不把阴影当作主要的层级手段，而是用蒙层**。
>
> ⚠️ **深色模式下官方明确说**："浅色模式下明度不是唯一的表达层级的视觉线索，而在深色模式尤其是在黑色背景上，**用户对投影的感知程度降低，通常使用明度表达层级**"。→ 深色模式里别指望阴影，要用背景明度差。

**《鸿蒙卡片》文档里的色彩层级约束（官方，可直接用在卡片配色上）：**
- **主色相不能超过 3 种**，核心颜色 1-2 个且占比最大，辅助色仅作丰富画面和点缀，**不可喧宾夺主**
- **主色色彩明度 + 饱和度 < 180**
- 避免使用大量高饱和度的颜色
- 多个主体物情况下**不超过 3 个**，且**主体物面积不超过画面的 60%**
- 并列元素：**重要的并列元素建议控制在 3-5 个**，其他非主要元素可使用 7 个左右；并列元素过多时用组块区分

---

## 1.7 万能卡片（服务卡片）设计规范（官方，全部数值）

### 尺寸体系
- 卡片按桌面宫格布局，**以手机 4×6 宫格为基础分为 4 种尺寸**
- 另有**圆形（1×1）**用于**锁屏和穿戴设备**
- 5 类：圆形 / 微尺寸 / 小尺寸 / 中尺寸 / 大尺寸
- **小尺寸（2×2）为必开发选项**，上架建议必须包含

### 卡片圆角（官方，注意这句是给设计工具用的）
> "设计师在进行设计时如果需要保证最终效果，可以在设计工具里使用 **1×2、2×2 宫格 18vp**，**2×4、4×4 宫格 22vp** 圆角预览效果，**交付时确保直角即可**。"

- **1×2、2×2 宫格 → 18vp**
- **2×4、4×4 宫格 → 22vp**
- ⚠️ 交付时背景必须是**直角矩形**，圆角由宿主裁切
- 锁屏 1×1、1×2 按最大圆角裁切为**圆形、胶囊形**

### 安全边距（官方）
> "卡片内容需要保证**距离边缘 12vp 的安全边距**，以免在圆角剪裁时对内容展示造成影响。"

### 卡片字号（官方）

| 场景 | 字号 |
|---|---|
| 左上角标题（通用建议） | **18fp、14fp**，默认距卡片左上角 **12vp** |
| 数字字体档位 | **20、32、40fp** |
| 桌面 1×2 主标题 / 副标题 | 14fp / 12fp |
| 桌面 1×2 数字 / 副标题 | 20fp / 12fp |
| 桌面 2×2 主标题 | 14、18fp |
| 桌面 2×2 副标题、辅助信息 | 12fp、14fp |
| 桌面 2×2 数字 | **32、40fp** |
| 锁屏 1×1 数据进度型 | 16fp |
| 锁屏 1×1 数据刻度型、图文结合型 | 12fp |
| 锁屏 1×2 图文结合型 | 10、14、20fp |
| 锁屏 1×2 清单列表型 | 10fp |

- 字重：合理运用 **Regular、Medium、SemiBold、Bold** 的关系，"帮助用户在阅读相对复杂的信息卡片时能够及时做出筛选"

### 卡片按钮（官方）
- 要求使用**圆形和胶囊形**按钮样式
- **可点击元素视觉尺寸不得小于 24vp，热区大小不得小于 40vp**
- 1×2 宫格按钮视觉推荐尺寸：**32×32vp**
- 2×2 宫格按钮视觉推荐尺寸：**30×30vp**
- 胶囊按钮高度视觉推荐尺寸：**36vp**，宽度自定义，但保证**距卡片四周 12vp**
- **按钮文本大小：14fp，Medium**
- 卡片内**不要**用滑动、拖拽、长按（与系统手势冲突）

### 卡片色彩（官方）
- 常规富信息卡片背景色尽可能干净，**"不要为了吸引眼球而使用跳脱的颜色"**
- Light 模式默认 **`#FFFFFF`**
- **Dark 模式默认 `#2E3033`**（与 `background_fourth` 的 dark 值 `#ff2e3033` 一致）
- 灰色背景**仅用于**卡片上还有其他白色色块时，防止白色重叠
- 也可用**透明度的毛玻璃效果**作为卡片背景，"如使用此效果需要调用系统的模糊能力"
- 锁屏卡片用**单色模式**：**通过透明度和模糊区分元素，不使用任何色相**

### 占位图规范（官方，做骨架屏可直接用）
- 一档占位色：**10% `#000000`（浅色）/ 40% `#FFFFFF`（深色）**
- 二档占位色：**5% `#000000`（浅色）/ 20% `#FFFFFF`（深色）**
- 圆角：占位内容高度 **>10vp 用一档圆角 4vp**；**≤10vp 用二档圆角 2vp**
- 文本占位 → 固定高度横条；图标占位 → 几何图形

### 品牌标识（官方）
- 单独使用品牌 LOGO 时，**20×20vp 大小，4vp 圆角**
- 卡片内**不建议**再出现应用名称
- 文字 LOGO / 服务信息名**统一放左上角**；纯图标**统一放右上角**
- 卡片名称 **2–7 个字符最佳**，最长不超过 30 字符；卡片描述最长 255 字符

### 字体适配（官方）
- 手机字体从 **0.8 倍到 1.45 倍**及适老化
- **卡片适配控制在最大 1.3 倍以下**，建议定义最大到 1.15 或 1.3
- **超过 20fp 的字号不响应大字体和适老化**

### 刷新（官方）
- 被动刷新频率**以 30 分钟为基础**，开发者可根据业务性质向上叠加
- 刷新动效：小元素变化用**简单变化 / Symbol 默认动效**；大面元素用**渐隐渐现**；数字用**翻转滑动**；周期轮播用**推移补位**

### 互动卡片元素出框（官方）
- 稳定态展示范围：**顶部不超过 16vp，底部和左右两侧不超过 8vp**
- 过程态展示范围：**四周不超过 56vp**
- 建议单边或双边出框，避免所有边缘出框

---

## 1.8 图标体系（官方）

### 设计规范
| 项目 | 官方数值 |
|---|---|
| 标准图标尺寸 | **24×24vp** |
| 主题物安全区 | **22×22vp**（蓝色区间内） |
| 描边粗细 | **1.5vp** |
| 终点样式 | **圆头** |
| 断口宽度 | **1.3vp** |
| 外圆角 / 内圆角 | **3vp / 1.5vp** |
| 复杂形状描边粗细 | **1.3vp** |
| 角标（面性图形无背板时）大小 | **8vp** |
| 切断角度 | 斜线从左上至右下，**45 度** |
| 导出格式 | **SVG**，必须包含外框线条 |

### SymbolGlyph / SymbolSpan（API 版本已逐项核对）

| 能力 | 起始版本 | API 12 可用？ |
|---|---|---|
| `SymbolGlyph` 组件 | **API 11** | ✅ |
| `SymbolSpan` 组件 | API 11 | ✅ |
| `.fontSize()` | API 12 支持在 attributeModifier 调用 | ✅ |
| `.fontColor(Array<ResourceColor>)` | **API 12** 支持 attributeModifier | ✅ |
| `.fontWeight()` | API 12 | ✅ |
| `.renderingStrategy()` | API 12 | ✅ |
| `.effectStrategy()` | API 12 | ✅ |
| `.symbolEffect()` | **API 12** | ✅ |
| `.symbolShadow()` | **API 20** | ❌ **不可用** |
| `.shaderStyle()` | **API 20** | ❌ **不可用** |

**官方关键说明：**
- `SymbolGlyph` **仅支持系统预置的 Symbol 资源名**：`$r('sys.symbol.ohos_wifi')`；引用非 symbol 资源会显示异常
- **默认字体大小 16fp**；**图标尺寸与字号一致** —— "设定为 24vp 的字号，其图标的宽高也将为 24×24vp"
- 支持**粗细无极变化**，能与系统字体无缝对接、与文本基线对齐

**三种渲染策略（`SymbolRenderingStrategy`）：**

| 策略 | 行为 |
|---|---|
| `SINGLE` | 单色。只生效**第一个**颜色 |
| `MULTIPLE_OPACITY` | 分层。默认黑色，可设一个颜色。**不透明度与图层相关：第一层 100%、第二层 50%** |
| `MULTIPLE_COLOR` | 多色。生效**两种**颜色；顺序与图层顺序匹配，多余颜色不生效 |

**动效策略：**
- `effectStrategy()` 仅支持 **NONE / SCALE / HIERARCHICAL** 三种预置动效，设置后**自动播放**
- `symbolEffect()` 支持更丰富的策略（出现、消失、弹跳、缩放、替换、快速替换、脉冲、可变颜色、禁用），并可控制播放状态
- ⚠️ 两者**不可同时使用**

### 内置符号名全量清单（一手数据）

从官方 Symbol 图标库索引 `name_map_new.json`（version **2.3**）解析：**共 579 个图标**。

支持版本分布：
- **`HarmonyOS 5.0+` = 570 个** ← **这些在 API 12 上都能用**
- `HarmonyOS 5.1+` = 5 个
- `HarmonyOS 6.0` = 3 个
- `HarmonyOS 6.1` = 1 个

**17 个大类及数量**：系统UI 147 / 箭头 58 / 编辑 56 / 相机与照片 46 / 媒体 36 / 通信 34 / 键盘 32 / 人物 31 / 办公文件 31 / 连接 26 / 隐私&安全 21 / 符号标识 19 / 时间 16 / 交通出行 15 / 形状 9 / 家庭 1 / 设备 1

**全量清单（579 个，含中文释义、所属模块、支持版本）已导出到同目录 `HarmonyOS-Symbol-全量图标清单.md`。**

**对碳足迹 App 最相关的一批（均已核实为 `HarmonyOS 5.0+`，API 12 可用）：**

| 用途 | 符号名 | 官方释义 |
|---|---|---|
| 首页 / 页签 | `house` / `house_fill` | home/首页 · 首页-选中 |
| 看板 / 图表页签 | `chart_pie` 未找到，见下方说明 | — |
| 积分 / 奖励 | `star` / `star_fill` | 获赞与收藏 / 收藏 |
| 我的 | `person` / `person_crop_circle_fill_1` | 账号 / **我的-未选中** |
| 设置 | `gearshape` / `gearshape_fill` | 设置 |
| 帮助 | `questionmark_circle` / `questionmark_circle_fill` | 帮助与客服 |
| 关于 | `info_circle` / `info_circle_fill` | 模式详情 / **详情、关于** |
| 记一笔（新增） | `plus` / `plus_circle_fill` | 增加/添加 |
| 完成 / 打卡 | `checkmark` / `checkmark_circle` / `checkmark_circle_fill` | 确认/勾选 / 清单 |
| 已选 | `checkmark_square_fill` | 已选 |
| 目标 | `flag` / `flag_fill` | **目标**（来自运动健康模块） |
| 运动 | `figure_running` | 运动 |
| 站立 | `figure_arms_open` | 站立 |
| 时间 / 时长 | `clock` / `clock_fill` | 时长 / **运动时间** |
| 日历 | `calendar` / `calendar_fill` | 日历 |
| 电 / 能源 | `bolt` / `bolt_fill` | 电费 |
| 功率 | `bolt_filled_on_circle` | 功率 |
| 水 | `drop_fill` | 水费 |
| 删除 | `trash` / `trash_fill` | 删除/回收站 |
| 搜索 | `magnifyingglass` | 搜索/查询/查找 |
| 通知 | `bell` / `bell_fill` / `bell_slash` | 响铃、通知 / 静音 |
| 收藏 | `heart` / `heart_fill` / `bookmark` / `bookmark_fill` | 收藏/爱心 |
| 科普 / 文章 | `book_open_fill` / `ebook` | 书城-选中 / 电子书 |
| 列表 | `list_bullet` / `list_square` / `list_number` | 项目符号 |
| 更多 | `dot_grid_2x2` | 更多/more |
| 返回 | `arrow_left` / `arrow_left_circle` | 返回 |
| 前进 / 下一级 | `arrow_right` / `arrow_right_circle` | 箭头/向右 |
| 刷新 / 同步 | `arrow_2_circlepath` | 旋转、切换 |
| 历史记录 | `arrow_counterclockwise_clock` | 历史记录 |
| 下载 | `arrow_down_circle` | 下载 |
| 上传 / 发送 | `arrow_up_circle_fill` | 发送/向上 |
| 亮度 / 环保主题 | `sun_max` | 曝光/亮度 |
| 分享 / 转发 | `arrowshape_turn_up_right_fill` | 转发 |
| 视频 | `play_video` / `video` | 视频 |
| 相机 | `camera` | 拍照 |
| 文本 / 日志 | `doc_text` | **日志**/文本/文件 |
| 已完成文档 | `doc_text_badge_checkmark` | 已完成 |
| 分类相册 | `square_fill_grid_2x2` | 分类相册 |
| 网格 | `grid` | 网格 |
| 隐私 | `person_shield` / `info_shield` | 隐私管理 / 隐私声明 |

> ⚠️ **重要提示**：我在 579 个图标里**没有找到** `leaf`（叶子）、`tree`（树）、`recycle`（回收）、`trophy`（奖杯）、`gift`（礼物）、`chart`（图表）这类名字。**官方 Symbol 库当前不含专门的"环保/碳/图表"语义图标** —— 它是从鸿蒙自家 App（图库、音乐、备忘录、运动健康、钱包…）的用图需求里长出来的。
> **这对改造有直接影响**：碳足迹的核心视觉隐喻（叶子、树、CO₂）**必须自备 SVG 图标资源**，页签图标则可以从上面这批里挑语义接近的（如 积分页用 `star_fill`、看板页用 `bolt_filled_on_circle` 或 `square_fill_grid_2x2`）。
> **替代方案见第 3.7 节。**

---

## 1.9 数据可视化官方规范（《数据可视化》文档）

- 组件样式分四大类：**进度形 / 占比形 / 范围形 / 线形**
- 选型规则（官方原文）：
  - "**数据组别较多的可以通过多个线形进度条组合，单个数据占比的可优先使用环形**"
  - "**范围类控件调用 Gauge 组件来实现**"
  - "环形进度数据开发相关能力请参考 **DataPanel** 文档，图标类数据开发相关能力请参考 **Gauge** 文档"
- 颜色（官方原文）：
  - "若应用需要展示的数据分类较多，则需要提供**多个分类明显的色彩**进行展示"
  - "数据条控件的颜色应与所展示数据的含义相符，**如绿色表示上升，红色表示下降**"
  - "或是可自定义一组套系色彩，呈现品牌自己的色彩风格"
  - "也可以根据数据含义**使用渐变色等视觉效果**，增强数据可读性和色彩的细腻程度"
  - "当存在多条数据线时，应为**每条线分配独特的颜色**，避免混淆"
- **线形数据条默认 4vp 小圆角**；"当开发者修改圆角大小或数据条高度时，两侧数据会被挤压显示控件"
- 短边规则：资源大小按短边计算。竖屏上下布局时，将屏幕一分为二后对比宽高，**数值较小的为短边**

---

# 第二部分 · 改造清单（按「改动小 / 收益大」排序）

> 每条都标注了**依据**：「官方」= 来自第一部分官方数值；「建议」= 我的设计判断。

| # | 改动 | 改什么 / 怎么改 | 预期效果 | 依据 | 工作量 |
|---|---|---|---|---|---|
| **T1** | **建立 4 档文本色 + 3 档图标色** | 全局定义 `font_primary #E5000000` / `font_secondary #99000000` / `font_tertiary #66000000` / `font_fourth #33000000`，把所有 `fontColor('#333')`、`Color.Black` 替换掉 | **单条改动，收益最大。** 层级感立刻出来，"平庸"主要就来自所有字一个颜色 | 官方 | 极小（1 个常量文件 + 全局替换） |
| **T2** | **补语义色三件套** | 加 `warning #E84026`（超额/超支）、`alert #ED6F21`（注意）、`confirm #64BB5C`（达成/成功） | 界面上第一次出现"有含义的颜色"，不再只有一种绿 | 官方 | 极小 |
| **T3** | **背景色换成官方值** | `#F5F7FA` → **`#F1F3F5`**（官方 `background_secondary`） | 与系统组件观感同源，白卡片浮起来更自然 | 官方 | 极小（1 行） |
| **T4** | **圆角收敛到官方五档** | 卡片 `14` → **`16`**；标签/角标 → **`4`**；图片/小图标底 → **`8`**；按钮 → **`20`**；弹窗/半模态 → **`32`**。**废止 14 和其它随意值** | 圆角从"随手填的数"变成"有层级语言的系统"。"层级正相关"是官方明文原则 | 官方 | 小（全局搜索替换） |
| **T5** | **间距全面对齐 8vp 体系** | 卡片间距 **12vp**、卡片内边距 **16vp**、屏幕左右 **16vp**、有边界元素间 **16vp**、无边界元素间 **8vp**、主次文本上下 **2vp**、左右 **8vp** | 版面立刻"整齐"，这是廉价但极有效的秩序感来源 | 官方 | 小 |
| **T6** | **卡片分三级（这是治"平庸"的核心）** | ①**主卡**（英雄区）：`linearGradient` 渐变底 + 32vp 圆角 + 无阴影<br>②**次卡**：白底 + 16vp 圆角 + `shadow({radius: vp2px(12), color:'#14000000', offsetY: vp2px(2)})`<br>③**微卡**：`#F1F3F5` 填充 + **无阴影** + 8vp 圆角 | **一句话：不是所有卡片长一样。** 官方明确"层级正相关"，且深色模式靠明度而非阴影 | 官方 + 建议 | 中 |
| **T7** | **首页英雄区重做** | 顶部一张大渐变卡：`linearGradient({angle:135, colors:[['#1F9A4E',0],['#0E7A3C',1]]})` + **32vp 圆角** + 环形进度 `Progress({type: ProgressType.Ring})` + **Display_M 48vp Light 大数字** + `Caption_L 12vp` 单位后缀 | 首屏有"主角"。大数字用 **Light 字重**是官方 Display 规格，比 Bold 高级得多 | 官方（字号/圆角/间距）+ 建议（渐变） | 中 |
| **T8** | **底部页签加图标 + 毛玻璃** | `TabContent.tabBar(this.tabBuilder(...))` 自定义，用 `SymbolGlyph` 图标 + 文字；`Tabs().barBackgroundBlurStyle(BlurStyle.COMPONENT_THICK).barOverlap(true)` | 页签从"纯文字"变成标准鸿蒙形态。**SymbolGlyph 是 API 11+，本工程可用** | 官方 | 小 |
| **T9** | **看板图表去网格线 + 上渐变** | 柱状/环形填 `linearGradient`；删掉所有网格线和坐标轴框；柱顶或环端加 `strokeRadius` 圆角 | 官方数据可视化原文鼓励"使用渐变色增强数据可读性和色彩的细腻程度" | 官方 | 中 |
| **T10** | **表单页图标化** | "记一笔"每行字段左侧加 `SymbolGlyph`（`bolt` 电 / `drop_fill` 水 / `figure_running` 出行 / `doc_text` 备注），图标色用 `icon_tertiary #66000000`，尺寸 24vp | 表单从"一堵文字墙"变成可扫读的列表。**这是当前"纯文字无图标"的直接解药** | 官方（图标尺寸/色阶） | 中 |
| **T11** | **积分页加等级/徽章卡** | 顶部一张 `radialGradient` 或 `sweepGradient` 徽章卡；积分数用 `Display_S 38vp`；兑换项用"微卡"（T6 第三级）区分 | 积分页有"成就感"峰值，与看板、表单拉开差异 | 建议 | 中 |
| **T12** | **加三处动效** | ①进入首页：`animateTo` + `curves.springMotion()` 驱动环形进度从 0 增长 + 数字滚动<br>②卡片 `onTouch` 按压态：`interactive_pressed #19000000` 叠加或 `scale(0.98)`<br>③页签切换 Symbol 用 `symbolEffect(new BounceSymbolEffect(...))` | 官方原文："采用弹簧曲线的动画在达终点时动画速度为 0，不会产生动画'戛然而止'的观感" | 官方 | 中 |

### 关于 T6「卡片分级」的具体建议参数

```
主卡（英雄区）  radius 32 · padding 20 · 渐变底 · 无阴影
次卡（内容卡）  radius 16 · padding 16 · #FFFFFF · shadow(radius:vp2px(12), color:'#14000000', offsetY:vp2px(2))
微卡（内嵌项）  radius 8  · padding 12 · #F1F3F5 · 无阴影
标签 / 角标     radius 4  · padding {h:8, v:2} · comp_emphasize_tertiary #190a59f7 或 #190A59F7 同构的绿色 10% 版
提示 / 通知     radius 16 · #FFFFFF · shadow(radius:vp2px(8), color:'#0F000000', offsetY:vp2px(1))
弹窗 / 半模态   radius 32
```

> 注：`comp_emphasize_tertiary` 官方值 `#190a59f7` 是**蓝色**的 10%。若你坚持绿色品牌，就按同样的"**10% / 20% 透明度**"规则生成绿色版本（如 `#191F9A4E` / `#331F9A4E`）—— **"用透明度做高亮底色"这个方法是官方的**，只是色相换成你的品牌绿。

---

# 第三部分 · ArkUI 代码片段集（API 12 逐条核对）

> 全部标注 API 版本。`vp2px` 是 ArkUI 全局函数，无需 import。

## 3.1 渐变（`linearGradient` / `radialGradient` / `sweepGradient`）

**API 版本（官方）**：`linearGradient` / `radialGradient` / `sweepGradient` 均 **API 7 起支持** → **API 12 完全可用**。
**重要限制（官方原文）**：
- 颜色渐变属于**组件内容**，绘制在背景**上方**
- **不支持宽高显式动画**，执行宽高动画时渐变会直接过渡到终点
- **同一组件上只能设置一种类型的颜色渐变**，后调用的会**覆盖**之前设置的

```typescript
// xxx.ets
@Entry
@Component
struct GradientDemo {
  build() {
    Column({ space: 16 }) {
      // ① 线性渐变 —— 英雄区背景卡
      //    angle: 0deg 从下往上；顺时针为正。colors: [颜色, 位置0~1]
      Row()
        .width('100%')
        .height(160)
        .borderRadius(32)
        .linearGradient({
          angle: 135,                                  // 左上 -> 右下
          colors: [['#1F9A4E', 0.0], ['#0E7A3C', 1.0]]
        })

      // ② 线性渐变（用方向枚举替代 angle）
      Row()
        .width('100%')
        .height(80)
        .borderRadius(16)
        .linearGradient({
          direction: GradientDirection.Right,          // angle 设置后 direction 不生效
          colors: [['#33FFFFFF', 0.0], ['#00FFFFFF', 1.0]]
        })

      // ③ 径向渐变 —— 积分徽章卡
      Row()
        .width('100%')
        .height(120)
        .borderRadius(32)
        .radialGradient({
          center: ['50%', '50%'],
          radius: '70%',
          colors: [['#FFF3C4', 0.0], ['#F2A93B', 1.0]]
        })

      // ④ 角度渐变 —— 环形进度底衬 / 动感装饰
      Row()
        .width(120)
        .height(120)
        .borderRadius(60)
        .sweepGradient({
          center: [60, 60],
          start: 0,
          end: 359,
          rotation: 45,
          colors: [['#1F9A4E', 0.0], ['#8BD8A6', 0.5], ['#0E7A3C', 1.0]]
        })

      // ⑤ 重复填充
      Row()
        .width('100%')
        .height(24)
        .borderRadius(8)
        .linearGradient({
          direction: GradientDirection.Right,
          repeating: true,
          colors: [['#1F9A4E', 0.0], ['#FFFFFF', 0.5]]
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#F1F3F5')
  }
}
```

**参数速查：**

| 渐变 | 参数 | 类型 | 说明 |
|---|---|---|---|
| `linearGradient` | `angle` | `number \| string` | 角度，number 单位度。**0 度从下往上**，顺时针为正。**默认 180**。字符串支持 `"90"`/`"90deg"`/`"1.57rad"`/`"0.25turn"` |
| | `direction` | `GradientDirection` | `Left/Right/Top/Bottom/LeftTop/...`；设了 `angle` 后此项不生效。**默认 `Bottom`** |
| | `colors` | `Array<[ResourceColor, number]>` | `[颜色, 位置]`，位置取值 `[0, 1.0]`，必须**递增** |
| | `repeating` | `boolean` | 默认 `false` |
| `radialGradient` | `center` | `[Length, Length]` | 相对组件左上角的中心点，number 单位 vp |
| | `radius` | `number \| string` | 半径。**默认 0** |
| `sweepGradient` | `center` / `start` / `end` / `rotation` / `repeating` | | `start`/`end` 角度，`rotation` 旋转角 |

> 💡 **`.backgroundColor()` 不能接渐变**。要渐变背景就用 `.linearGradient()`（它画在内容下方但属于组件内容），或者用 `Stack` 叠一个渐变层。

---

## 3.2 阴影（`shadow()`）

**API 版本**：`shadow()` **API 7 起**；入参支持 `ShadowStyle` 枚举为 **API 10+**；`fill` 字段 **API 11+**。→ **API 12 全部可用。**

```typescript
// xxx.ets
@Entry
@Component
struct ShadowDemo {
  build() {
    Column({ space: 20 }) {

      // ① 官方 elevation 分级（推荐 —— 直接对齐系统视觉语言）
      Row().width('90%').height(60)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .shadow(ShadowStyle.OUTER_DEFAULT_XS)     // 超小：角标、微卡

      Row().width('90%').height(60)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .shadow(ShadowStyle.OUTER_DEFAULT_SM)     // 小：列表项、次卡

      Row().width('90%').height(60)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .shadow(ShadowStyle.OUTER_DEFAULT_MD)     // 中：主卡、悬浮操作栏

      Row().width('90%').height(60)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .shadow(ShadowStyle.OUTER_FLOATING_MD)    // 浮动中：底部悬浮 TabBar、FAB

      // ② 自定义阴影（次卡标准配方）
      //    ⚠️ radius / offsetX / offsetY 单位是 px，必须 vp2px 转换！
      Row().width('90%').height(60)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .shadow({
          radius: vp2px(12),        // 模糊半径
          color: '#14000000',       // 8% 黑
          offsetX: 0,
          offsetY: vp2px(2)
        })

      // ③ 内阴影（API 11+）—— 做"凹陷"输入框
      Row().width('90%').height(48)
        .backgroundColor('#F1F3F5')
        .borderRadius(8)
        .shadow({
          radius: vp2px(6),
          color: '#0F000000',
          offsetX: 0,
          offsetY: vp2px(1),
          fill: true               // true = 内阴影
        })

      // ④ 智能取色阴影（API 11+）—— 卡片上浮时取图主色
      Row().width('90%').height(60)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .shadow({
          radius: vp2px(16),
          color: 'primary',        // 'average' = 平均取色；'primary' = 主色取色
          offsetY: vp2px(4)
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#F1F3F5')
  }
}
```

> ⚠️ **圆角 + 阴影同时生效的正确写法（高频踩坑）**：
> 直接 `.borderRadius(16).clip(true).shadow(...)` 会把阴影**一起裁掉**。
> **正确做法**：外层容器负责阴影 + 圆角 + 背景色，内层负责内容裁剪；或者干脆**不要** `clip(true)`，让子组件自己设圆角。
> ```typescript
> // ✅ 正确：外层阴影，内层裁剪
> Column() {
>   Column() { /* 内容 */ }
>     .width('100%')
>     .borderRadius(16)
>     .clip(true)             // 只裁内容
> }
> .backgroundColor(Color.White)
> .borderRadius(16)
> .shadow({ radius: vp2px(12), color: '#14000000', offsetY: vp2px(2) })  // 阴影不被裁
> ```

---

## 3.3 模糊 / 毛玻璃

**API 版本**：`backgroundBlurStyle` **API 9 起**；`BlurStyle` 枚举值 `BACKGROUND_*` **API 10+**、`COMPONENT_*` **API 11+**。→ **API 12 全部可用。**
**官方重要限制（原文）**：
- `backgroundBlurStyle`、`backdropBlur`、`backgroundEffect` **均为背景模糊接口**，同一组件上**同时设置多个时仅最后一个生效**，之前的被覆盖
- `backgroundBlurStyle`、`blur`、`backdropBlur` 是**实时模糊接口，每帧渲染，性能负载较高**。当模糊内容和半径都不需要变化时，**建议使用静态模糊接口**
- 通过 `backgroundBlurStyle` 的 `inactiveColor` 指定背景色时，**不建议再用 `backgroundColor`**

**`BlurStyle` 枚举全量：**

| 名称 | 值 | 说明 | 起始 |
|---|---|---|---|
| `Thin` | — | 轻薄材质模糊 | API 9 |
| `Regular` | — | 普通厚度材质模糊 | API 9 |
| `Thick` | — | 厚材质模糊 | API 9 |
| `BACKGROUND_THIN` | 3 | 近距景深模糊 | API 10 |
| `BACKGROUND_REGULAR` | 4 | 中距景深模糊 | API 10 |
| `BACKGROUND_THICK` | 5 | 远距景深模糊 | API 10 |
| `BACKGROUND_ULTRA_THICK` | 6 | 超远距景深模糊 | API 10 |
| `NONE` | 7 | 关闭模糊 | API 10 |
| `COMPONENT_ULTRA_THIN` | 8 | 组件超轻薄材质模糊 | API 11 |
| `COMPONENT_THIN` | 9 | 组件轻薄材质模糊 | API 11 |
| `COMPONENT_REGULAR` | 10 | 组件普通材质模糊 | API 11 |
| `COMPONENT_THICK` | 11 | 组件厚材质模糊 | API 11 |
| `COMPONENT_ULTRA_THICK` | 12 | 组件超厚材质模糊 | API 11 |

**《沉浸光感》官方档位选用建议（这是官方给的选型规则）：**

| 组件位置 | 推荐枚举 |
|---|---|
| 顶部悬浮 | `ULTRA_THIN` + 渐变模糊延展顶部空间 |
| 底部悬浮 | **`THIN`** + 渐变颜色蒙层延展底部空间 |
| 非常驻、任意位置弹出 | `THICK` |
| 半模态、弹出框（面积大、内容多） | `ULTRA_THICK` |

> ⚠️ 注意：官方文档把 `Ultra_Thin ~ Ultra_Thick` 说成"5 个层级枚举值"，但 `BlurStyle` 里 `COMPONENT_*` 实际是 **5 个**（ULTRA_THIN / THIN / REGULAR / THICK / ULTRA_THICK）。**"沉浸光感"这个品牌化特性本身是较新版本（HarmonyOS 6 时代）的能力**，API 12 可用的只是底层 `BlurStyle` 枚举。见第五部分。

```typescript
// xxx.ets
@Entry
@Component
struct BlurDemo {
  @State blurStyle: BlurStyle = BlurStyle.COMPONENT_THICK;

  build() {
    Stack() {
      // 背景内容（会被模糊）
      Image($r('app.media.bg'))
        .width('100%').height('100%')
        .objectFit(ImageFit.Cover)

      Column({ space: 16 }) {
        // ① 毛玻璃卡片（底部悬浮推荐 THIN）
        Column() {
          Text('今日碳足迹').fontSize(16).fontWeight(FontWeight.Medium)
        }
        .width('90%')
        .padding(16)
        .borderRadius(16)
        .backgroundBlurStyle(BlurStyle.COMPONENT_THIN)

        // ② 毛玻璃 + 不生效时的兜底背景色（API 10+）
        Column() {
          Text('降级兜底').fontSize(14)
        }
        .width('90%')
        .padding(16)
        .borderRadius(16)
        .backgroundBlurStyle(BlurStyle.COMPONENT_REGULAR, {
          inactiveColor: '#F1F3F5'   // 模糊不可用时的背景色
        })

        // ③ 内容模糊（模糊组件自身内容，不是背景）
        Text('这段文字会被模糊')
          .fontSize(20)
          .foregroundBlurStyle(BlurStyle.COMPONENT_THIN)

        // ④ 自定义半径的背景模糊（比枚举更细的控制）
        Column() {
          Text('自定义模糊').fontSize(14)
        }
        .width('90%')
        .padding(16)
        .borderRadius(16)
        .backdropBlur(10)                       // 参数为模糊半径
      }
      .width('100%')
    }
    .width('100%').height('100%')
  }
}
```

---

## 3.4 环形进度 `Progress({ type: ProgressType.Ring })`

**API 版本**：`Progress` **API 7 起**；`ProgressType.Ring` **API 7 起**；`RingStyleOptions`（`strokeWidth`/`shadow`/`status`）**API 10+**；用 `LinearGradient` 给 **Ring 上渐变色 API 10+**；`enableSmoothEffect` **API 10+**（`CommonProgressStyleOptions`）；`contentModifier` **API 12+**。→ **API 12 全部可用。**

**官方关键参数：**

| 属性 | 默认 | 说明 |
|---|---|---|
| `RingStyleOptions.strokeWidth` | **4.0vp** | 进度条宽度，不支持百分比。**当宽度 ≥ 半径时，自动改为半径的 1/2** |
| `RingStyleOptions.shadow` | `false` | 进度条阴影开关 |
| `RingStyleOptions.status` | `ProgressStatus.PROGRESSING` | 设为 `LOADING` 时开启检查更新动效，**此时 value 不生效** |
| `RingStyleOptions.enableSmoothEffect` | `true` | 进度平滑动效（从当前值渐变到设定值） |
| `RingStyleOptions.enableScanEffect` | `false` | 扫光效果（Linear/Ring/Capsule 支持） |
| `.color()` 默认值 | Ring：API 10+ 起 `#ff86c1ff` → `#ff254ff7`（**起始→结束的渐变**） | |

> ⚠️ **官方特别提示**："**Ring 类型不建议设置透明度，如需设置透明度，建议使用 DataPanel。**"

```typescript
// xxx.ets
@Entry
@Component
struct HeroRingDemo {
  @State progress: number = 0;
  private readonly target: number = 68;   // 今日目标完成度
  // API 10+ 起，Ring 支持 LinearGradient 做渐变描边
  private ringGradient: LinearGradient = new LinearGradient([
    { color: '#8BD8A6', offset: 0.0 },
    { color: '#1F9A4E', offset: 1.0 }
  ]);

  aboutToAppear(): void {
    // 进场动画：进度从 0 增长到 target
    this.getUIContext()?.animateTo({
      duration: 1200,
      curve: curves.springMotion()      // 官方推荐的物理曲线
    }, () => {
      this.progress = this.target;
    });
  }

  build() {
    Column() {
      // 英雄区：渐变底 + 圆角 32（官方"顶层/重点展示容器"档）
      Stack() {
        // 环形进度
        Progress({ value: this.progress, total: 100, type: ProgressType.Ring })
          .width(180)
          .height(180)
          .color(this.ringGradient)                 // 渐变描边（API 10+）
          .backgroundColor('#33FFFFFF')             // ⚠️ Progress 重写了 backgroundColor = 进度条底色
          .style({
            strokeWidth: 12,                        // 默认 4vp，这里加粗
            shadow: true,                           // 环形阴影
            enableSmoothEffect: true                // 进度平滑（默认就 true）
          })

        // 环内大数字（Display_M 48，官方 Light 字重）
        Column({ space: 2 }) {
          Row() {
            Text(this.progress.toFixed(0))
              .fontSize(48)                          // 官方 Display_M = 48
              .fontWeight(FontWeight.Light)          // 官方 Display 用 Light
              .fontColor(Color.White)
            Text('%')
              .fontSize(16)                          // 官方 Subtitle_M
              .fontWeight(FontWeight.Medium)
              .fontColor('#99FFFFFF')                // 官方 font_on_secondary
              .margin({ left: 2, bottom: 8 })
          }
          .alignItems(VerticalAlign.Bottom)

          Text('今日目标')
            .fontSize(12)                            // 官方 Caption_L
            .fontWeight(FontWeight.Medium)
            .fontColor('#66FFFFFF')                  // 官方 font_on_tertiary
        }
      }
      .width('100%')
      .height(240)
      .borderRadius(32)                              // 官方"超大圆角"，用于重点展示容器
      .linearGradient({
        angle: 135,
        colors: [['#1F9A4E', 0.0], ['#0E7A3C', 1.0]]
      })
    }
    .width('100%')
    .padding(16)                                     // 官方手机屏幕左右边距 16vp
    .backgroundColor('#F1F3F5')                      // 官方 background_secondary
  }
}
```

> ⚠️ **注意**：`Progress` **重写了通用属性 `backgroundColor`** —— 加在 `Progress` 上时它是**进度条底色**。要设整个 `Progress` 组件的背景色，**必须用外层容器包裹**。

**多段/纯色环替代写法：**
```typescript
// 纯色环
Progress({ value: 60, total: 100, type: ProgressType.Ring })
  .width(120).height(120)
  .color('#1F9A4E')
  .style({ strokeWidth: 10 })

// 带刻度环（ScaleRing）
Progress({ value: 50, total: 150, type: ProgressType.ScaleRing })
  .width(120)
  .color('#1F9A4E')
  .style({ strokeWidth: 20, scaleCount: 30, scaleWidth: 3 })

// loading 态
Progress({ value: 0, total: 100, type: ProgressType.Ring })
  .width(100).color('#1F9A4E')
  .style({ strokeWidth: 12, status: ProgressStatus.LOADING })
```

---

## 3.5 自定义绘制（`Canvas` / `Shape` / `Path`）

### 3.5.1 Canvas 画渐变环形进度

**API 版本**：`Canvas` **API 8 起**；`CanvasRenderingContext2D` 同。→ API 12 可用。

```typescript
// xxx.ets
@Entry
@Component
struct CanvasRingDemo {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @State percent: number = 0;
  private readonly size: number = 220;

  // 画一段圆弧（用 Canvas 做，可精确控制圆头端点）
  private drawRing(p: number): void {
    const cx = this.size / 2;
    const cy = this.size / 2;
    const r = this.size / 2 - 14;
    const lineW = 14;
    const start = -Math.PI / 2;                     // 从 12 点方向开始
    const end = start + Math.PI * 2 * (p / 100);

    this.ctx.clearRect(0, 0, this.size, this.size);

    // 底环
    this.ctx.beginPath();
    this.ctx.arc(cx, cy, r, 0, Math.PI * 2);
    this.ctx.strokeStyle = '#E6F4EC';
    this.ctx.lineWidth = lineW;
    this.ctx.stroke();

    // 进度环（渐变描边）
    const g = this.ctx.createLinearGradient(0, 0, this.size, this.size);
    g.addColorStop(0.0, '#8BD8A6');
    g.addColorStop(1.0, '#1F9A4E');

    this.ctx.beginPath();
    this.ctx.arc(cx, cy, r, start, end);
    this.ctx.strokeStyle = g;
    this.ctx.lineWidth = lineW;
    this.ctx.lineCap = 'round';                     // 圆头端点 —— 官方图标规范也是"终点样式：圆头"
    this.ctx.stroke();
  }

  aboutToAppear(): void {
    setTimeout(() => {
      this.getUIContext()?.animateTo({ duration: 1000, curve: curves.springMotion() }, () => {
        this.percent = 68;
      });
    }, 100);
  }

  build() {
    Column() {
      Stack() {
        Canvas(this.ctx)
          .width(this.size)
          .height(this.size)
          .onReady(() => {
            this.drawRing(this.percent);
          })
        // 注：Canvas 不会随 @State 自动重绘，需要在状态变化处显式调用 drawRing
        Text(`${this.percent}%`)
          .fontSize(38)                             // 官方 Display_S
          .fontWeight(FontWeight.Light)
          .fontColor('#1F9A4E')
      }
      .onAreaChange(() => {
        this.drawRing(this.percent);                // 状态变化后重绘
      })
    }
    .width('100%').padding(16).backgroundColor('#F1F3F5')
  }
}
```

**Canvas 常用 API（已核实存在）**：`beginPath()` / `arc(x,y,r,startAngle,endAngle)` / `stroke()` / `fill()` / `moveTo` / `lineTo` / `closePath` / `strokeStyle` / `fillStyle` / `lineWidth` / **`lineCap`（`'butt' | 'round' | 'square'`）** / `createLinearGradient` / `addColorStop` / `clearRect` / `fillText(text,x,y)` / `strokeText` / `measureText(text).width/.height` / `font` / `textBaseline` / `strokeRect`

> ⚠️ **Canvas 不会跟随 `@State` 自动重绘**。必须在 `onReady` 里首绘，并在数据变化时**显式**重新调用绘制函数（常用 `onAreaChange` 或数据变更回调）。这是 Canvas 相比 `Progress` 最大的代价 —— **如果你的环只需要单色/简单渐变，用 `Progress` + `LinearGradient` 更省事**。

### 3.5.2 Shape / Path 画环形与迷你图

**API 版本**：`Path` **API 7 起**，`commands` 符合 **SVG 路径描述规范，单位 px**。

```typescript
// xxx.ets
@Entry
@Component
struct ShapeDemo {
  build() {
    Column({ space: 20 }) {

      // ① Path 画折线（迷你趋势图 sparkline）
      //    M=moveto  L=lineto  C=三次贝塞尔  Q=二次贝塞尔  A=圆弧  Z=闭合
      //    ⚠️ Path commands 单位是 px
      Shape() {
        Path()
          .commands('M0 60 L30 45 L60 50 L90 30 L120 35 L150 12')
          .strokeWidth(3)
          .stroke('#1F9A4E')
          .fillOpacity(0)                     // 只描边不填充
          .strokeLineCap(LineCapStyle.Round)  // 圆头
          .strokeLineJoin(LineJoinStyle.Round)
      }
      .width(150)
      .height(80)
      .viewPort({ x: 0, y: 0, width: 150, height: 80 })   // viewPort 定义内部坐标系

      // ② Path 画带渐变填充的面积图
      Shape() {
        Path()
          .commands('M0 60 L30 45 L60 50 L90 30 L120 35 L150 12 L150 80 L0 80 Z')
          .fill('#331F9A4E')
          .stroke('#1F9A4E')
          .strokeWidth(2)
      }
      .width(150).height(80)
      .viewPort({ x: 0, y: 0, width: 150, height: 80 })

      // ③ Shape + Circle 画简单环形（纯描边圆）
      Shape() {
        Circle({ width: 100, height: 100 })
          .fillOpacity(0)
          .stroke('#1F9A4E')
          .strokeWidth(10)
      }
      .width(100).height(100)

      // ④ 用 Path 的 A 命令画进度弧（可选方案）
      //    A rx ry x-axis-rotation large-arc-flag sweep-flag x y
      Shape() {
        Path()
          .commands('M 60 10 A 50 50 0 1 1 20 78')
          .fillOpacity(0)
          .stroke('#1F9A4E')
          .strokeWidth(10)
          .strokeLineCap(LineCapStyle.Round)
      }
      .width(120).height(120)
      .viewPort({ x: 0, y: 0, width: 120, height: 120 })
    }
    .width('100%').padding(16).backgroundColor('#F1F3F5')
  }
}
```

**SVG 路径命令（官方支持清单）**：`M`（moveto）/ `L`（lineto）/ `H`（水平线）/ `V`（垂直线）/ `C`（三次贝塞尔）/ `S`（平滑三次）/ `Q`（二次贝塞尔）/ `T` / `A`（圆弧）/ `Z`（闭合）

> 💡 **Canvas vs Shape 怎么选**：
> - **静态/半静态图**（迷你趋势图、装饰弧）→ **`Shape`/`Path`**，声明式，随状态自动更新
> - **需要每帧重算的复杂图形** → **`Canvas`**
> - **标准环形进度** → **`Progress`**（最省事，且自带平滑动效）

---

## 3.6 动效

### 3.6.1 `animateTo` 与 `AnimateParam`

**API 版本**：`animateTo` **API 7 起**；`keyframeAnimateTo` **API 11 起**。→ API 12 可用。

**官方建议（原文）**："直接使用 `animateTo` 可能导致 UI 上下文不明确的问题，**建议使用 `getUIContext()` 获取 `UIContext` 实例，并使用 `animateTo` 调用绑定实例的 `animateTo`**。"

**`AnimateParam` 全量字段：**

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `duration` | `number` | **1000** | 毫秒。**`curve` 配弹簧类曲线时 duration 不生效** |
| `tempo` | `number` | 1.0 | 播放速度倍数 |
| `curve` | `Curve \| string \| ICurve` | `Curve.EaseInOut` | 见下方 |
| `delay` | `number` | 0 | 毫秒。负值表示提前播放 |
| `iterations` | `number` | 1 | `-1` 无限次；`0` 无动画 |
| `playMode` | `PlayMode` | `Normal` | `Normal` / `Alternate` / `Reverse` / `AlternateReverse` |
| `onFinish` | `() => void` | — | 播放完成回调 |

**`curve` 传字符串时的合法值（官方全量）：**

```
"linear"  "ease"  "ease-in"  "ease-out"  "ease-in-out"
"fast-out-slow-in"(标准)  "linear-out-slow-in"(减速)  "fast-out-linear-in"(加速)
"friction"(阻尼)  "extreme-deceleration"(极缓)  "rhythm"(节奏)  "sharp"(锐利)  "smooth"(平滑)
"cubic-bezier(x1,y1,x2,y2)"
"steps(number,step-position)"
"spring-motion(response,dampingFraction,overlapDuration)"
"responsive-spring-motion(...)"   "interpolating-spring(...)"   "spring(...)"
```

### 3.6.2 `@ohos.curves` / `@kit.ArkUI` 的 curves

**弹簧曲线（官方推荐优先使用 —— "建议优先采用物理曲线创建动画，将传统曲线作为辅助用于极少数必要场景"）：**

| 函数 | 签名 | 说明 |
|---|---|---|
| `curves.springMotion` | `(response?: number, dampingFraction?: number, overlapDuration?: number) => ICurve` | 弹性动画。**时长由曲线参数、属性变化值大小和弹簧初速度自动计算，指定的 duration 不生效**。不提供速度设置，速度通过继承获得 |
| `curves.responsiveSpringMotion` | 同上签名 | `springMotion` 的特例，仅默认参数不同。**一般用于跟手动画**；离手时用 `springMotion`，会自动继承跟手阶段速度 |
| `curves.interpolatingSpring` | `(velocity: number, mass: number, stiffness: number, damping: number) => ICurve` | 适合**需要指定初速度**的场景。时长自动计算，`duration` 不生效。速度是**归一化速度** |
| `curves.springCurve` | `(velocity, mass, stiffness, damping) => ICurve` | 适合**需要直接指定动画时长**的场景。⚠️ 官方"**不建议开发者使用**"（会把物理时长映射到指定时长，破坏物理规律） |

**传统曲线**：`curves.cubicBezierCurve(x1, y1, x2, y2)` 为代表，另有阶梯曲线。
**`Curve` 枚举（官方示例里出现）**：`Curve.Linear` / `Ease` / `EaseIn` / `EaseOut` / `EaseInOut` / `FastOutSlowIn`

```typescript
// xxx.ets
import { curves } from '@kit.ArkUI';

@Entry
@Component
struct AnimDemo {
  @State bigNumber: number = 0;       // 用于数字滚动
  @State progress: number = 0;
  @State scaleValue: number = 1;
  @State translateY: number = 20;
  @State opacityValue: number = 0;

  aboutToAppear(): void {
    // ① 进场：数字滚动 + 环增长 + 卡片上浮（一个 animateTo 驱动多个属性）
    this.getUIContext()?.animateTo({
      curve: curves.springMotion(0.55, 0.825),   // response, dampingFraction
      delay: 100,
      onFinish: () => {
        console.info('进场动画完成');
      }
    }, () => {
      this.bigNumber = 24.6;
      this.progress = 68;
      this.translateY = 0;
      this.opacityValue = 1;
    });
  }

  build() {
    Column({ space: 20 }) {
      // ② 大数字 + 环（随 @State 变化走动画）
      Stack() {
        Progress({ value: this.progress, total: 100, type: ProgressType.Ring })
          .width(140).height(140)
          .color('#1F9A4E')
          .style({ strokeWidth: 12 })
        Text(this.bigNumber.toFixed(1))
          .fontSize(38)                          // 官方 Display_S
          .fontWeight(FontWeight.Light)
      }

      // ③ 按压反馈：interactive_pressed 的等效做法
      Column() {
        Text('记一笔').fontSize(16).fontColor(Color.White)
      }
      .width('100%').height(48)
      .borderRadius(20)                          // 官方"按钮"圆角档位
      .backgroundColor('#1F9A4E')
      .scale({ x: this.scaleValue, y: this.scaleValue })
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.getUIContext()?.animateTo({ curve: curves.springMotion(0.3, 0.9) }, () => {
            this.scaleValue = 0.96;
          });
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.getUIContext()?.animateTo({ curve: curves.springMotion(0.3, 0.9) }, () => {
            this.scaleValue = 1.0;
          });
        }
      })

      // ④ animation 属性动画：无需闭包，属性变化自动带动画
      //    注意：animation 仅作用于"在其之上调用"的属性
      Column()
        .width(60).height(60)
        .borderRadius(8)                          // 官方"图片/图标"圆角档位
        .backgroundColor('#8BD8A6')
        .rotate({ angle: this.progress * 3.6 })
        .animation({ curve: curves.springMotion(), iterations: -1 })

      // ⑤ 自定义三次贝塞尔（传统曲线）
      Column()
        .width('100%').height(4)
        .backgroundColor('#1F9A4E')
        .scale({ x: this.progress / 100, y: 1 })
        .animation({ duration: 600, curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1) })
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#F1F3F5')
    .translate({ y: this.translateY })
    .opacity(this.opacityValue)
  }
}
```

**官方动效选型对照（三种属性动画接口）：**

| 接口 | 作用域 | 适用场景 |
|---|---|---|
| `animateTo` | 闭包内改变属性引起的界面变化 | 多个可动画属性配**相同**动画参数；命令式显式触发；**需要嵌套**的场景 |
| `animation` | 组件通过属性接口绑定的属性变化 | 对不同属性配**不同**参数；希望**隐式**触发。**仅作用于在其之上调用的属性** |
| `keyframeAnimateTo` (API 11+) | 多个闭包内改变属性 | 同一属性做**连续多段**动画 |

---

## 3.7 图标：`SymbolGlyph` 与替代方案

### 3.7.1 SymbolGlyph（API 11+，本工程可用）

```typescript
// xxx.ets
@Entry
@Component
struct SymbolDemo {
  @State isLiked: boolean = false;
  @State tabIndex: number = 0;
  @State bounceTrigger: number = 0;

  build() {
    Column({ space: 24 }) {

      // ① 基础用法
      //    ⚠️ 仅支持系统预置 symbol 资源名，引用非 symbol 资源会显示异常
      SymbolGlyph($r('sys.symbol.ohos_trash'))
        .fontSize(24)                              // 24vp 图标尺寸 = 官方标准图标尺寸
        .fontColor([Color.Black])

      // ② 单色策略
      SymbolGlyph($r('sys.symbol.bolt_fill'))
        .fontSize(24)
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontColor(['#1F9A4E'])

      // ③ 分层策略（第一层 100%，第二层 50% 不透明度）
      SymbolGlyph($r('sys.symbol.ohos_folder_badge_plus'))
        .fontSize(48)
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_OPACITY)
        .fontColor(['#1F9A4E'])

      // ④ 多色策略（生效两种颜色）
      SymbolGlyph($r('sys.symbol.ohos_folder_badge_plus'))
        .fontSize(48)
        .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
        .fontColor(['#1F9A4E', '#8BD8A6'])

      // ⑤ 粗细无极变化（与字体一致）
      SymbolGlyph($r('sys.symbol.heart'))
        .fontSize(28)
        .fontWeight(FontWeight.Light)

      // ⑥ 预置动效（NONE / SCALE / HIERARCHICAL，设置后自动播放）
      SymbolGlyph($r('sys.symbol.ohos_wifi'))
        .fontSize(32)
        .effectStrategy(SymbolEffectStrategy.HIERARCHICAL)

      // ⑦ 可控制播放状态的动效（API 12）—— 收藏心跳
      SymbolGlyph(this.isLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
        .fontSize(28)
        .fontColor([this.isLiked ? '#E84026' : '#66000000'])
        .symbolEffect(
          new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP),
          this.bounceTrigger
        )
        .onClick(() => {
          this.isLiked = !this.isLiked;
          this.bounceTrigger++;
        })
    }
    .width('100%').padding(16).backgroundColor('#F1F3F5')
  }
}
```

**可用的动效类（API 12）**：`HierarchicalSymbolEffect(EffectFillStyle)` / `BounceSymbolEffect(EffectScope, EffectDirection)` / `ReplaceSymbolEffect(EffectScope)` / `ScaleSymbolEffect` / `PulseSymbolEffect` / `AppearSymbolEffect` / `DisappearSymbolEffect`
**❌ API 12 不可用**：`ReplaceEffectType.SLASH_OVERLAY`、`ReplaceEffectType.CROSS_FADE`（**API 20+**）、`.symbolShadow()`（**API 20+**）、`.shaderStyle()`（**API 20+**）

**`SymbolSpan`（图标与文本混排）：**
```typescript
Text() {
  Span('今日减排 ')
  SymbolSpan($r('sys.symbol.bolt_fill'))
    .fontSize(16)
    .fontColor(['#1F9A4E'])
  Span(' 2.4 kg')
}
.fontSize(16)
// ⚠️ SymbolSpan 需嵌入 Text 才能显示，单独使用不呈现任何内容
// ⚠️ SymbolSpan 不支持通用事件
```

### 3.7.2 替代方案（官方 Symbol 库缺少"叶子/树/CO₂/图表"图标时）

**方案 A：`Image` + SVG 资源（推荐）**
把自绘的 SVG 放进 `src/main/resources/base/media/`，然后：

```typescript
// 普通显示
Image($r('app.media.ic_leaf'))
  .width(24).height(24)
  .objectFit(ImageFit.Contain)

// ✅ 用 fillColor 给单色 SVG 动态改色（关键能力）
Image($r('app.media.ic_leaf'))
  .width(24).height(24)
  .fillColor('#1F9A4E')         // 只对单色 SVG 生效

// 从 rawfile 加载并用 fillColor 改色
Image($rawfile('ic_leaf.svg'))
  .width(24).height(24)
  .fillColor('#66000000')
```

**方案 B：`canvas` / `Path` 自绘矢量图形**（见 3.5.2）

**方案 C：把自绘图标做成字体**（官方支持自定义 Symbol 注册，`ui-design-custom-symbol-res-register` 文档，但**该能力属于较新版本**，API 12 上建议不要依赖）

> 📌 **实操建议**：碳足迹 App 的图标分两层
> - **通用 UI 图标**（首页/我的/设置/搜索/返回/通知/勾选）→ **直接用 `SymbolGlyph`**，省资源、自动跟主题色、有动效，且和系统观感一致
> - **品牌语义图标**（叶子、树、CO₂、碳循环）→ **自备单色 SVG** + `.fillColor()` 动态改色
> 这样既拿到 Symbol 的精致度，又不受官方图标库语义缺失的限制。

---

## 3.8 字体

**API 版本**：`fontFamily()` / `fontWeight()` / `lineHeight()` / `letterSpacing()` / `textAlign()` 均 **API 7 起**。→ API 12 可用。

```typescript
// xxx.ets
@Entry
@Component
struct FontDemo {
  build() {
    Column({ space: 16 }) {

      // ① 默认系统字体（HarmonyOS Sans）—— 官方推荐直接用，不要额外指定
      Text('今日碳足迹').fontSize(24).fontWeight(FontWeight.Bold)     // 官方 Title_M

      // ② 显式指定字体族
      Text('HarmonyOS Sans').fontFamily('HarmonyOS Sans')
      Text('HarmonyOS Sans SC').fontFamily('HarmonyOS Sans SC')

      // ③ 官方字重阶梯（对应 Thin / UltraLight / Light / Regular / Medium / SemiBold / Bold / Heavy / Black）
      Text('Thin').fontWeight(FontWeight.Lighter)        // 最细
      Text('Light').fontWeight(FontWeight.Light)         // 官方 Display 用
      Text('Regular').fontWeight(FontWeight.Regular)     // 官方 Body_M 用
      Text('Medium').fontWeight(FontWeight.Medium)       // 官方 Subtitle/Body_L 用
      Text('SemiBold').fontWeight(FontWeight.Medium)     // 见下方说明
      Text('Bold').fontWeight(FontWeight.Bold)           // 官方 Title 用
      Text('Bolder').fontWeight(FontWeight.Bolder)       // 更粗

      // ④ 完整排版组合（官方 Body_M）
      Text('骑行 5 公里，减排 0.6 kg CO₂')
        .fontSize(14)                                    // 官方 Body_M = 14
        .fontWeight(FontWeight.Regular)
        .fontFamily('HarmonyOS Sans')
        .lineHeight(22)
        .letterSpacing(0)
        .textAlign(TextAlign.Start)
        .fontColor('#99000000')                          // 官方 font_secondary

      // ⑤ 数字用等宽数字特性，避免跳动
      //    官方《鸿蒙黑体》提到系统字体支持 tnum（等宽数字）特性 Tag
      Text('1234.56')
        .fontSize(48)                                    // 官方 Display_M
        .fontWeight(FontWeight.Light)                    // 官方 Display 用 Light
        .fontColor('#E5000000')
    }
    .width('100%').padding(16).backgroundColor('#F1F3F5')
  }
}
```

**自定义字体（`registerFont`）：**
```typescript
// 在 EntryAbility 的 onWindowStageCreate 之前，或页面 aboutToAppear 中
import { font } from '@kit.ArkUI';

// 方式一：注册单个字体
font.registerFont({
  familyName: 'MyBrandFont',
  familySrc: $rawfile('MyBrandFont.ttf')
});

// 注册后使用
Text('品牌字体文案').fontFamily('MyBrandFont')
```

**官方对自定义字体的态度（《文本排版》原文）**："如果系统默认字体风格无法满足您的诉求，例如为了宣传品牌或者创造沉浸式的游戏体验，您可以使用自定义字体，**但需要确保用户可在不同视距和各种条件下都能轻松阅读**。"

> ⚠️ **字重取值注意**：ArkUI 的 `FontWeight` 枚举是 `Lighter / Normal / Regular / Medium / Bold / Bolder`，**没有** `SemiBold`。若需 SemiBold，用 `fontWeight(600)` 这类**数字值**（ArkUI 支持 `number` 字重），或直接用 `FontWeight.Medium` 近似。
> **中文可用字体**：系统默认 `HarmonyOS Sans` 完整支持简繁中文。**我没有找到官方文档列出"除 HarmonyOS Sans 外还有哪些内置中文字体"** —— 见第五部分。

---

## 3.9 其他质感增强

```typescript
// xxx.ets
@Entry
@Component
struct PolishDemo {
  @State selected: boolean = false;

  build() {
    Column({ space: 16 }) {

      // ① 边框（radius 缺省时，borderRadius 必须写在 border 之后才生效）
      Column().width('100%').height(48)
        .border({ width: 1, color: '#33000000', radius: 16, style: BorderStyle.Solid })
      // ✅ 或者拆开写更稳
      Column().width('100%').height(48)
        .border({ width: 1, color: '#33000000' })
        .borderRadius(16)

      // ② 外描边（不占布局空间，画在组件外部 —— 做聚焦态很合适）
      Column().width('100%').height(48)
        .backgroundColor(Color.White)
        .borderRadius(16)
        .outline({ width: 2, color: '#1F9A4E', style: OutlineStyle.SOLID, radius: 16 })

      // ③ 形状裁剪（配合圆角用，注意会裁掉阴影）
      Column() {
        Image($r('app.media.bg')).width('100%').height('100%').objectFit(ImageFit.Cover)
      }
      .width('100%').height(120)
      .borderRadius(16)
      .clip(true)

      // ④ 遮罩
      Column().width('100%').height(60)
        .backgroundColor('#1F9A4E')
        .mask(new Circle({ width: 60, height: 60 }).fill(Color.White))

      // ⑤ 混合模式（做"高亮叠色"、"正片叠底"效果）
      Column().width('100%').height(60)
        .backgroundColor('#1F9A4E')
        .blendMode(BlendMode.MULTIPLY)

      // ⑥ 图像效果全家桶
      Image($r('app.media.bg'))
        .width('100%').height(120)
        .borderRadius(16)
        .grayscale(0.3)          // 灰度 0~1
        .brightness(1.1)         // 亮度，1 无变化，>1 变亮
        .saturate(1.2)           // 饱和度，1 无变化
        .blur(4)                 // 内容模糊
        .opacity(0.9)

      // ⑦ 选中态用"10% 高亮底色"（官方 comp_emphasize_tertiary 的思路）
      Text('已达成')
        .fontSize(12)                                   // 官方 Caption_L
        .fontWeight(FontWeight.Medium)
        .fontColor('#1F9A4E')
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })   // 官方主次文本左右间隔 8vp
        .borderRadius(4)                                // 官方"标签"圆角 4vp
        .backgroundColor(this.selected ? '#331F9A4E' : '#191F9A4E')  // 20% / 10%

      // ⑧ 分割线用官方 comp_divider
      Divider().color('#33000000').strokeWidth(0.5)
    }
    .width('100%').padding(16).backgroundColor('#F1F3F5')
  }
}
```

**`BlendMode` 可用枚举（API 11+，节选）**：`NONE` / `CLEAR` / `SRC` / `DST` / `SRC_OVER` / `DST_OVER` / `SRC_IN` / `DST_IN` / `SRC_OUT` / `DST_OUT` / `SRC_ATOP` / `DST_ATOP` / `XOR` / `PLUS` / `MODULATE` / `SCREEN` / `OVERLAY` / `DARKEN` / `LIGHTEN` / `COLOR_DODGE` / `COLOR_BURN` / `HARD_LIGHT` / `SOFT_LIGHT`

**图像效果可用方法**：`grayscale(number)` / `brightness(number)` / `saturate(number)` / `blur(number)` / `opacity(number)` / `contrast(number)` / `invert(number)` / `sepia(number)` / `hueRotate(number|string)` / `colorBlend(...)` / `lightUpEffect(number)` / `pixelStretchEffect(...)` / `shadow(...)`

---

## 3.10 底部页签美化（`Tabs`）

**API 版本**：`barBackgroundBlurStyle` / `barOverlap` 均为 **API 10 起**。→ API 12 可用。
**官方推荐的毛玻璃组合（原文）**："通过设置 Tabs 组件的 `barOverlap` 属性，可以实现 TabBar 变模糊并叠加在 TabContent 之上，并且配合 `barBackgroundBlurStyle` 属性实现毛玻璃效果。"

```typescript
// xxx.ets
@Entry
@Component
struct TabBarDemo {
  @State currentIndex: number = 0;
  private controller: TabsController = new TabsController();

  // 自定义页签：图标 + 文字
  @Builder
  tabBuilder(index: number, name: string, icon: Resource) {
    Column() {
      SymbolGlyph(icon)
        .fontSize(24)                                  // 官方标准图标 24vp
        .fontColor([this.currentIndex === index ? '#1F9A4E' : '#66000000'])
        .symbolEffect(
          new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.UP),
          this.currentIndex === index                   // 选中时播放弹跳
        )
      Text(name)
        .margin({ top: 4 })
        .fontSize(10)                                  // 官方 Caption_M
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentIndex === index ? '#1F9A4E' : '#66000000')
    }
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height(56)                                        // 官方列表"效率型"高度档位之一
  }

  build() {
    Tabs({ barPosition: BarPosition.End, controller: this.controller }) {
      TabContent() {
        Text('记一笔').fontSize(20)
      }.tabBar(this.tabBuilder(0, '记一笔', $r('sys.symbol.plus_circle')))

      TabContent() {
        Text('看板').fontSize(20)
      }.tabBar(this.tabBuilder(1, '看板', $r('sys.symbol.bolt_filled_on_circle')))

      TabContent() {
        Text('积分').fontSize(20)
      }.tabBar(this.tabBuilder(2, '积分', $r('sys.symbol.star_fill')))

      TabContent() {
        Text('科普').fontSize(20)
      }.tabBar(this.tabBuilder(3, '科普', $r('sys.symbol.book_open_fill')))

      TabContent() {
        Text('我的').fontSize(20)
      }.tabBar(this.tabBuilder(4, '我的', $r('sys.symbol.person')))
    }
    .barMode(BarMode.Fixed)
    .barBackgroundColor('#F1F3F5')
    .barBackgroundBlurStyle(BlurStyle.COMPONENT_THICK)  // 毛玻璃（官方：底部悬浮推荐 THIN，此处更厚以便文字清晰）
    .barOverlap(true)                                   // TabBar 叠加在内容之上
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])  // 延展到底部安全区
    .onChange((index: number) => {
      this.currentIndex = index;
    })
    .width('100%')
    .height('100%')
  }
}
```

**其他 TabBar 能力（官方文档确认存在）：**
- `.fadingEdge(true)` —— TabBar 边缘渐隐（顶部导航栏页签靠近两侧模糊化）
- `controller.setTabBarTranslate({x, y})` / `controller.setTabBarOpacity(number)` —— 平移与透明度
- `Tabs({ barModifier: this.tabBarModifier })` —— 通过 `CommonModifier` 设置对齐、`clip(false)` 实现页签超出 TabBar 区域

---

# 第四部分 · 视觉参考（请注意本节的来源等级）

## 4.1 ⚠️ 先说清楚：这一节我**没能**拿到可验证的竞品数据

**搜索通道实际情况（实测）：**

| 通道 | 结果 |
|---|---|
| `web_search` 工具 | ❌ 不可用（API key 401） |
| Google / DuckDuckGo / Brave / Ecosia / Startpage | ❌ 网络不通（HTTP 000） |
| Bing（HTML 与 RSS） | ✅ 可访问，但**索引质量极差**：搜"蚂蚁森林 首页 设计"返回的是"蚂蚁（膜翅目蚁科动物）_百度百科"、"蚂蚁种类_百度百科" |
| 搜狗 | ✅ 首次可用（拿到了蚂蚁森林设计升级的相关结果），**第二次起触发 antispider 反爬** |
| 360 搜索 (so.com) | ✅ 可访问，但对设计类查询返回的是**文库/论文**（"碳足迹可视化设计-360文库"、"基于八角行为分析框架的个人碳足迹类App设计研究-豆丁网"），**不是设计稿或色值** |
| 站酷 ZCOOL | ✅ 页面可达，但**结果由客户端 JS 加载**，`__NEXT_DATA__` 里没有搜索结果数据 |
| UI 中国 | ❌ 403 |
| 知乎 | ❌ 403 |
| Bilibili 搜索 / Mojeek | ✅ 可达，未产出相关内容 |

**结论：我没有获取到任何一个竞品 App 的真实截图、色值或设计标注。因此本节不提供"某某 App 用的是 #XXXXXX"这类信息 —— 那会是我编的。**

**唯一一条我实际读到的、关于竞品视觉手法的描述**（来自搜狗搜索结果为"打动人心的真实-蚂蚁森林设计升级"的摘要片段，**我没有成功打开原文，因此这只是摘要级证据，置信度低**）：

> "……我们可以用**图形、配色、质感和视角**这样四个要素来进行设计……经过多版本尝试，我们把改版的视觉风格定位在了"**微质感**"上……通过**减少大面积几何色块**，并合理**增加阴影、高光反射面**，可以有效塑……"

**这条摘要里有价值的一点**（如果为真）：蚂蚁森林改版走的是**"减少大面积几何色块 + 增加阴影/高光"**的路径。这与本报告 T6（卡片分级）和 T2（补语义色）的方向一致 —— **不是靠加更多颜色和更花的元素，而是靠"质感"和"层次"**。但这**不是**我可以背书的事实。

另有一条（同样只是搜索摘要）：**"2020年UI设计的10个趋势"** 摘要提到"**圆角卡片** 圆角代表友好、亲和力；而卡片模块化的布局更为清晰、有效、整洁" —— 泛泛而谈，参考价值有限。

---

## 4.2 官方规范里的"参考"：官方是怎么要求好设计的（这部分是**官方来源**）

既然拿不到竞品数据，我用**华为官方文档里对真实上架应用的设计要求**来替代。这些是官方白纸黑字写的，比我的个人偏好可靠：

### 4.2.1 官方对"配色策略"的硬性要求（来自《鸿蒙卡片》）

| 维度 | 官方要求 |
|---|---|
| **配色数量** | **主色相不能超过 3 种**；核心颜色 **1-2 个且占比最大**；辅助色仅作丰富画面和点缀，**不可喧宾夺主** |
| **配色舒适度** | 整体明度、饱和度、对比度适中；**主色色彩明度 + 饱和度 < 180** |
| **禁止事项** | 避免使用**大量高饱和度**的颜色；避免**主色相过多** |
| **用色克制** | "用色需要克制，保证画面配色和谐统一" |
| **业务特征** | 颜色传递的情绪应符合业务调性（金融重信赖感、消费重活力感、儿童重亲和力） |
| **文字对比** | 文字与背景对比度 **≥1:3** |

### 4.2.2 官方对"层次"的要求（来自《鸿蒙卡片》《深色模式》）

| 维度 | 官方要求 |
|---|---|
| **突出主体** | "识别主体信息，并在视觉上突出展示。**多个并列核心信息时，使用相同的视觉形式**能达到整体突出的效果。**背景信息弱化处理**，在视觉上凸显主体" |
| **层次清晰** | "**重要的并列元素建议控制在 3-5 个**，其他非主要元素可使用 7 个左右。若并列元素过多，建议使用**组块**作为区分" |
| **构图** | "画面主体突出并占据画面主要位置，比例合理"；"多个主体物情况下**不超过 3 个**，且**主体物面积不超过画面的 60%**" |
| **层级一致性（深色模式）** | "浅色模式下明度不是唯一的表达层级的视觉线索，而在深色模式尤其是在黑色背景上，**用户对投影的感知程度降低，通常使用明度表达层级**，因此不同层级之间需要有一定的**明度区分**，并与浅色模式感知一致" |
| **色彩语义一致性** | 深色模式下，表示警示等具有语义信息的颜色**需要保持一致**，可以在保持色相一致的前提下对明度进行调整 |
| **同类控件风格一致性** | 深色模式下，不同应用或不同页面中的**同类控件，视觉风格（颜色、形状等）保持一致** |

### 4.2.3 官方对"数据可视化"的要求（来自《数据可视化》）

| 维度 | 官方要求 |
|---|---|
| **选型** | 数据组别多 → **多个线形进度条组合**；单个数据占比 → **优先使用环形**；范围类 → **Gauge 组件** |
| **颜色语义** | "数据条控件的颜色应与所展示数据的含义相符，**如绿色表示上升，红色表示下降**" |
| **分类色彩** | 数据分类较多时 → 提供**多个分类明显的色彩**；存在多条数据线时 → **每条线分配独特的颜色** |
| **渐变** | "也可以根据数据含义**使用渐变色等视觉效果**，增强数据可读性和色彩的细腻程度" |
| **线宽** | "数据条的**线条宽度应与屏幕尺寸相适应，避免过粗或过细**" |
| **线形圆角** | 默认 **4vp 小圆角** |

### 4.2.4 官方对"英雄区"的处理（这是我能找到的最接近"英雄区"的官方指引）

官方《服务卡片》文档里对**卡片内的数字展示**给了明确档位，这正好就是"大数字 + 环形进度"的做法：

- **数字字体支持 20、32、40fp 等不同档位**（2×2 卡片推荐 **32、40fp**）
- 标题 18、14fp，**距卡片左上角 12vp**
- 字体规范里 **Display_L/M/S = 56/48/38vp，字重 Light** —— **用 Light 而非 Bold 做超大数字**，这是官方给的规格
- 数字配 `Caption_L 12fp` 副标题

### 4.2.5 官方对"沉浸感/毛玻璃"的档位选用（来自《沉浸光感》）

| 组件位置 | 推荐档位 |
|---|---|
| 顶部悬浮 | `ULTRA_THIN` + 渐变模糊 |
| **底部悬浮** | **`THIN`** + 渐变颜色蒙层 |
| 任意位置弹出 | `THICK` |
| 半模态/弹出框 | `ULTRA_THICK` |

官方还给了**使用场景的判断标准**："原则上，我们建议，**当某些界面操作元素在交互过程中可能存在与内容区产生重叠情况时，使用沉浸光感效果**能够大幅度提高页面的视觉体验，**强化页面 Z 轴空间感**，从纵向空间分离开内容与交互组件。"

### 4.2.6 官方对"宽屏/响应式"的要求（来自官方《便捷生活类》案例）

- 首页自适应：宽屏上可一排显示更多图标，但**折叠屏不超过一排 8 个，平板横屏不超过一排 12 个**
- 折叠屏展开态**3 列宫格**最佳；平板横屏默认**5 列宫格**最佳
- 分栏比例：折叠屏 **1:1**，平板 **4:6**
- 半模态窗口高度动态变化：**最低不低于 320vp，最高不超过 90% 屏幕短边宽度**

---

## 4.3 我的设计建议（明确标注：以下**不是**官方要求，也没有竞品数据支撑，是我的判断）

> 按你的要求，这部分与官方规范清楚分开。

1. **"平庸"的根因不是颜色，是层次缺失。**
   你现在所有卡片 `radius 14`、同一种白、同一种阴影（或没阴影）、所有文字同一个黑。这导致**信息没有主次**。我建议**先做 T1 + T6**（四级文本色 + 卡片三级），这两条做完观感变化最明显，而且不需要重写业务逻辑。

2. **不要为了"高级"而把主色换成蓝色。**
   官方 `brand` 是宇宙蓝，但那是**系统主题色**。官方明确说"**应用可定制属于自己品牌色色调**"（《色彩》原文）。碳足迹用绿色是对的品牌语义，**问题在于你只用了一种绿**。建议：
   - 保留绿做主色，但**建一条绿的梯度**（如 `#0E7A3C` 深 → `#1F9A4E` 主 → `#8BD8A6` 浅 → `#E6F4EC` 极浅底）
   - **同时**接入官方语义色 `warning #E84026` / `alert #ED6F21` / `confirm #64BB5C` 用于"超标/注意/达成"
   - 这样主色相仍然只有 1 个（符合官方"主色相不超过 3 种"），但色彩层次丰富了

3. **英雄区值得单独设计，不要复用普通卡片的样式。**
   官方圆角规范说"层级越高圆角越大"，官方字号规范有 38/48/56 的 Light 档位 —— 两者结合就是：**一张 32vp 圆角的渐变卡 + 48vp Light 大数字 + 环形进度**。这是首屏唯一该"用力"的地方。

4. **动效要"物理"不要"机械"。**
   官方明确"**建议优先采用物理曲线创建动画**，将传统曲线作为辅助用于极少数必要场景中"，且"采用弹簧曲线的动画在**达终点时动画速度为 0**，不会产生动画'戛然而止'的观感"。所以用 `curves.springMotion()` 而不是 `Curve.EaseInOut`。

5. **深色模式要提前规划，否则改动量翻倍。**
   官方明确深色模式**不能靠阴影表达层级，要靠明度**。如果你现在硬编码了白色卡片和黑色文字，后面补深色模式会非常痛苦。建议在 T1 就把颜色抽成常量文件（用 `$r('app.color.xxx')` 资源引用），并同时定义 Light/Dark 两套值。

---

# 第五部分 · 未确认清单（请勿当成事实使用）

## 5.1 我**没有**找到官方规范的

| 项 | 情况 |
|---|---|
| **官方"阴影 Token 全量表"** | 圆角和间隔都有"Token 全量表"，**阴影没有**。我只找到 `ShadowStyle` 枚举（6 档）和 `ShadowOptions` 的参数定义。**不确定是官方文档不含此表，还是我没找到对应文档。** |
| **阴影的具体数值规格** | 官方**没有**给出"卡片阴影用 radius=X、offsetY=Y、透明度=Z"这样的数值。ArkUI 默认值只有"黑色、offset 0、radius 无默认"。**本报告里我写的 `radius: vp2px(12), color:'#14000000', offsetY: vp2px(2)` 是我自己试出来的配方，不是官方值。** |
| **除 HarmonyOS Sans 外的内置中文字体清单** | 官方文档只说明 HarmonyOS Sans 是默认系统字体，**没有列出还有其他哪些内置中文字体**。 |
| **`fontFamily` 的合法中文字体名全量** | 同上，未找到官方清单。 |
| **官方是否有"应用内页面"的栅格/间距特化规范** | 圆角/间隔文档给的是通用值；页面级（列表页、详情页、表单页）的间距我只找到零散条目，没有成体系的"页面模板规范"。 |
| **万能卡片的"安全区"精确图示** | 官方文字说"距边缘 12vp 的安全边距"，但配图我无法读取（正文接口返回的是 HTML，图片是链接）。 |
| **官方主色板的完整色阶** | 官方给了 `brand` 的 Light/Dark 两个值，以及"基于透明度映射 12 个参数"的规则，但**没有公开这 12 个参数的完整数值表**。 |

## 5.2 我**没能验证**的

| 项 | 情况 |
|---|---|
| **竞品 App 的实际色值、字号、圆角** | 完全没有取得。见 4.1。 |
| **`SymbolGlyph` 的全部动效类在 API 12 是否都可用** | 我核实了 `.symbolEffect()` 接口本身是 **API 12**，`ReplaceEffectType` 的两个新值是 API 20+。但**各个 SymbolEffect 子类**（`ScaleSymbolEffect` / `PulseSymbolEffect` / `AppearSymbolEffect` / `DisappearSymbolEffect`）的**具体起始版本我没有逐个核对**。建议在 DevEco 里逐个试编译。 |
| **`symbolEffect` 与 `effectStrategy` 同时使用会怎样** | 官方说"仅支持使用 `effectStrategy` 属性**或**单个 `symbolEffect` 属性，**不支持多种动效属性混合使用**"，但**没有说明混用时的具体行为**（是报错还是静默覆盖）。 |
| **`BlurStyle` 各枚举的实际模糊半径数值** | 官方只说"封装了不同的模糊半径、蒙版颜色、蒙版透明度、饱和度、亮度"，**没有给出具体数值**。 |
| **`Curve` 枚举的完整取值** | 我在官方示例里见到 `Linear/Ease/EaseIn/EaseOut/EaseInOut/FastOutSlowIn`，常见还有 `Friction`/`Sharp`/`Rhythm`/`Smooth`/`ExtremeDeceleration`。**我没有拿到 `Curve` 枚举的官方全量定义文档。** |
| **《沉浸光感》的能力在 API 12 是否可用** | 文档说"配备了从 Ultra_Thin 到 Ultra_Thick 共 5 个层级枚举值"，与 `BlurStyle.COMPONENT_*`（API 11+）吻合。但"沉浸光感"作为一个**品牌化特性**（含 `MartialColor` 接口、粒子流转等）**我认为是新版本能力，API 12 上很可能不可用** —— 文档里出现的 `MartialColor` 接口我**没有找到其 API 版本说明**。**API 12 上请只用 `BlurStyle` 枚举，不要用 `MartialColor`。** |
| **`DataPanel` 的参数细节** | 官方《数据可视化》提到环形进度可参考 `DataPanel` 文档，我**没有抓取该文档**。 |
| **`Gauge` 的参数细节** | 我抓了 `ts-basic-components-gauge`（18631 字符）但**未逐条阅读**。范围类数据展示需要时请单独查阅。 |
| **`Canvas` 在 API 12 的完整 API 清单** | 我拿到了 `arkts-drawing-customization-on-canvas` 开发指导（含示例），但**没有找到 `CanvasRenderingContext2D` 的完整 API 参考页**（`ts-components-canvas-canvasrenderingcontext2d` 返回 "document not found"）。本报告用到的 `arc` / `strokeStyle` / `lineCap` / `createLinearGradient` / `addColorStop` 均在官方示例中出现，但**完整方法列表未核实**。 |
| **`@Builder` 传给 `.tabBar()` 时 `@State` 更新能否触发刷新** | 官方示例确实是这么写的（`tabBuilder(index, name, icon)` + `@State currentIndex` + `onChange` 更新），但**我没有实机验证**。如果不刷新，改用 `TabBarOptions` 或 `tabBarModifier`。 |

## 5.3 需要你在工程里自行确认的

1. **`vp2px` 的可用性**：官方文档明确提到 `vp2px` 用于 `shadow` 参数转换，但请确认在 API 12 的 ArkTS 里它是**全局函数**（无需 import）。
2. **`@kit.ArkUI` 的导入路径**：`import { curves } from '@kit.ArkUI';` 是官方示例写法（较新版本）。**API 12 上如果编译报错**，回退到 `import curves from '@ohos.curves';`。
3. **`this.getUIContext()?.animateTo(...)`**：官方推荐写法，我**未在 API 12 上实机验证**。若不支持，回退到全局 `animateTo(param, callback)`。
4. **所有 `sys.symbol.*` 名称**：全部来自官方 `name_map_new.json` v2.3。但该文件是**当前最新版**，其中标 `HarmonyOS 5.0+` 的 570 个我推断在 API 12 可用 —— **推断依据是 HarmonyOS 5.0 对应 API 12**，但没有官方文档明确写"HarmonyOS 5.0+ 图标 = API 12 可用"。**建议在 DevEco 里逐个试编译**，尤其是我在第 1.8 节表格里列的那些。
5. **`shadow()` 的 px 单位**：官方明确 radius/offset 单位是 px。**如果你的设计稿是 2x/3x 屏**，`vp2px` 会按设备密度换算 —— 请在设计稿和代码间核对一次实际观感。

---

## 附：本次调研产出的文件

| 文件 | 内容 |
|---|---|
| `HarmonyOS-视觉改造调研报告.md` | 本文件 |
| `HarmonyOS-Symbol-全量图标清单.md` | 官方 Symbol 图标库全量 **579 个**（name / 中文释义 / 所属模块 / 支持版本），按 17 个大类分组 |

### 复现方法（供后续核查）

```bash
# 1. 拉取设计规范正文
curl -s -X POST "https://svc-drcn.developer.huawei.com/community/servlet/consumer/cn/documentPortal/getDocumentById" \
  -H "Content-Type: application/json" \
  -H "Origin: https://developer.huawei.com" -H "Referer: https://developer.huawei.com/" \
  -d '{"objectId":"corner-radius-parameter-0000002556468705","language":"cn","catalogName":"design-guides"}'
# 正文在 value.content.content

# 2. 枚举 design-guides 全部 168 篇文档
curl -s -X POST "https://svc-drcn.developer.huawei.com/community/servlet/consumer/cn/documentPortal/getCatalogTree" \
  -H "Content-Type: application/json" \
  -H "Origin: https://developer.huawei.com" -H "Referer: https://developer.huawei.com/" \
  -d '{"language":"cn","catalogName":"design-guides"}'
# 递归 value.catalogTreeList，节点的 relateDocument 即 objectId
# ArkUI 文档用 catalogName: "harmonyos-guides" / "harmonyos-references"（各约 5700 / 4760 篇）

# 3. 拉取官方 Symbol 图标库索引
curl -s "https://developer.huawei.com/allianceCmsResource/resource/HUAWEI_Developer_VUE/template/resources/hm-symbol/name_map_new.json"
```
