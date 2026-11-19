/**
 * API 错误分类，对齐原项目 client.ts ApiErrorKind：
 * http 非 2xx；stream 流中错误帧；network 请求未达服务端；interrupted 流提前结束；protocol 协议不符。
 */
export type ApiErrorKind = 'http' | 'stream' | 'network' | 'interrupted' | 'protocol';

export class ApiError extends Error {
  readonly kind: ApiErrorKind | 'upload';
  readonly status?: number;

  constructor(kind: ApiErrorKind | 'upload', message: string, status?: number) {
    super(message);
    this.name = 'ApiError';
    this.kind = kind;
    this.status = status;
  }

  /** 按状态码给出本地化文案键对应的 i18n key（供 UI 层翻译） */
  static i18nKeyFor(err: ApiError): string {
    return ApiError.replyKeyFor(err.kind, err.status);
  }

  /** 回复气泡错误文案键：区分网络/鉴权/余额/限流/服务端/上传 */
  static replyKeyFor(kind: ApiErrorKind | 'upload', status?: number): string {
    if (kind === 'upload') {
      return 'uploadFileStatusFailed';
    }
    if (kind === 'network' || kind === 'interrupted') {
      return 'commonNetworkErrorToast';
    }
    const code = status ?? 0;
    if (kind === 'http' || kind === 'protocol') {
      if (code === 401) {
        return 'replyInvalidApiKey';
      }
      if (code === 402) {
        return 'replyInsufficientBalance';
      }
      if (code === 429) {
        return 'replyRateLimited';
      }
      if (code >= 500) {
        return 'completionServerBusyToast';
      }
    }
    if (kind === 'stream' && code === 529) {
      return 'completionServerBusyToast';
    }
    return 'requestFailed';
  }
}
