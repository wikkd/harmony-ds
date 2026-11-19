# HarmonyOS Design 规范摘要（来源：华为官方设计文档）

> 数据来源：华为开发者联盟官方设计指南（developer.huawei.com，HarmonyOS 设计指南「通用设计基础 / 控件 / 人机交互 / 应用 UX 体验标准」）。所有数值（ms、vp、bezier 参数、字号、色值）均逐字取自页面原文，未获取到的项标注「未获取」。抓取日期：2026-11-20。

## 1. 设计理念（One Harmonious Universe 三原则 + 引力动效体系三感）

### One Harmonious Universe 三原则

HarmonyOS 希望为用户打造一个和谐的数字世界——One Harmonious Universe，三原则：

- **One（万物归一，回归本源）**：以人为本的设计；结合人因研究，保障全场景多设备的舒适体验；各种大小的文字都清晰易读，图标精确而清晰、色彩舒适而协调、动效流畅而生动；界面元素层次清晰，系统的表现是直觉的、无需思考。
- **Harmonious（一生为二，平衡共生）**：在物理世界中找到数字世界中的映射，通过光影、材质等设计转化到界面设计；熟悉的印象帮助用户快速理解界面元素并完成操作。
- **Universe（三生万物，演化自如）**：面向多设备体验；界面/组件设计需有良好的自适应能力；多设备体验在一致性与差异性中取得平衡（一致性减少学习成本，差异性按屏幕尺寸/交互方式/使用场景/用户人群做差异化设计）；在数字健康、全球化、无障碍方面积极探索。

### 引力动效体系三感

HarmonyOS 动效引力体系围绕"回归本源"设计理念，打造自然、流畅、品质一体的操作体验。转场动效表现物体运动过程中"力"的节奏感；手势动效打造元素运动互相影响"力"的力量感；特征动效呈现天体运动"力"的星体即视感。三感：

| 感 | 原文要点 |
|---|---|
| 力的即视感 | 将力赋予元素形象化、拟物化、动态化，更直观地传递设计理念，凸显品牌调性 |
| 力的秩序感 | 元素有序、一致、节奏的运动创造秩序感，让主要信息更易引起注意；转场元素的运动编排上尤为重要 |
| 力的控制感 | 动效延伸对物理世界的认知，摩擦力、重力、斥力以另外的方式被感知；元素通过速度或节奏等显性因子传达仿真物理世界的感受 |

另：转场动效在系统中占比最高的动效类型 60% 以上（转场动效页原文）。

**来源**：
- 设计理念 https://developer.huawei.com/consumer/cn/doc/design-guides/design-concepts-0000001795698445
- 动效概述 https://developer.huawei.com/consumer/cn/doc/design-guides/design-animation-overview-0000001750985338
- 转场动效 https://developer.huawei.com/consumer/cn/doc/design-guides/transition-animation-0000001750078488

## 2. 视觉风格（色彩规则、字体与字号阶梯表、圆角分档表、图标规范要点）

### 2.1 色彩规则

- 色彩基础：**宇宙蓝**（深邃广阔，系统高亮色）与**雪域灰**（带有淡蓝色相的背景色）构成系统色彩基础，象征苍穹与大地。
- Token 三层级：自上而下为 **控件私有参数 → 通用语义参数 → 通用基础参数**；基础 Token（primary、on_primary、brand、container、background 等）基于透明度系数映射出 12 个色彩参数。
- 对比度规则：**系统默认颜色保障了最小 3:1 对比度**；文本与图标分四个透明度层级 + 一个高亮层级（font_primary / font_secondary / font_tertiary / font_fourth / font_emphasize）。
- UX 体验标准对对比度的硬性/推荐条目：图标或标题文字与背景对比度 **大于 3:1**；正文文字与背景对比度 **大于 4.5:1**；智慧屏深色模式推荐文字与背景对比度范围 **5:1 ~ 15.1:1**（正文 **11:1 ~ 15.1:1**）；智能穿戴深色背景下 **11pt 及以下小字号对比度不小于 8:1，11pt 及以上字号对比度不小于 5:1**。

核心色值表（ARGB，前两位为透明度；Light / Dark）：

