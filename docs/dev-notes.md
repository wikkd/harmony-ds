# 开发经验总结（harmony DS）

chat-demo → 鸿蒙原生移植（M1–M12）过程中沉淀的实操经验，按主题归类。
配套工具：`scripts/build.cmd`（构建）、`scripts/install.cmd`（装机启动）、`scripts/test.cmd`（真机单测）；纯逻辑单测在 `entry/src/ohosTest/ets/test/Core.test.ets`。

## 构建与工程

- 无 IDE 构建：`scripts\build.cmd` 直接调 DevEco 自带的 hvigor/node（`DEVECO_SDK_HOME`/`JAVA_HOME` 指向 DevEco 安装目录），命令形如 `hvigorw --mode module -p module=entry@default assembleHap`。设备测试包把 module 限定符换成 `entry@ohosTest`。
- **签名材料保护**：`build-profile.json5` 含签名密码，用 `git update-index --skip-worktree build-profile.json5` 挡在提交外；每次提交前用 `git ls-files -v | grep ^S` 复核标志还在。
- ArkTS 严格模式高频坑：
  - 复杂递归避免闭包自引用，用类静态方法 + 栈式实现（SseDecoder、MathConverter.walk 都是这个形态）。
  - 运行时形状不确定的数据（如响应头可能是 `Record<string,string>` 或 `Array<Array<string>>`）先 try-catch 内断言、逐形状兼容（ApiClient.headerValue）。
  - 用 Edit 工具改 import 块时容易把整块重复插入 → Duplicate identifier 编译错；改完先 grep 确认唯一。

## ArkUI / 状态管理（V2）

- @ComponentV2 体系：@Param 入参、@Local 私有态、@Trace 深层可观察；跨页共享状态用 @ObservedV2 单例（SettingsStore/ChatStore），组件里 `SettingsStore.get()` 直接绑 @Trace 字段即可刷新。
- `Text` 只能包含 `Span`：嵌套强调/链接/公式树要先拍平成一层带样式的 Span（MarkdownView.FlatSpan），别指望 Text 里放组件。
- 自适应高度容器里 `Rect + height('100%')` 会按父级下发的视口约束解析，把元素撑到近一屏高——画竖条/分隔线用 `border` 而不是 Rect（引用块竖条踩过）。
- 页面底部"露分界线/被裁切"：给 Scroll 内容和页面根容器都加 `.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])`，让底色延伸进手势条避让区；文字滚动区自己留 bottom padding。
- 状态栏高度启动时取 `getWindowAvoidArea(TYPE_SYSTEM).topRect.height / density` 写进 AppStorage（safeTopVp），顶部胶囊/抽屉钮据此定位；不要硬编码。
- 键盘弹出会挤压输入 dock，高度要走窗口监听动态调整，不能用固定值。
- 流式重渲场景 ForEach 键要用稳定语义（内容无关的 `f${i}`），避免整树重建闪烁。

## 网络与 SSE

- **requestInStream 的 Promise 在部分设备上要等整段流结束才 resolve**（期间 statusCode 恒 0）——流式判定不能等 Promise，必须在 headers receive 回调里按 `content-type: text/event-stream` 立即切流式，否则流式回复被当成失败（ApiClient 踩过，真机必现）。
- SSE 错误有两种形状：`event: error` 帧和 JSON payload 内的 `error` 字段，两条路都要解析。
- 网络定位：`hilog -x | grep -a '<bundle>' | grep NETSTACK` 能看到每次请求的 method/RespCode/耗时；先 `hilog -r` 清环缓冲再复现动作。
- DeepSeek 模型实际输出三种数学定界符：`$$…$$`、`\[…\]`、`\(…\)`，解析器三个都要支持，少一个就漏渲染。

## 数据层

- RelationalStore 事务：`createTransaction()` → 操作 → `commit()`，catch 里 `rollback()` 并保留原错误；历史导入用"先删后插"的事务化原子替换，失败回滚保原数据。
- 结构变更必须递增 `SCHEMA_VERSION` 并在启动迁移；会话新增字段（如 rootMessageId）必须写进 bucket 落盘，否则重启丢失（根级分支切换踩过）。

## 真机自动化（hdc/uitest）

- `uiInput inputText` 输入的是 IME 未上屏组合串：下一次 `uiInput click`（包括点发送键）会把它清掉，应用 onChange 不触发、发送无效。正确流程：Back 收键盘 → 点输入框 → 等 1.5s 键盘弹起 → inputText（用抬升后的坐标）→ dumpLayout 取发送键实时 bounds → 点击 → dump 验证用户气泡真的出现。
- 键盘弹起后别点旧坐标：底部旧坐标会命中 IME 按键（如话筒键）；剪贴板建议条出现/消失还会让 dock 整体 ±48px。**每次点击前 dumpLayout 取实时 bounds**。
- 界面结构用 `uitest dumpLayout -p <path> -b <bundle>` 看树，不肉眼猜坐标；截屏 `screenCap -p`。
- 测模型行为用**确定性提示**（如"不要用代码块，原样输出以下三行：$$…$$ 和 \[…\] 和 \(…\)"），绕开模型自发选择输出格式的随机性。bash 里传 `$$`/`\[` 要转义（`\$\$`、`\\[`）。

## 测试策略

