# harmony DS

DeepSeek 官方 [chat-demo](https://github.com/deepseek-ai/chat-demo) 的鸿蒙原生（HarmonyOS NEXT / ArkTS）完整移植版。无 WebView、无三方 UI 库，全部功能以 ArkUI 原生实现。

> 移植自 DeepSeek 官方 chat-demo（MIT License）。UI 按 HarmonyOS Design 重新设计，设计 token 取自官方 HarmonyOS Component Library 规范库与官方图标集。

## 功能（对齐原项目）

- 多会话：时间分组侧栏、重命名、删除、自动标题（message_delta.title）
- 消息分支树：编辑重发、重新生成、‹n/m› 版本切换（含 current_message_id 选中链）
- 流式回复：SSE（WHATWG 规范解码）、深度思考折叠（用时统计）、停止生成、继续生成
- 富文本（纯原生渲染）：Markdown（GFM 子集）、代码高亮、LaTeX 公式（Unicode 子集）、Mermaid 图表（Canvas 自绘 flowchart）
- 联网搜索 / 链接阅读：搜索步骤、来源引用角标、来源卡片、浏览器打开
- 附件：文件/图片选择、Files API 上传（purpose 判定）、file_id 引用发送
- 语音：录音（WAV）→ ASR 转写输入；回复朗读（TTS 24kHz PCM 流式播放）
- 双语（简体中文/English）、深浅色主题（跟随系统/手动）、位置信息设置
- 数据：RelationalStore 持久化、历史导入导出（与 web 版 v3 ZIP 格式互通，图片原件包含、API Key 排除）、删除全部对话
- 安全：API Key 存于系统关键资产库（Asset Store Kit），不随导出文件离开本机

## 协议

Anthropic 兼容 Messages API（`POST /anthropic/v1/messages`，stream），`x-api-key` 鉴权；`GET /models` 校验 Key；`/anthropic/v1/files` 附件；`/v1/tools/asr|tts` 语音。默认服务地址 `https://api.deepseek.com`。

## 构建

DevEco Studio 26+（HarmonyOS 6.1.1 / API 24）打开工程，或使用命令行：

```cmd
scripts\build.cmd assembleHap
```

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`。真机安装需在 DevEco 中配置自动签名。

## 工程结构

```
entry/src/main/ets/
├─ common/          设计 token、I18n（全量词条）、Logger、断点、主题
├─ model/           协议类型（Anthropic 兼容）与会话数据模型（V2 可观察）
├─ service/
│  ├─ api/          SseDecoder / ApiClient(requestInStream) / EventParser / ApiError
│  ├─ chat/         ChatStore（分支树）/ ReplyEngine / LatestReminder
│  ├─ db/           RelationalStore（sessions/messages，schema 版本化）
│  ├─ prefs/        Preferences 设置 + KeyVault（asset 关键资产）
│  ├─ speech/       Recorder(WAV) / SpeechApi(ASR/TTS) / TtsPlayer
│  ├─ attachments/  picker + Files API 上传
│  └─ history/      v3 ZIP 导入导出
├─ components/      侧栏/消息/输入/Markdown/设置/隐私政策（全 ArkUI 原生）
└─ pages/           Navigation 骨架（窄屏抽屉 / 宽屏双栏）
```

## 隐私

本应用不设自有服务器：消息、附件与录音仅在发送时传输到你自行配置的 API 服务。详见应用内「设置 → 隐私政策」。

## License

MIT —— 见 [LICENSE](LICENSE)。原始项目版权归 DeepSeek（deepseek-ai/chat-demo）所有。