| Token | 场景 | Light | Dark |
|---|---|---|---|
| brand | 品牌色 | #ff0a59f7 | #ff317af7 |
| warning | 一级警示色 | #ffe84026 | #ffd94838 |
| alert | 二级警示色 | #ffed6f21 | #ffdb6b42 |
| confirm | 确认色 | #ff64bb5c | #ff5ba854 |
| font_primary | 一级文本 | #e5000000 | #e5ffffff |
| font_secondary | 二级文本 | #99000000 | #99ffffff |
| font_tertiary | 三级文本 | #66000000 | #66ffffff |
| font_fourth | 四级文本 | #33000000 | #33ffffff |
| font_emphasize | 高亮文本 | #ff0a59f7 | #ff317af7 |
| font_on_primary | 一级文本反色 | #ffffffff | #ffffffff |
| icon_primary | 一级图标 | #e5000000 | #e5ffffff |
| icon_emphasize | 高亮图标 | #ff0a59f7 | #ff317af7 |
| icon_sub_emphasize | 高亮辅助图标 | #660a59f7 | #66317af7 |
| background_primary | 一级背景 | #ffffffff | #ffe5e5e5 |
| background_secondary | 二级背景 | #fff1f3f5 | #ff191a1c |
| background_tertiary | 三级背景 | #ffe5e5ea | #ff202224 |
| background_fourth | 四级背景 | #ffd1d1d6 | #ff2e3033 |
| background_emphasize | 高亮背景 | #ff0a59f7 | #ff317af7 |
| comp_background_primary | 白色背景 | #ffffffff | #ff202224 |
| comp_background_secondary | 二级背景 | #19000000 | #19ffffff |
| comp_background_tertiary | 三级背景 | #0c000000 | #0cffffff |
| comp_background_emphasize | 高亮背景 | #ff0a59f7 | #ff317af7 |
| comp_background_neutral | 黑色中性高亮背景 | #ff000000 | #ffffffff |
| comp_emphasize_secondary | 20% 高亮背景 | #330a59f7 | #33317af7 |
| comp_emphasize_tertiary | 10% 高亮背景 | #190a59f7 | #19317af7 |
| comp_divider | 分割线颜色 | #33000000 | #33ffffff |
| interactive_hover | 通用悬停交互色 | #0c000000 | #0cffffff |
| interactive_pressed | 通用按压交互色 | #19000000 | #19ffffff |
| interactive_focus | 通用获焦交互色 | #ff0a59f7 | #ff317af7 |
| interactive_click | 通用点击交互色 | #19000000 | #19ffffff |
| interactive_active | 通用激活交互色 | #ff0a59f7 | #ff317af7 |
| interactive_disable | 禁用事件色 | 未获取（原文仅表格图片） | 未获取 |

（另有智能穿戴 Token 全量表：穿戴端 Dark 的 brand = #ff1f71ff、font_emphasize = #ff5ea1ff 等，见来源页。）

### 2.2 字体与字号阶梯

- 字体家族：**HarmonyOS Sans** 为默认系统字体，无衬线；完全支持简/繁体中文，广泛支持拉丁、希腊、西里尔、阿拉伯语系。
- 字重：**Thin、UltraLight、Light、Regular、Medium、SemiBold、Bold、Heavy、Black** 九档；另有 **Condensed & Italic** 风格与 **VF 可变字体**（字重在连续轴上可调）。
- 字体特性 Tag：sups（上标）、subs（下标）、sinf、numr、dnom、tnum（等宽数字）、pnum、case、frac、ordn、liga（连字）、fwid、hwid、vert（竖排）等。
- 字号阶梯表（「文本排版」页原文；单位 vp；Weight 为字重）：

| 场景类别 | 层级 Token | 字重 Weight | 尺寸 Size (phone) | 尺寸 Size (PC) | 尺寸 Size (watch) |
|---|---|---|---|---|---|
| 展示性文本 Display | Display_L | Light | 56 vp | 54 vp | 56 vp |
| 展示性文本 Display | Display_M | Light | 48 vp | 46 vp | 48 vp |
| 展示性文本 Display | Display_S | Light | 38 vp | 36 vp | 38 vp |
| 标题文本 Title | Title_L | Bold | 30 vp | 28 vp | 30 vp |
| 标题文本 Title | Title_M | Bold | 24 vp | 22 vp | 24 vp |
| 标题文本 Title | Title_S | Bold | 20 vp | 18 vp | 20 vp |
| 副标题文本 Subtitle | Subtitle_L | Medium | 18 vp | 16 vp | 18 vp |
| 副标题文本 Subtitle | Subtitle_M | Medium | 16 vp | 14 vp | 16 vp |
| 副标题文本 Subtitle | Subtitle_S | Medium | 14 vp | 12 vp | 14 vp |
| 正文文本 Body | Body_L | Medium | 16 vp | 14 vp | 16 vp |
| 正文文本 Body | Body_M | Regular | 14 vp | 14 vp | 14 vp |
| 正文文本 Body | Body_S | Regular | 12 vp | 14 vp | 12 vp |
| 说明文本 Caption | Caption_L | Medium | 12 vp | 12 vp | 12 vp |
| 说明文本 Caption | Caption_M | Medium | 10 vp | 9 vp | 10 vp |
| 说明文本 Caption | Caption_S | Medium | - | - | 8 vp |

- 行高数值：未获取（「文本排版」页仅含"小语种行高变化"图例，无数字）。
- 排版规则要点：行首标点缩进/禁则、行尾标点悬挂、标点符号连用挤压、中西文混排间空格、行尾孤字成行规避、中文两端对齐、英文平衡排版、英文按音节换行（密集文本场景行末/行首各不少于 3/2 字符）、小语种行高变化；支持系统大字体（fp = vp × scale）。
- 最小字号（UX 体验标准 2.1.4.2，必须）：手机/折叠/平板不小于 12 vp（推荐）、最小不得小于 8 vp（必须）；电脑不小于 14 vp（推荐）、最小 10 vp（必须）；智慧屏不小于 16 vp（推荐）、最小 14 vp（必须），正文字号建议 22～26vp；智能穿戴不小于 13 vp（推荐）、最小 10 vp（必须）。

