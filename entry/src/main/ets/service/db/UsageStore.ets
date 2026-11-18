import { ModelInfo } from '../../model/ModelInfo';
import { PeakPeriod } from '../../common/PeakPeriod';
import { ChatDb } from './ChatDb';
import { Logger } from '../../common/Logger';

const TAG: string = 'UsageStore';

/** 一条回执的用量记录（按请求时刻判定峰谷并估算费用） */
export class UsageRecord {
  /** 请求发起时刻（ms） */
  ts: number = 0;
  /** 输入（缓存未命中）= inputTokens + cacheCreationInputTokens */
  inputMiss: number = 0;
  /** 输入（缓存命中）= cacheReadInputTokens */
  inputHit: number = 0;
  /** 输出 tokens */
  output: number = 0;
  /** 联网搜索次数 */
  searches: number = 0;
  /** 请求时段是否高峰 */
  peak: boolean = false;
  /** 估算费用（元） */
  cost: number = 0;
}

/**
 * 用量归集：从本地消息库解析 assistant 回执 usage（payloadJson 内），
 * 兼容历史数据，无需独立流水表。
 */
export class UsageStore {
  static async load(): Promise<UsageRecord[]> {
    const out: UsageRecord[] = [];
    try {
      const payloads = await ChatDb.assistantPayloads();
      for (const p of payloads) {
        const obj = JSON.parse(p) as Record<string, Object>;
        const usageStr = obj['usage'];
        if (typeof usageStr !== 'string' || usageStr === '') {
          continue;
        }
        let u: Record<string, number>;
        try {
          u = JSON.parse(usageStr) as Record<string, number>;
        } catch (e) {
          continue;
        }
        const rec = new UsageRecord();
        rec.ts = (obj['createdAt'] as number) ?? 0;
        rec.inputMiss = ((u['inputTokens'] as number) ?? 0) + ((u['cacheCreationInputTokens'] as number) ?? 0);
        rec.inputHit = (u['cacheReadInputTokens'] as number) ?? 0;
        rec.output = (u['outputTokens'] as number) ?? 0;
        rec.searches = (u['webSearchRequests'] as number) ?? 0;
        rec.peak = PeakPeriod.isPeak(new Date(rec.ts));
        rec.cost = ModelInfo.replyCost(rec.peak, rec.inputMiss, rec.inputHit, rec.output, rec.searches);
        if (rec.inputMiss + rec.inputHit + rec.output > 0 || rec.searches > 0) {
          out.push(rec);
        }
      }
    } catch (err) {
      Logger.warn(TAG, `load usage failed: ${JSON.stringify(err)}`);
    }
    return out;
  }
}
