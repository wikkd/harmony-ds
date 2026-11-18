import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ServerSentEvent, ServerSentEventDecoder } from './SseDecoder';
import { ApiError } from './ApiError';
import { parseMessageEvent } from './EventParser';
import { StreamEvent } from '../../model/ApiTypes';
import { Logger } from '../../common/Logger';
import { SettingsStore } from '../../prefs/SettingsStore';

const TAG: string = 'ApiClient';
/** Anthropic 兼容接口前缀 */
const ANTHROPIC_BASE_PATH: string = '/anthropic/v1';
/** Files API 与 file_id 引用图片时必传 */
const FILES_BETA: string = 'files-api-2025-04-14';
const CONNECT_TIMEOUT_MS: number = 15000;
const READ_TIMEOUT_MS: number = 600000;

export interface StreamCallbacks {
  onEvent: (event: StreamEvent) => void;
  onError: (err: ApiError) => void;
  onDone: () => void;
}

/** 中止句柄：UI 的停止按钮调用 abort() */
export class StreamAborter {
  private request?: http.HttpRequest;
  private aborted: boolean = false;

  abort(): void {
    this.aborted = true;
    try {
      this.request?.destroy();
    } catch (e) {
      // 忽略
    }
  }

  isAborted(): boolean {
    return this.aborted;
  }

  internal(): http.HttpRequest | undefined {
    return this.request;
  }

  internalSet(req: http.HttpRequest): void {
    this.request = req;
  }

  internalIsAborted(): boolean {
    return this.aborted;
  }
}

export class ApiClient {
  static apiOrigin(): string {
    return SettingsStore.get().apiOrigin.replace(/\/+$/, '');
  }

  private static anthropicUrl(path: string): string {
    return `${ApiClient.apiOrigin()}${ANTHROPIC_BASE_PATH}${path}`;
  }

  /**
   * POST /anthropic/v1/messages（stream: true）。
   * 收到 message_stop 时 onDone；流中出现错误帧或提前断开时 onError。
   * withFiles: 请求含 file_id 引用时必须带 anthropic-beta 头。
   */
  static streamMessage(apiKey: string, bodyJson: string, callbacks: StreamCallbacks, withFiles: boolean = false): StreamAborter {
    const aborter = new StreamAborter();
    const req = http.createHttp();
    aborter.internalSet(req);

    const decoder = new ServerSentEventDecoder();
    const utf8 = util.TextDecoder.create('utf-8');
    let statusCode = 0;
    let contentType = '';
    let sawMessageStop = false;
    let finished = false;
    let errorBody = '';
    let sseMode = false;

    const fail = (err: ApiError): void => {
      if (finished) {
        return;
      }
      finished = true;
      try {
        req.destroy();
      } catch (e) {
        // 忽略
      }
      callbacks.onError(err);
    };

    req.on('headersReceive', (headers: Object) => {
      const h = headers as Record<string, string>;
      const ctKey = Object.keys(h).find((k) => k.toLowerCase() === 'content-type');
      if (ctKey !== undefined) {
        contentType = h[ctKey] ?? '';
      }
    });

    req.on('dataReceive', (chunk: ArrayBuffer) => {
      if (aborter.internalIsAborted() || finished) {
        return;
      }
      const bytes = new Uint8Array(chunk);
      if (sseMode) {
        const text = utf8.decodeToString(bytes, { stream: true });
        const events: ServerSentEvent[] = decoder.push(text);
        for (const ev of events) {
          if (ev.event === 'error') {
            fail(new ApiError('stream', ev.data));
            return;
          }
          let payload: Record<string, Object> | null;
          try {
            payload = JSON.parse(ev.data) as Record<string, Object>;
          } catch (e) {
            payload = null;
          }
          if (payload !== null) {
            // 流中无名 error 帧（如等待生成超时）
            const errRec = payload['error'];
            if (errRec !== null && errRec !== undefined) {
              const errObj = errRec as Record<string, Object>;
              const msg = typeof errObj['message'] === 'string' ? errObj['message'] as string : ev.data;
              fail(new ApiError('stream', msg));
              return;
            }
            const parsed = parseMessageEvent(payload);
            if (parsed !== null) {
              if (parsed.type === 'message_stop') {
                sawMessageStop = true;
              }
              callbacks.onEvent(parsed);
            }
          }
        }
      } else {
        // 非 SSE（错误响应体）累积原文
        errorBody += utf8.decodeToString(bytes, { stream: true });
      }
    });

    req.on('dataEnd', () => {
      if (aborter.internalIsAborted() || finished) {
        return;
      }
      if (!sseMode) {
        // HTTP 错误体：解析 error.message
        let message = errorBody;
        try {
          const parsed = JSON.parse(errorBody) as Record<string, Object>;
          const errRec = parsed['error'];
          if (errRec !== null && errRec !== undefined) {
            const errObj = errRec as Record<string, Object>;
            if (typeof errObj['message'] === 'string') {
              message = errObj['message'] as string;
            }
          }
        } catch (e) {
          // 非 JSON 响应体直接展示原文
        }
        fail(new ApiError(statusCode >= 200 && statusCode < 300 ? 'protocol' : 'http',
          message === '' ? 'unknown error' : message, statusCode > 0 ? statusCode : undefined));
        return;
      }
      // 收尾：派发残尾事件
      const tail: ServerSentEvent[] = decoder.push(utf8.decodeToString(new Uint8Array(0)));
      const tailEnd: ServerSentEvent[] = decoder.end();
      for (const evEnd of tailEnd) {
        tail.push(evEnd);
      }
      for (const ev of tail) {
        if (ev.event === 'error') {
          fail(new ApiError('stream', ev.data));
          return;
        }
        try {
          const payload = JSON.parse(ev.data) as Record<string, Object>;
          if (payload !== null && payload['error'] !== undefined) {
            fail(new ApiError('stream', ev.data));
            return;
          }
          const parsed = parseMessageEvent(payload);
          if (parsed !== null) {
            if (parsed.type === 'message_stop') {
              sawMessageStop = true;
            }
            callbacks.onEvent(parsed);
          }
        } catch (e) {
          // 无法解析的内容忽略
        }
      }
      if (sawMessageStop) {
        finished = true;
        try {
          req.destroy();
        } catch (e) {
          // 忽略
        }
        callbacks.onDone();
      } else {
        // 流在 message_stop 之前结束
        fail(new ApiError('interrupted', ''));
      }
    });

    (async () => {
      try {
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.POST,
          header: {
            'x-api-key': apiKey,
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
          extraData: bodyJson,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: CONNECT_TIMEOUT_MS,
          readTimeout: READ_TIMEOUT_MS,
        };
        if (withFiles) {
          (options.header as Record<string, string>)['anthropic-beta'] = FILES_BETA;
        }
        const code = await req.requestInStream(ApiClient.anthropicUrl('/messages'), options);
        statusCode = code;
        if (code >= 200 && code < 300) {
          if (contentType.includes('text/event-stream')) {
            sseMode = true;
          } else {
            // 等 dataEnd 收完错误/异常体后按 protocol 处理
            Logger.warn(TAG, `non-sse content-type: ${contentType}`);
          }
        } else {
          Logger.warn(TAG, `HTTP ${code}`);
        }
      } catch (err) {
        if (aborter.internalIsAborted()) {
          // 用户主动停止：不算错误
          finished = true;
          return;
        }
        Logger.error(TAG, `requestInStream failed: ${JSON.stringify(err)}`);
        fail(new ApiError('network', `${JSON.stringify(err)}`));
      }
    })();

    return aborter;
  }