### 2.3 圆角分档表

使用原则：**同层统一**（同层级同类型控件圆角一致）、**层级正相关**（层级越高圆角越大：半模态、弹出框 > 图片、标签、角标）。

通用圆角尺寸（「圆角参数」页原文）：

| 数值 | 场景 |
|---|---|
| 4vp | 系统通用超小圆角，适用于标签和角标等 |
| 8vp | 系统通用小圆角，适用于各类图片和图标等 |
| 16vp | 系统通用圆角，适用于通知卡片和内容容器等 |
| 20vp | 系统通用大圆角，适用于按钮和菜单等 |
| 32vp | 系统通用超大圆角，适用于半模态和弹出框等 |

系统圆角 Token 全量表（单位 vp）：

| Token | 数值 | Token | 数值 |
|---|---|---|---|
| corner_radius_none | 0 | corner_radius_level8 | 16 |
| corner_radius_level1 | 2 | corner_radius_level9 | 18 |
| corner_radius_level2 | 4 | corner_radius_level10 | 20 |
| corner_radius_level3 | 6 | corner_radius_level11 | 22 |
| corner_radius_level4 | 8 | corner_radius_level12 | 24 |
| corner_radius_level5 | 10 | corner_radius_level13 | 26 |
| corner_radius_level6 | 12 | corner_radius_level16 | 32 |
| corner_radius_level7 | 14 | corner_radius_level18 | 36 |

### 2.4 图标规范要点

**应用图标**：
- 设计原则：简洁优雅、极速达意、细腻质感（光影塑造体积感与层次感）。
- 资源规范（必须）：必须为**分层资源（前景图 + 背景图两层）**；尺寸必须 **1024 × 1024 px**；必须为**正方形图像、无需圆角**（系统自动生成遮罩裁切）；**PNG 格式**；**背景图不允许含有透明像素**（不允许自行裁切圆角、不允许内间距）。
- 色彩规则：图标底板光源保持至上而下，颜色上浅下深；渐变方向统一，不宜斜向渐变、上深下浅；系统提供 **9 种推荐色彩方向**。
- 多设备：泛手机端巧用应用主题色；电脑在鼠标滑入 dock 栏时于对角线位置生成前景动态阴影；智慧屏分层图标适配光标动效。
- 界面图标最小尺寸（UX 标准 2.1.4.3.2，必须）：手机/折叠屏/平板不小于 12 vp（推荐）、最小 8 vp（必须）；电脑不小于 14 vp（推荐）、最小 10 vp（必须）；智慧屏不小于 26vp（推荐）、最小 22vp（必须）；智能穿戴不小于 20vp（推荐）、最小 16vp（必须）。

**HarmonyOS Symbol（系统图标）**：
- 具备字体属性，可与字体基线对齐、粗细无极变化。
- 渲染策略：**单色 SINGLE**（仅生效第一个颜色）；**分层 MULTIPLE_OPACITY**（默认黑色，可设一个颜色；第一层 100%、第二层 50% 不透明度）；**多色 MULTIPLE_COLOR**（可生效两种颜色）。
- 动效策略：支持 9 种——出现、消失、弹跳、缩放、替换、快速替换、脉冲、可变颜色、禁用（默认为无动效策略）。

**来源**：
- 色彩 https://developer.huawei.com/consumer/cn/doc/design-guides/color-0000001776857164
- 鸿蒙黑体 https://developer.huawei.com/consumer/cn/doc/design-guides/font-0000001828772001
- 文本排版 https://developer.huawei.com/consumer/cn/doc/design-guides/typography-0000002622688363
- 圆角参数 https://developer.huawei.com/consumer/cn/doc/design-guides/corner-radius-parameter-0000002556468705
- 应用图标 https://developer.huawei.com/consumer/cn/doc/design-guides/application-icon-0000001953444009
- HarmonyOS Symbol https://developer.huawei.com/consumer/cn/doc/design-guides/system-icons-0000001929854962
- 通用应用 UX 体验标准 https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/ux-guidelines-general-0000001760708152

## 3. 布局与间隔（栅格、屏幕边缘间距表、控件间距表）

### 3.1 布局基础（栅格）

- 单位：**vp**（虚拟像素，任意屏幕上缩放以具有统一尺寸体量）；**fp**（字体像素，默认 1 fp = 1 vp，用户设置大字体后 1 fp = 1 vp × scale）。
- **8vp 网格系统**：以 8vp 为网格基本单位规划元素大小/位置/对齐；更小的控件（例如图标大小）可对齐 **4vp** 网格。
- 断点系统：横向断点以窗口宽度区分，纵向断点以窗口宽高比区分；支持设备类型、窗口宽/高、折叠屏状态（折叠方式/折痕位置/折叠状态/悬停状态）、横竖屏查询。
- **窗口栅格**（按窗口水平宽度自动匹配栅格数量）：
  - 0 <= 水平 vp < 600 时：**4 Columns** 栅格；
  - 600 <= 水平 vp < 840 时：**8 Columns** 栅格；
  - 840 <= 水平 vp 时：**12 Columns** 栅格。
