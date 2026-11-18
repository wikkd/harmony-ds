import { Want } from '@kit.AbilityKit';
import BuildProfile from 'BuildProfile';
import { ChatStore } from '../service/chat/ChatStore';
import { ReplyBlock } from '../model/ChatTypes';
import { MessageUsage } from '../model/ApiTypes';
import { ApiClient } from '../service/api/ApiClient';
import { ReplyEngine } from '../service/chat/ReplyEngine';
import { KeyVault } from '../prefs/KeyVault';
import { AppContextHolder } from './AppContextHolder';
import { Logger } from './Logger';

const TAG = 'TestHarness';

/**
 * 测试注入器：Debug 构建下经 `aa start ... --ps testInject=<场景>` 触发，
 * 向当前会话注入固定消息夹具后走真实渲染管线，供真机自动化用 dumpLayout
 * 断言渲染结果——绕开 IME 组合串被清、坐标漂移等 UI 驱动的不确定性。
 * Release 构建（DEBUG=false）直接空操作，不进上架包行为。
 */
export class TestHarness {

  static handle(want: Want): void {
    if (!BuildProfile.DEBUG) {
      return;
    }
    const scene = want.parameters?.['testInject'];
    if (typeof scene === 'string' && scene !== '') {
      TestHarness.run(scene).catch((e: Object) => {
        Logger.error(TAG, `inject ${scene} failed: ${JSON.stringify(e)}`);
      });
    }
    // 测试 Key 引导：真实走 GET /models 校验后入 KeyVault（Key 只经命令行参数传入，不落代码库）
    const key = want.parameters?.['testKey'];
    if (typeof key === 'string' && key !== '') {
      TestHarness.setupKey(key).catch((e: Object) => {
        Logger.error(TAG, `testKey failed: ${JSON.stringify(e)}`);
      });
    }
    // 真实发送：注入用户消息后走完整 ReplyEngine（真 SSE/思考/搜索），绕开 IME 发送的时序不确定性
    const sendText = want.parameters?.['testSend'];
    if (typeof sendText === 'string' && sendText !== '') {
      TestHarness.sendReal(sendText).catch((e: Object) => {
        Logger.error(TAG, `testSend failed: ${JSON.stringify(e)}`);
      });
    }
  }

  private static async sendReal(text: string): Promise<void> {
    const store = ChatStore.get();
    for (let i = 0; i < 25 && !store.isReady; i++) {
      await TestHarness.sleep(200);
    }
    const sessionId = store.currentSessionId;
    if (sessionId === '') {
      Logger.error(TAG, 'testSend: no session');
      return;
    }
    ReplyEngine.send(sessionId, text);
    Logger.info(TAG, `testSend dispatched: ${text.length} chars to ${sessionId}`);
  }

  private static async setupKey(key: string): Promise<void> {
    await ApiClient.verifyApiKey(key.trim());
    await KeyVault.save(AppContextHolder.get(), key.trim());
    AppStorage.setOrCreate<boolean>('hasApiKey', true);
    Logger.info(TAG, 'testKey verified & saved');
  }

  private static async run(scene: string): Promise<void> {
    const store = ChatStore.get();
    // 冷启动时 onCreate 先于 restore 完成：等恢复结束再注入
    for (let i = 0; i < 25 && !store.isReady; i++) {
      await TestHarness.sleep(200);
    }
    await store.newSession();
    const session = store.current();
    let question = '';
    let answer = '';
    if (scene === 'math') {
      question = '数学公式渲染测试';
      answer = '三种定界符渲染如下。\n\n'
        + '$$x=\\frac{-b\\pm\\sqrt{b^2-4ac}}{2a}$$\n\n'
        + '\\[e^{i\\pi}+1=0\\]\n\n'
        + '行内写法：质能方程 \\(E=mc^2\\) 与勾股定理 \\(a^2+b^2=c^2\\)。';
    } else if (scene === 'md') {
      question = 'Markdown 渲染测试';
      answer = '## 二级标题\n\n'
        + '这是**加粗**、*斜体*、~~删除线~~、行内 `code()` 与[链接](https://example.com)。\n\n'
        + '- 无序列表一\n- 无序列表二\n  - 嵌套项\n\n'
        + '1. 有序第一\n2. 有序第二\n\n'
        + '- [x] 已完成任务\n- [ ] 待办任务\n\n'
        + '> 引用块：自适应容器里的竖条要用 border 绘制。\n\n'
        + '| 列一 | 列二 |\n| --- | ---: |\n| 甲 | 12 |\n| 乙 | 345 |\n\n'
        + '```ts\nconst ok: boolean = true;\n```\n\n---';
    } else if (scene === 'long') {
      question = '长文滚动测试';
      let sb = '下面是 30 段长文，用于滚动与定位条验证。\n\n';
      for (let i = 1; i <= 30; i++) {
        sb += `${i}. 第 ${i} 段：内容观察点 ${i * 7}，流式渲染下整块重渲由父层节流控制。\n\n`;
      }
      answer = sb;
    } else {
      Logger.warn(TAG, `unknown scene: ${scene}`);
      return;
    }
    session.title = `注入测试·${scene}`;
    await store.renameSession(session.id, session.title);
    const userMsg = store.appendUserMessage(session, question, null);
    const reply = store.appendAssistantPlaceholder(session, userMsg.id, false, false);
    const block = new ReplyBlock();
    block.type = 'text';
    block.textPart.text = answer;
    reply.blocks.push(block);
    reply.status = 'done';
    reply.model = 'deepseek-flash';
    reply.stopReason = 'end_turn';
    const usage = new MessageUsage();
    usage.inputTokens = 24;
    usage.outputTokens = 512;
    reply.usage = usage;
    await store.persistMessage(session, userMsg);
    await store.persistMessage(session, reply);
    // append 不自动刷可见链：switchTo 内部重算 visible 并 bump 版本
    await store.switchTo(session.id);
    Logger.info(TAG, `injected ${scene}: messages=${session.messages.length}, visible=${store.visible.length}`);
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
