/**
 * 模型元信息（与官方「模型 & 价格」页对齐）。
 * deepseek-flash：上下文 1M，最大输出 384K。
 */
export class ModelInfo {
  static readonly NAME: string = 'deepseek-flash';
  /** 内置（走 DeepSeek 完整协议）的模型名；其余视为外部自定义模型 */
  static readonly BUILTIN_MODELS: string[] = ['deepseek-flash', 'deepseek-v4-pro'];
  /** 外部 Anthropic 兼容模型的 max_tokens（协议必填，DeepSeek 端可省略） */
  static readonly EXTERNAL_MAX_TOKENS: number = 8192;

  static isBuiltin(name: string): boolean {
    return ModelInfo.BUILTIN_MODELS.indexOf(name.trim()) >= 0;
  }
  /** 上下文长度（tokens） */
  static readonly CONTEXT_LIMIT: number = 1000000;
  /** 最大输出长度（tokens） */
  static readonly MAX_OUTPUT: number = 384000;

  /** 官方单价：元 / 百万 tokens（搜索为 元/次，5 元/千次） */
  static readonly PRICE_IN_MISS_IDLE: number = 1;
  static readonly PRICE_IN_MISS_PEAK: number = 2;
  static readonly PRICE_IN_HIT_IDLE: number = 0.02;
  static readonly PRICE_IN_HIT_PEAK: number = 0.04;
  static readonly PRICE_OUT_IDLE: number = 4;
  static readonly PRICE_OUT_PEAK: number = 8;
  static readonly PRICE_SEARCH_PER_CALL: number = 0.005;

  /** 单次回复费用估算（元）：输入按命中/未命中分开计价，输出与搜索按请求时段峰谷 */
  static replyCost(peak: boolean, inMiss: number, inHit: number, out: number, searches: number): number {
    const m = 1000000;
    const inMissCost = (inMiss / m) * (peak ? ModelInfo.PRICE_IN_MISS_PEAK : ModelInfo.PRICE_IN_MISS_IDLE);
    const inHitCost = (inHit / m) * (peak ? ModelInfo.PRICE_IN_HIT_PEAK : ModelInfo.PRICE_IN_HIT_IDLE);
    const outCost = (out / m) * (peak ? ModelInfo.PRICE_OUT_PEAK : ModelInfo.PRICE_OUT_IDLE);
    return inMissCost + inHitCost + outCost + searches * ModelInfo.PRICE_SEARCH_PER_CALL;
  }
}