- 栅格定义（margin/gutter/column）：
  1. 通用型：margin=16vp，gutter=8vp，column=4；宽松型：margin=16vp，gutter=16vp，column=4
  2. margin=24vp，gutter=12vp，column=8
  3. margin=32vp，gutter=16vp，column=12
  4. margin=32vp，gutter=20vp，column=12
- Gutters 通常的取值不会大于 Margins 的取值；**栅格最大使用宽度 2220vp**，超过后内容区不再变化、多出区域左右留白。
- 系统安全区：手机避让顶部信号栏、底部导航条安全区与两侧 margin；折叠设备避免关键信息放在转轴区（折痕处）；平板避让信号栏、导航条与两侧 margin（按断点规则计算）。
- 布局原则：布局完整（避免错位/截断/变形/模糊）、响应式设计（避免固定像素，用弹性布局/Blank/媒体查询/断点）、移动优先（先保证最小屏幕完整再向大屏延展）。

### 3.2 多设备屏幕边缘间隔表（margin，单位 vp）

| 间隔类型 | 手机 | 折叠屏 | 平板 | 智慧屏 | 穿戴 | PC | 智能座舱 | 场景 |
|---|---|---|---|---|---|---|---|---|
| 屏幕边缘间隔/margin | 16vp | 24vp | 32vp | 48vp | 26vp | 40vp | 48vp | 屏幕左右两侧边距 |
| 屏幕边缘间隔/margin | 36vp | 36vp | 36vp | 27vp | 20vp | / | / | 屏幕顶部边距 |
| 屏幕边缘间隔/margin | 28vp | 28vp | 28vp | 27vp | 20vp | / | / | 屏幕底部边距 |

### 3.3 控件/文本间距表（单位 vp）

间隔使用规则：优先使用固定基数倍数（**4vp、8vp 体系**）；层级越高间距越大；同类元素间距一致；屏幕边缘间距固定。

**泛手机（元素间）**：
- 卡片之间的间隔：**12vp**
- 控件间上下方向较大间隔（有明显边界元素）：**16vp**
- 控件间上下方向普通间隔（无明显边界元素）：**8vp**
- 控件间左右方向较大间隔（有明显边界元素）：**16vp**
- 控件间左右方向普通间隔（无明显边界元素）：**8vp**

**泛手机（文本间）**：
- 主次文本上下间隔：**2vp**
- 主次文本左右间隔：**8vp**

**智慧屏**：
- 控件间上下/左右较大间隔：**24vp**；普通间隔：**12vp**；较小间隔：**8vp**
- 文本段落五级间隔：第一层级 **32vp**、第二层级 **24vp**、第三层级 **16vp**、第四层级 **8vp**、第五层级 **4vp**

**穿戴（元素间）**：间距 9 = **12vp**、间距 10 = **6vp**、间距 11 = **8vp**、间距 12 = **26vp**；
**穿戴（文本间）**：间距 13 = **16vp**、间距 14 = **12vp**、间距 15 = **6vp**、间距 16 = **2vp**、间距 17 = **2vp**。

系统间隔 Token 全量表（单位 vp，节选自「间隔参数」页）：

| Token | 数值 | Token | 数值 |
|---|---|---|---|
| Padding_level0 | 0 | Padding_level12 | 24 |
| Padding_level1 | 2 | Padding_level13 | 26 |
| Padding_level2 | 4 | Padding_level16 | 32 |
| Padding_level3 | 6 | Padding_level17 | 34 |
| Padding_level4 | 8 | Padding_level18 | 36 |
| Padding_level5 | 10 | Padding_level19 | 38 |
| Padding_level6 | 12 | Padding_level20 | 40 |
| Padding_level7 | 14 | Padding_level21 | 42 |
| Padding_level8 | 16 | Padding_level22 | 44 |
| Padding_level9 | 18 | Padding_level23 | 46 |
| Padding_level10 | 20 | Padding_level25 | 50 |
| Padding_level11 | 22 | Padding_level26 | 52 |
| Padding_level27 | 54 | Padding_level28 | 56 |
| Padding_level29 | 58 | Padding_level30 | 60 |
| Padding_level32 | 64 | Padding_level33 | 66 |
| Padding_level34 | 68 | Padding_level35 | 70 |
| Padding_level36 | 72 |  |  |

**来源**：
- 布局基础 https://developer.huawei.com/consumer/cn/doc/design-guides/design-layout-basics-0000001795579413
- 间隔参数 https://developer.huawei.com/consumer/cn/doc/design-guides/interval-parameter-0000002562577161

## 4. 动效（设计原则条目、时长分档表 ms、曲线表、转场动效规则、手势动效规则）

### 4.1 动效设计原则条目（「设计原则」页原文）

