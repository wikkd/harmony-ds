/**
 * API 错误分类，对齐原项目 client.ts ApiErrorKind：
 * http 非 2xx；stream 流中错误帧；network 请求未达服务端；interrupted 流提前结束；protocol 协议不符。
 */
export type ApiErrorKind = 'http' | 'stream' | 'network' | 'interrupted' | 'protocol';

export class ApiError extends Error {
  readonly kind: ApiErrorKind;
  readonly status?: number;

  constructor(kind: ApiErrorKind, message: string, status?: number) {
    super(message);
    this.name = 'ApiError';
    this.kind = kind;
    this.status = status;
  }

  /** 按状态码给出本地化文案键对应的 i18n key（供 UI 层翻译） */
  static i18nKeyFor(err: ApiError): string {
    if (err.kind === 'network') {
      return 'commonNetworkErrorToast';
    }
    if (err.kind === 'interrupted') {
      return 'commonNetworkErrorToast';
    }
    const status = err.status ?? 0;
    if (err.kind === 'http' || err.kind === 'protocol') {
      if (status === 401) {
        return 'replyInvalidApiKey';
      }
      if (status === 402) {
        return 'replyInsufficientBalance';
      }
      if (status === 429) {
        return 'replyRateLimited';
      }
      if (status >= 500) {
        return 'completionServerBusyToast';
      }
    }
    if (err.kind === 'stream' && status === 529) {
      return 'completionServerBusyToast';
    }
    return 'unknownError';
  }
}