  /** 非流式一次性补全（compact 摘要等）：返回全部 text 块拼接 */
  static async completeOnce(apiKey: string, bodyJson: string): Promise<string> {
    const req = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'x-api-key': apiKey,
          'Content-Type': 'application/json',
        },
        extraData: bodyJson,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: 300000,
      };
      const resp = await req.request(ApiClient.anthropicUrl('/messages'), options);
      const text = resp.result as string;
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new ApiError('http', text, resp.responseCode);
      }
      const parsed = JSON.parse(text) as Record<string, Object>;
      const content = parsed['content'];
      if (!Array.isArray(content)) {
        throw new ApiError('protocol', text);
      }
      let out = '';
      for (const b of content as Array<Object>) {
        const block = b as Record<string, Object>;
        if (block['type'] === 'text' && typeof block['text'] === 'string') {
          out += block['text'] as string;
        }
      }
      return out.trim();
    } catch (err) {
      if (err instanceof ApiError) {
        throw err as ApiError;
      }
      throw new ApiError('network', `${JSON.stringify(err)}`);
    } finally {
      try {
        req.destroy();
      } catch (e) {
        // 忽略
      }
    }
  }

  /** GET /models 校验 API Key（不产生费用） */
  static async verifyApiKey(apiKey: string): Promise<void> {
    const req = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: { 'Authorization': `Bearer ${apiKey}` },
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: 30000,
      };
      const resp = await req.request(`${ApiClient.apiOrigin()}/models`, options);
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        return;
      }
      let message = `${resp.responseCode}`;
      try {
        const parsed = JSON.parse(resp.result as string) as Record<string, Object>;
        const errRec = parsed['error'];
        if (errRec !== null && errRec !== undefined) {
          const errObj = errRec as Record<string, Object>;
          if (typeof errObj['message'] === 'string') {
            message = errObj['message'] as string;
          }
        }
      } catch (e) {
        // 保底
      }
      throw new ApiError('http', message, resp.responseCode);
    } catch (err) {
      if (err instanceof ApiError) {
        throw err as ApiError;
      }
      throw new ApiError('network', `${JSON.stringify(err)}`);
    } finally {
      try {
        req.destroy();
      } catch (e) {
        // 忽略
      }
    }
  }
}