- **自然流畅**：手势触控、视觉感知、心理预期三者合一；帧率稳定、响应及时、跟手操作是基础要求。
- **简洁高效**：界面元素运动尽可能少且简洁，减少路径及不必要的元素。
- **快速响应**：高效响应并减少过长的位移和时间。**长距离保持在 350ms 内，短距离保持在 250ms 内，较短的动画保持在 150ms 内完成动作**。
- **运动一致**：运动路径方式一致，避免不一致的运动分散视觉焦点。
- **隐藏等待**：通过元素运动或转场过渡减少等待焦虑；优先处理当前任务或将串行逻辑优化为并行。
- **凸显品牌**：通过系统级元素特效（拖尾、融球、发光、磁吸等）营造品牌氛围感。

### 4.2 时长分档表（ms）

时长单位：毫秒（ms），1 秒 = 1000 毫秒；**帧率 60FPS 环境下 1 帧 = 16.67 毫秒**。

| 分档维度 | 示例场景 | 时长 |
|---|---|---|
| 简单动画（前后状态只通过颜色动效实现） | — | **100ms** |
| 复杂动画（旋转动画） | — | **300ms** |
| 小范围内运动 | 开关图标动效 | **150ms** |
| 局部范围内运动 | 删除一条列表 | **200ms** |
| 全屏范围的运动 | 打开一张图片 | **350ms** |

### 4.3 曲线表（含具体参数）

曲线四类概况：linear、easing、spring、others。

**贝塞尔曲线**（原文参数逐字保留）：

| 类型 | 参数 | 使用原则 / 应用场景 |
|---|---|---|
| 标准曲线 | **cubic-bezier(0.40,0.00,0.20,1.00)** | 开始和结束处静止，速度峰值在中段，加速阶段相对减速阶段用时更少；运动前后始终在用户视线范围内的物体。场景：图片缩放，Tab 切换，Switch 开关等 |
| 标准曲线其他类型 | **cubic-bezier(0.20,0.00,0.10,1.00)**、**cubic-bezier(0.33, 0.00, 0.67, 1.00)** | — |
| 减速曲线 | **cubic-bezier(0.00, 0.00, 0.40, 1.00)** | 开始处速度最快，初始即峰值，渐渐变缓，结束处完全静止；适用从视线中新出现的物体。场景：弹框出现等 |
| 减速曲线其他类型 | **cubic-bezier(0.00, 0.00, 0.20, 1.00)**、**cubic-bezier(0.00, 0.00, 0.00, 1.00)** | — |
| 加速曲线 | 未获取（原文仅图示曲线形态，未给出 bezier 参数） | 从静止启动逐渐加速，达到峰值速度时结束（出场）；适用原本在视线中的物体消失/出场。场景：窗口出场、卡片删除等 |

**弹性曲线（Spring curve，物理曲线）**：

- **interpolatingSpring 曲线**由刚性、阻尼、质量、速度四个物理属性决定（Stiffness 刚性 / Damping 阻尼 / Mass 质量 / Velocity 速度）。与 springMotion 的换算等价示例（原文）：**interpolatingSpring：Stiffness:128，Damping:12，Mass:1（原文写作"Msss"，为原文笔误），Velocity:0** 等价于 **springMotion：Response:0.555，DampingFraction:0.53**。
- **springMotion 和 responsiveSpringMotion 曲线**由响应（Response，无阻尼自然振荡周期）、阻尼比（DampingFraction）、重叠时长（overlapDuration，两段弹性动画衔接时长）决定。
- 阻尼三态：临界阻尼（刚好不产生振动、最短时间到达平衡）、欠阻尼（振荡消耗能量后平衡）、过阻尼（衰减更慢后平衡）。
- 弹性曲线特点：支持可打断（时长自动匹配、新动效继承上一段速度）、继承速度、自然时长（物理模型自动计算）。
- 使用原则：适用于跟手运动的对象或需要表现弹簧特性的对象。场景：列表上下滚动、桌面左右翻页、手势上滑退出应用等；层级切换转场动效、提示性事件入场动效；微动效（多次振荡适用于小面积元素，需联合人因研究）。

**帧率**：
- 人眼画面帧率高于每秒约 **10~12 帧**即认为连贯（视觉暂留）；连贯不代表感知流畅。
- **交互类动效**：移动设备屏幕一般 60 赫兹刷新率，动画帧率与其保持一致（**60FPS**）；交互型动效需要更严苛的帧率稳定性（对比示例 60FPS vs 30FPS）。
- **纯动画**（如操作引导）：早期迪士尼手绘动画基本帧率 **24FPS** 也可满足观看；高帧率更细腻；有些动画创作会选择 8FPS（风格需要）；**12FPS** 低帧率导致两帧之间变化过大、眼跳感。

### 4.4 转场动效规则

- 层级关系：**同层级**（编辑、页签、横竖屏转场等）、**上下层级**（上下级页面、新建、解锁、搜索转场等）、**跨层级**（应用之间跳转）。
- 场景解构四类元素：**进场元素**（新出现）、**出场元素**（消失）、**持续元素**（持续存在、无中断）、**静止元素**（无变化）；元素类别决定转场方式、曲线和时长。
- **一镜到底**：通过共享元素的转场编排，重点推荐技法。三个手法：**共享元素**（转场前后持续存在的焦点元素）、**共享容器**（有明确边界的一组元素，通过大小、高度、圆角等属性补间过渡，容器内元素淡入淡出或共享元素过渡）、**共享动势**（无中间属性时提取共享转换属性：位移、缩放、旋转等）。
- **淡入淡出**：单向淡入淡出（只有前景变化）；交叉淡入淡出（进出场元素样式一致可同时透明度变化，不同类型可适当错开淡出/淡入时机）。

