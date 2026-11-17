# DeepSeek chat-demo → 鸿蒙原生完整移植（harmony DS，鸿蒙设计语言，生产上架级）

## Context

将 deepseek-ai/chat-demo（DeepSeek 官方纯静态聊天前端，MIT）完整移植为生产上架级鸿蒙原生应用。工程：D:\harmony_deepseek（API 24 空白模板）。功能逻辑对齐 chat-demo；UI 按 HarmonyOS Design 重新设计，素材取自 D:\harmony资源包（676 官方 SVG 图标 + 833 画板官方组件规范库）。

已确认：纯原生 Markdown 渲染；语音一期完整；手机+平板；App 名 harmony DS；鸿蒙设计语言。

## 实施（10 个里程碑，每步可构建）

M1 基座+设计系统：bundleName com.harmonyds.chat / deviceTypes phone+tablet / INTERNET+MICROPHONE 权限；解压规范库提取官方色板字号尺寸→DesignTokens；筛选图标→media；断点框架；Navigation 骨架；主题跟随/手动；I18n 全量词条；Preferences+AssetStoreKit 存 API Key；hilog Logger；隐私政策页。
M2 流式内核：SseDecoder/ApiClient(requestInStream)/EventParser/ApiError；单会话流式跑通（thinking 折叠/停止/错误重试/Key 验证 GET /models）；超时+429 退避。实施前精读 parseEvent.ts/reply.ts/latestReminder.ts 逐行移植。
M3 数据：RelationalStore（sessions/messages/files，版本迁移）、BranchTree（编辑重发/重新生成/版本切换）、Drafts、自动标题、侧栏。
M4 富渲染：MarkdownView（mdast→ArkUI）/CodeBlock 高亮/MathView（LaTeX 子集降级原文）/MermaidView（Canvas 自绘 flowchart/sequence/pie 降级代码块）/引用角标/来源卡片/节流渲染。
M5 设置页：全部设置项+位置选择+隐私政策/关于。
M6 语音：麦克风权限申请、录音→ASR、TTS 流式 PCM 播放、频谱动画。
M7 附件：picker/拍照、purpose 判定上传、file_id 引用、FileCard。
M8 历史导入导出：@ohos.zlib、schema 校验、排除 Key；删除全部聊天。
M9 平板：宽屏双栏 SideBarContainer 常驻、折叠屏展开态、窗口拖拽。
M10 收尾：release 混淆、冷启动优化、LazyForEach/@Reusable、深浅色+fp 字体核对、无障碍、上架清单（隐私政策/双语文案/宣传图）。

## 协议要点（已从源码读取）

Anthropic 兼容 Messages API（POST /anthropic/v1/messages stream，x-api-key，files-api beta 头）；SSE 事件 message_start/content_block_*/message_delta/message_stop/ping；Files API（purpose rich_layout_recognition|user_data）；ASR /v1/tools/asr（WAV≤120s）、TTS /v1/tools/tts（24kHz PCM）；分支树消息；设置 localStorage→Preferences；ZIP 导入导出。

## 验证

每里程碑 hvigorw assembleHap；hypium 单测（SseDecoder/BranchTree/MathView/EventParser/KeyVault）；真实 API Key 端到端对照原 README 功能清单；phone+tablet 断点切换；抓包比对请求体；release 混淆包可运行。

## 风险降级

Math/Mermaid 子集实现降级显示；Sketch token 与原生组件并存以 token 为准；协议细节以抓包为准；AssetStoreKit 模拟器受限预留加密回退。