import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { Logger } from '../common/Logger';

const TAG: string = 'KeyVault';
const ALIAS: string = 'harmony_ds_api_key';
const FALLBACK_PREF: string = 'chat_demo_key_fallback';

function strToBytes(s: string): Uint8Array {
  return util.TextEncoder.create('utf-8').encodeInto(s);
}

function bytesToStr(b: Uint8Array): string {
  return util.TextDecoder.create('utf-8').decodeToString(b);
}

/**
 * API Key 安全存储：优先系统关键资产库（asset，硬件级保护）。
 * 关键资产不可用的环境（部分模拟器）降级为 Preferences 混淆存储，仅用于开发调试。
 */
export class KeyVault {
  private static fallbackStore?: preferences.Preferences;

  private static async initFallback(context: Context): Promise<void> {
    if (!KeyVault.fallbackStore) {
      KeyVault.fallbackStore = preferences.getPreferencesSync(context, { name: FALLBACK_PREF });
    }
  }

  private static alias(): Uint8Array {
    return strToBytes(ALIAS);
  }

  /** 保存 API Key；已存在则先删后写 */
  static async save(context: Context, apiKey: string): Promise<void> {
    const old: string | null = await KeyVault.load(context);
    if (old !== null && old === apiKey) {
      return;
    }
    await KeyVault.remove(context);
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, KeyVault.alias());
      query.set(asset.Tag.SECRET, strToBytes(apiKey));
      query.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_POWERED_ON);
      await asset.add(query);
      Logger.info(TAG, 'key saved to asset store');
      return;
    } catch (err) {
      Logger.warn(TAG, `asset store unavailable, fallback: ${JSON.stringify(err)}`);
    }
    await KeyVault.initFallback(context);
    if (KeyVault.fallbackStore) {
      // 开发降级路径：可逆混淆，生产环境以真机 asset 为准
      const obfuscated: string = new util.Base64Helper().encodeToStringSync(strToBytes(apiKey));
      await KeyVault.fallbackStore.put('k', obfuscated);
      await KeyVault.fallbackStore.flush();
    }
  }

  static async load(context: Context): Promise<string | null> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, KeyVault.alias());
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const result: Array<asset.AssetMap> = await asset.query(query);
      if (result.length > 0) {
        const data = result[0].get(asset.Tag.SECRET) as Uint8Array;
        if (data && data.length > 0) {
          return bytesToStr(data);
        }
      }
    } catch (err) {
      // 走降级
    }
    await KeyVault.initFallback(context);
    if (KeyVault.fallbackStore) {
      const obfuscated = KeyVault.fallbackStore.getSync('k', '') as string;
      if (obfuscated) {
        const bytes: Uint8Array = new util.Base64Helper().decodeSync(obfuscated);
        return bytesToStr(bytes);
      }
    }
    return null;
  }

  static async remove(context: Context): Promise<void> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, KeyVault.alias());
      await asset.remove(query);
    } catch (err) {
      // 忽略
    }
    await KeyVault.initFallback(context);
    if (KeyVault.fallbackStore) {
      await KeyVault.fallbackStore.delete('k');
      await KeyVault.fallbackStore.flush();
    }
  }

  /** 是否已存 Key（供启动分流） */
  static async exists(context: Context): Promise<boolean> {
    const k = await KeyVault.load(context);
    return k !== null && k.length > 0;
  }
}