UX 体验标准中与转场相关的条目（详见第 5 节）：层级转场（手机左右平移 / 电脑大屏淡入淡出）、搜索转场（共享元素 / 淡入淡出）、新建转场（上下位移）、编辑转场（淡入淡出）、共享容器/共享元素转场、秩序感元素转场。

### 4.5 手势动效规则

- 点击：包含按下（touch down）和抬起（touch up）；**按下接触过程平均时长 100~130ms 中对象无反馈，为提升响应速度，点击手势动效设计在按下那一刻即响应动效反馈**（可先行的触控响应机制）。
- 滑动：分跟手阶段、离手瞬间、离手后阶段；跟手阶段着重响应性；**离手瞬间需要对象继承手速**进行动画反馈，保证连贯性。
- 翻动：通过抛滑和拖拽操作，基于设定区域翻动切换；**离手后对象不会处于任一坐标位置上，有明显限位属性**；翻页有成功与否，未成功停留在当前内容；有过界拖拽提示性场景。
- 夹捏：双/多指合拢或分开；跟手阶段基于手势做缩放、旋转、移动反馈；离手瞬间继承手速。
- 拖拽：跟手阶段**显控比设计**；离手后对象运动曲线及属性变化设计。
- 进阶联动：**标题联动**（主内容区过界阻尼 + 标题区不同阻尼联动）、**卡片左右滑**（横向拖拽一定距离后产生阻尼感）、**下拉返回**（递进的显控比设计、渐强阻尼，离手后继承手速）。

UX 标准 2.1.3.2 典型手势时长（必须）：**长按手势接触时长应为 500 ms，时长在 400 ms-650 ms 内可调；双击手势间隔时长应为 70-400 ms 之间**。

**来源**：
- 动效概述 https://developer.huawei.com/consumer/cn/doc/design-guides/design-animation-overview-0000001750985338
- 动效设计原则 https://developer.huawei.com/consumer/cn/doc/design-guides/animation-design-principles-0000001750237392
- 动效属性 https://developer.huawei.com/consumer/cn/doc/design-guides/animation-attributes-0000001797117229
- 转场动效 https://developer.huawei.com/consumer/cn/doc/design-guides/transition-animation-0000001750078488
- 手势动效 https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/gesture-animation-0000001797038213

## 5. 交互与体验标准（点击反馈、按压态、弹窗/菜单/半模态、UX 硬性条目）

### 5.1 点击反馈与按压态

- 点击响应：按下（touch down）那一刻即响应动效反馈（见 4.5，手势动效页）。
- 按压/悬停/点击态色 Token（色彩页原文）：**interactive_pressed（通用按压交互色）#19000000（Light）/ #19ffffff（Dark）**；interactive_click 同为 #19000000 / #19ffffff；**interactive_hover #0c000000 / #0cffffff**；interactive_focus、interactive_active 为品牌色 #ff0a59f7 / #ff317af7。
- 按钮多态：强调/普通/文字/圆形按钮均含默认样式与多态；按钮样式应使用控件子样式（ButtonStyleMode / ButtonRole / controlSize NORMAL、SMALL）而非直接写参数；电脑设备使用更小的按钮圆角；穿戴不可用状态背板不变、仅文本不透明度变为 **40%**；穿戴文本超长则缩小 2 级，还放不下则跑马灯。
- 点击热区（UX 标准 2.1.3.3，必须）：手机/平板/折叠屏可点击热区**至少 48vp×48vp（推荐），不得小于 40vp×40vp（必须）**；电脑键鼠热区不小于 **5mm**、触屏不小于 **7mm**；智慧屏指向光标热区**至少 4cm（推荐）、不得小于 2.5cm（必须）**；智能穿戴**至少 46vp×46vp（推荐）、不得小于 40vp×40vp（必须）**。
- 可滑动控件高度（UX 标准 2.1.3.4，必须）：**不低于屏幕高度的 20%**。

### 5.2 弹窗 / 菜单 / 半模态规范要点

**弹出框**：
- 结构：标题区、内容区（必选）、按钮区；通常居中显示于屏幕/窗口。
- 宽度通用计算：**屏幕/窗口宽度 - 两侧 Margin = 弹出框宽度**；基于默认手机 360vp 宽度自适应，**最大宽度达到 400vp 时不再继续响应伸缩**。
- **弹出框最大高度 = 0.9 × (屏幕高度 - 信号栏 - 导航栏)**（电脑场景按子窗口整体高度计算，最大高度 = 0.9 × 窗口内容层）。
- 视觉：移动端用全屏/窗口蒙层区分层级；电脑自带阴影分获焦态/失焦态、使用更小圆角；品牌色点缀使用，避免大面积。
- 已默认提供沉浸光感样式。