- 纯逻辑（SSE 解码、Markdown/数学转换、错误码映射、峰谷判定）全部进 hypium 单测 `entry/src/ohosTest/ets/test/Core.test.ets`：放 ohosTest 源集是因为它既能在 IDE 设备测试里跑，也能被 `scripts\test.cmd` 脚本化（构建测试包 → `aa test` → 自动恢复正式包）；src/test 本地套件需要 IDE 且不能脚本化，只留模板冒烟。
- 一次 ohosTest 构建失败的教训：跨源集 import（src/test ↔ src/main）在本地测试与设备测试编译里解析规则不同，`any` 报错全是 import 解析失败的级联效应，先修路径再看类型。
- UI/流式行为在真机人工验收：改代码 → 构建通过 → `scripts\install.cmd` 装机 → 人工点验。自动化截图循环只在外观回归时才值得。

## 消息注入测试（真机 E2E 的可靠路径）

- UI 驱动（点输入框 → inputText → 点发送）受 IME 组合串、键盘时序、熄屏影响，成功率不稳定。可靠方案是 **`aa start --ps` 参数注入**（TestHarness，Debug 构建生效）：
  - `--ps testInject math|md|long`：向当前会话注入固定消息夹具，走真实渲染管线，断言全靠 dumpLayout；
  - `--ps testKey <sk-...>`：真实 GET /models 校验后入 KeyVault（Key 只走命令行参数，不落代码库）；
  - `--ps testSend <文本>`：注入用户消息后走完整 ReplyEngine（真 SSE/思考/搜索）。
  - 冷启动注入要等 ChatStore 恢复完成（isReady 轮询）；已在运行时参数走 onNewWant。封装在 `scripts\inject.cmd`。
- **平板（MRDI-W00 实测）设备怪癖**：
  - `screenCap` 不存在，用 `snapshot_display -f`；但快照/合成层不可靠（会出黑帧、丢文字层）——**渲染断言一律以 `uitest dumpLayout` 的节点树为准**，截图只作参考。
  - 自动锁屏后 `uiInput click/swipe` 静默失效（返回 No Error 但无效果）；每次交互批次前先 `power-shell wakeup`，失败就唤醒后重试一次。
  - 免打扰/睡前模式下熄屏极快，长测试中途会被锁屏打断：交互命令要"唤醒+动作"同批执行。
- 宽屏（≥840vp）常驻侧栏的让位必须用**布局手段**（padding/margin），不能只用 translate：translate 不改布局宽度，`width('100%')` 子件仍按全窗宽居中，内容整体右偏且右缘被推出屏幕（主页欢迎态/输入面板/消息列表全部中招）。
- **Scroll 内容里 Row 不要用 `Blank()` 撑开**：平板实测 Row 内 Blank 会把同 Row 的 Text/Image 节点整个吞掉（树里都没有），同样代码在设置页 optionRow（用 `Text.layoutWeight(1)`，无 Blank）正常。撑开一律 `layoutWeight(1)`。
- `@ComponentV2` 子组件的回调入参必须 `@Param`（普通属性禁止父级初始化，10905324）。

## 2026-11-19 全项目重构沉淀

- **文件地图（重构后）**：pages/ 三文件（Index=路由+首启合规弹窗、HomePage=抽屉壳、ChatView=会话编排+排队/压缩）；components/messages/ 三文件（MessageList=列表骨架+用户行、AssistantBody=助手正文+TTS/引用卡、AttPreview=缩略图）；components/settings/SettingRow=设置行统一子组件（carded/danger/toggle 一体，规避平板 @Builder 吞文字怪癖）；components/privacy/LegalDocPage=隐私政策/用户协议共用骨架；service/chat/RequestBodyBuilder=请求构建纯函数（自 ReplyEngine 拆出，compact 复用其 getContextRounds/assistantTextParam）；common/i18n/ 8 个分域词条文件（I18n.ets 只留合并+translate，zh/en 导出常量供 parity 单测）。
- **导出失败根因**（平板 export failed: {}）：产物固定名 `deepseek_data-YYYYMMDD.zip` 且从不删除，`zlib.zipFile` 压到已存在目标即失败——首次成功当天必复现。修复=秒级时间戳命名+压缩前防御 unlink+沙箱产物 finally 删除。**教训：`JSON.stringify(err)` 对 Error 恒得 `{}`（message/stack 非枚举），错误日志必须逐字段记 BusinessError.code/message。**
- **流式健壮性**：`setStreaming` 之后的任何 `await persistMessage` 都必须 try/catch 收尾（failPersist），否则 DB 异常让 UI 永久卡在流式态；兜底持久化的空 `.catch(() => {})` 会静默丢回复，至少要 Logger.warn。
- **zlib.zipFile 虽 API 9 起标记废弃**，但对目录压缩无同位替代（compressFile 只收文件），本次保持使用；换 API 需真机回归。
- **注释里别写 `att_*/cam_*` 这类含 `*/` 的通配符**：块注释提前终止，后续代码被当代码解析，报错点远离真因（全是级联 any/undefined 错）。
- 重构批量替换用 sed 时按形态分三类核对（`{ X,` 开键、`, X }` 中键、独立行），替换后 `grep 残留` + 全量构建兜底；Motion token 替换 40 处即靠三段式 grep 收敛。
- zh/en 词条 parity 与空值已入单测（Core.test i18n 套件）；词条增删后跑 `node scripts/i18n_audit.mjs` 可再审计死词条。
