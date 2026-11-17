import { Context } from '@kit.AbilityKit';

/** 全局应用 Context：EntryAbility onCreate 时注入，供非 Ability 场景使用 */
export class AppContextHolder {
  private static context?: Context;

  static set(context: Context): void {
    AppContextHolder.context = context;
  }

  static get(): Context {
    if (!AppContextHolder.context) {
      throw new Error('AppContextHolder not initialized. EntryAbility.onCreate must call set().');
    }
    return AppContextHolder.context;
  }
}