**半模态面板**：
- 档位高度：**Large = 屏幕/窗口高度 - 信号栏 - 8**；**Medium = 60% 屏幕/窗口高度**；**Free = 可完全自定义展示高度**。
- 手机横屏：保持宽度 **480vp** 最大宽度，高度距离屏幕顶部 **8vp** 安全间距。
- 大于 **600vp** 设备断点以上：变更为窗口模式居中显示；**默认高度 560vp、宽度 480vp**，背景覆盖蒙层；**最小高度 320vp**；**最大高度为屏幕短边的 90% 高度**；Popup 容器承载时宽度默认 **400vp**，尖角与指向目标保持 **8vp** 间距。
- 滑动响应优先级：内容区滑动时优先扩展/收缩档位再滚动内容（内容不可滚动按最顶部状态处理）；标题栏滑动时短滑切换相邻档位、长滑跨档位/直接关闭。
- 沉浸光感：半模态内复杂卡片容器建议使用**不透明度低于 60%** 的背景色；关闭按钮需同时使用沉浸光感效果。

**菜单**：
- 菜单项中不显示与当前内容无关的项；最常用菜单项放在菜单顶部依次排列。
- 泛手机统一宽度固定 **224vp**；电脑菜单宽度按内容自适应，默认最小宽度 **224vp**，可配置最小宽度但**不得低于 64vp**。
- 建议采用沉浸光感样式。

### 5.3 UX 体验标准：与转场/动效相关的硬性条目（标准编号逐字保留）

| 标准编号 | 条目 | 判定标准（原文要点） | 标准等级 |
|---|---|---|---|
| 2.1.5.2.1 | 动效无缺失 | 前后相邻界面的切换跳转或较大元素的进出场必须有转场动效过渡，不应单帧直接切换 | **必须** |
| 2.1.5.2.2 | 转场动效时长下限 | 全屏页面转场动效时长在 **8.5 英寸以下的设备上不应短于 200 ms**，**8.5 至 12 英寸的设备上不应短于 250ms**，**12 英寸以上的设备上不应短于 300ms** | **必须** |
| 2.1.5.3.1 | 启动页动效时长 | 有内容填充的启动页全屏停留时长不建议超过 **3 s**；全黑/全白空白启动页不建议超过 **300 ms** | 强烈推荐 |
| 2.1.5.3.2 | 滑动跟手动效一致性 | 界面滑动有跟手的上下/左右位移反馈动效，不应过快过慢、不跟手、卡顿 | **必须** |
| 2.1.5.3.3 | 滑动过界反馈动效一致性 | 滑动到边界（顶部/底部/左右边界）应有反馈动效 | 强烈推荐 |
| 2.1.5.3.4 | 离手减速动效一致性 | 达到一定手速的滑动，离手后界面应继续移动，速度随时间缓慢下降直至停止 | **必须** |
| 2.1.5.1.1.1 | 层级转场-左右平移 | 应用内上下层级页面转场采用左右位移，曲线优先使用弹簧曲线（手机、折叠屏、平板、智能穿戴） | 强烈推荐 |
| 2.1.5.1.1.2 | 层级转场-淡入淡出 | 页面转场采用淡入淡出（电脑、大屏设备、智能穿戴） | 强烈推荐 |
| 2.1.5.1.2.1 | 搜索转场-共享元素 | 搜索框作为持续存在的元素串联前后两个界面 | 强烈推荐 |
| 2.1.5.1.2.2 | 搜索转场-淡入淡出 | 仅有搜索图标/功能键时采用淡入淡出过渡 | 强烈推荐 |
| 2.1.5.1.3.1 | 新建转场-手机通用 | 新建页面转场采用上下位移（手机） | 推荐 |
| 2.1.5.1.3.2 | 新建转场-宽屏 | 交互按钮在底部采用上下位移；按钮在侧边可用淡入淡出；上下层级页面转场采用左右位移（折叠屏、平板、电脑、大屏） | 推荐 |
| 2.1.5.1.4 | 编辑转场 | 编辑页面转场采用淡入淡出的过渡方式 | 推荐 |
| 2.1.5.1.5.1 | 共享容器转场 | 转场前后持续存续的有明显边界元素维持同一个容器（卡片/列表形态扩大成窗口） | 强烈推荐 |
| 2.1.5.1.5.2 | 共享元素转场 | 前后存续元素为同一元素（geometryTransition 一镜到底） | 强烈推荐 |
| 2.1.5.1.6 | 秩序感元素转场 | 成组排列布局进入页面时有节奏的时间差或不同曲线，不应单帧直接切换 | 推荐 |

### 5.4 其他相关硬性/体验条目

- 2.1.1.1 系统返回（**必须**）：所有界面都可执行系统返回操作；除一级界面外，所有全屏界面均需提供返回/关闭/取消按钮（全屏沉浸式场景、穿戴圆形屏除外）。
- 2.1.2.2 挖孔区适配（**必须**）：重要信息或交互操作与挖孔区有遮挡时需局部避开显示；悬浮类控件与可滚动内容无需避开。
- 2.1.3.1 避免与系统手势冲突（**必须**）：不设计与屏幕边缘手势、指关节手势、三指及以上手势冲突的操作。
- 2.2.1 底部导航条适配（**必须**）：底部固定控件/键盘/悬浮按钮向上抬高避让；可滚动内容可显示在导航条下方；弹出框、半模态向上避让导航条；沉浸场景导航条可自动隐藏、底部上滑恢复。
- 2.2.5 深色模式（**必须**）：系统切换深色模式后界面以深色风格呈现，无识别性问题。
- 2.2.6 状态栏（**必须**）：沉浸一体化背景，状态栏区域不被单独切割；按背景色选择黑/白状态栏颜色；避免左右半区对比差异过大。
- 2.2.7.1 滑动沉浸（推荐）：浏览型场景滑动/点击可隐藏顶部与底部标题栏、导航栏等控件。
- 沉浸光感（Immersive Light）：三档强度（强档 / 均衡档=默认 / 弱档）；开发配备 **Ultra_Thin 到 Ultra_Thick 共 5 个层级枚举值**；组件位置建议：顶部悬浮用 **ULTRA_THIN**（结合渐变模糊）、底部悬浮用 **THIN**（结合渐变颜色蒙层）、非常驻任意位置弹出建议 **THICK**、半模态/弹出框推荐 **ULTRA_THICK**。

**来源**：
- 通用应用 UX 体验标准 https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/ux-guidelines-general-0000001760708152
- 弹出框 https://developer.huawei.com/consumer/cn/doc/design-guides/dialog-0000001957012569
- 半模态面板 https://developer.huawei.com/consumer/cn/doc/design-guides/bindsheet-0000001956852753
- 菜单 https://developer.huawei.com/consumer/cn/doc/design-guides/menu-0000001957001877
- 按钮 https://developer.huawei.com/consumer/cn/doc/design-guides/button-0000001929683228
- 沉浸光感 https://developer.huawei.com/consumer/cn/doc/design-guides/immersivelight-0000002612101053
- 手势动效 https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/gesture-animation-0000001797038213

## 6. 参考链接（每章节来源 URL 汇总）

| 章节 | 页面 | URL |
|---|---|---|
| 1 | 设计理念 | https://developer.huawei.com/consumer/cn/doc/design-guides/design-concepts-0000001795698445 |
| 1 | 动效概述（引力动效体系） | https://developer.huawei.com/consumer/cn/doc/design-guides/design-animation-overview-0000001750985338 |
| 2 | 色彩 | https://developer.huawei.com/consumer/cn/doc/design-guides/color-0000001776857164 |
| 2 | 鸿蒙黑体（HarmonyOS Sans） | https://developer.huawei.com/consumer/cn/doc/design-guides/font-0000001828772001 |
| 2 | 文本排版 | https://developer.huawei.com/consumer/cn/doc/design-guides/typography-0000002622688363 |
| 2 | 圆角参数 | https://developer.huawei.com/consumer/cn/doc/design-guides/corner-radius-parameter-0000002556468705 |
| 2 | 应用图标 | https://developer.huawei.com/consumer/cn/doc/design-guides/application-icon-0000001953444009 |
| 2 | HarmonyOS Symbol | https://developer.huawei.com/consumer/cn/doc/design-guides/system-icons-0000001929854962 |
| 3 | 布局基础（栅格） | https://developer.huawei.com/consumer/cn/doc/design-guides/design-layout-basics-0000001795579413 |
| 3 | 间隔参数 | https://developer.huawei.com/consumer/cn/doc/design-guides/interval-parameter-0000002562577161 |
| 4 | 动效设计原则 | https://developer.huawei.com/consumer/cn/doc/design-guides/animation-design-principles-0000001750237392 |
| 4 | 动效属性（时长/曲线/帧率） | https://developer.huawei.com/consumer/cn/doc/design-guides/animation-attributes-0000001797117229 |
| 4 | 转场动效 | https://developer.huawei.com/consumer/cn/doc/design-guides/transition-animation-0000001750078488 |
| 4 | 手势动效 | https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/gesture-animation-0000001797038213 |
| 5 | 通用应用 UX 体验标准 | https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/ux-guidelines-general-0000001760708152 |
| 5 | 弹出框 | https://developer.huawei.com/consumer/cn/doc/design-guides/dialog-0000001957012569 |
| 5 | 半模态面板 | https://developer.huawei.com/consumer/cn/doc/design-guides/bindsheet-0000001956852753 |
| 5 | 菜单 | https://developer.huawei.com/consumer/cn/doc/design-guides/menu-0000001957001877 |
| 5 | 按钮 | https://developer.huawei.com/consumer/cn/doc/design-guides/button-0000001929683228 |
| 5 | 沉浸光感 | https://developer.huawei.com/consumer/cn/doc/design-guides/immersivelight-0000002612101053 |

> 抓取方式备注：上述页面为 JS 渲染的 SPA，本文档正文取自各页面的官方 Markdown 原文端点（在页面 URL 后追加 `.md`，即 doccenter-ux-design 路径下的 `https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/<id>.md`）；所有数值均为原文逐字保留。未获取项：加速曲线的具体 bezier 参数、字号阶梯表的行高数值、interactive_disable 色值。
