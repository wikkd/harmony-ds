import { http } from '@kit.NetworkKit';
import fs from '@ohos.file.fs';
import { util } from '@kit.ArkTS';
import { ApiError } from '../api/ApiError';
import { Logger } from '../../common/Logger';
import { SettingsStore } from '../../prefs/SettingsStore';

const TAG: string = 'SpeechApi';
const CONNECT_TIMEOUT_MS: number = 15000;

export type TtsVoice = 'stella' | 'tide';

export interface TtsCallbacks {
  onChunk: (chunk: ArrayBuffer) => void;
  onDone: () => void;
  onError: (err: ApiError) => void;
}

/** 语音接口：ASR POST /v1/tools/asr；TTS POST /v1/tools/tts（对齐原项目 speech.ts） */
export class SpeechApi {
  private static toolsUrl(path: string): string {
    return `${SettingsStore.get().apiOrigin.replace(/\/+$/, '')}/v1/tools${path}`;
  }

  /** 语音识别：上传 WAV，返回 {text} */
  static async transcribe(apiKey: string, wavPath: string): Promise<string> {
    const stat = fs.statSync(wavPath);
    const file = fs.openSync(wavPath, fs.OpenMode.READ_ONLY);
    const wav = new Uint8Array(stat.size);
    fs.readSync(file.fd, wav.buffer as ArrayBuffer, { offset: 0, length: stat.size });
    fs.closeSync(file);
    if (stat.size > 8 * 1024 * 1024) {
      throw new ApiError('http', 'file too large', 413);
    }

    const boundary = `ds${Date.now()}${Math.floor(Math.random() * 1e8)}`;
    const pre = `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="recording.wav"\r\nContent-Type: audio/wav\r\n\r\n`;
    const post = `\r\n--${boundary}--\r\n`;
    const preBytes = util.TextEncoder.create('utf-8').encodeInto(pre);
    const postBytes = util.TextEncoder.create('utf-8').encodeInto(post);
    const body = new Uint8Array(preBytes.length + wav.length + postBytes.length);
    body.set(preBytes, 0);
    body.set(wav, preBytes.length);
    body.set(postBytes, preBytes.length + wav.length);

    const req = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': `multipart/form-data; boundary=${boundary}`,
        },
        extraData: body.buffer as ArrayBuffer,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: CONNECT_TIMEOUT_MS,
        readTimeout: 60000,
      };
      const resp = await req.request(SpeechApi.toolsUrl('/asr'), options);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new ApiError('http', SpeechApi.errorMessage(resp.result as string), resp.responseCode);
      }
      const parsed = JSON.parse(resp.result as string) as Record<string, Object>;
      const text = parsed['text'];
      if (typeof text !== 'string') {
        throw new ApiError('protocol', resp.result as string);
      }
      return text;
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

  /** 语音合成：流式接收 24kHz PCM，逐块回调（首帧即播） */
  static synthesize(apiKey: string, text: string, voice: TtsVoice, callbacks: TtsCallbacks): void {
    const req = http.createHttp();
    let sseLike = false;
    req.on('dataReceive', (chunk: ArrayBuffer) => {
      if (chunk.byteLength > 0) {
        callbacks.onChunk(chunk);
      }
    });
    req.on('dataEnd', () => {
      if (!sseLike) {
        callbacks.onDone();
      }
    });
    (async () => {
      try {
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.POST,
          header: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json',
          },
          extraData: JSON.stringify({
            'text': text,
            'voice_id': voice,
            'format': 'pcm',
            'filter_markdown': true,
          }),
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: CONNECT_TIMEOUT_MS,
          readTimeout: 300000,
        };
        const code = await req.requestInStream(SpeechApi.toolsUrl('/tts'), options);
        if (code < 200 || code >= 300) {
          // 错误体（JSON）会经 dataReceive 到达，但此处无法区分；等 dataEnd 收尾判断
          Logger.warn(TAG, `tts http ${code}`);
          sseLike = true;
          callbacks.onError(new ApiError('http', `HTTP ${code}`, code));
        }
      } catch (err) {
        callbacks.onError(new ApiError('network', `${JSON.stringify(err)}`));
      }
    })();
  }

  private static errorMessage(body: string): string {
    try {
      const parsed = JSON.parse(body) as Record<string, Object>;
      const errRec = parsed['error'];
      if (errRec !== null && errRec !== undefined) {
        const errObj = errRec as Record<string, Object>;
        if (typeof errObj['message'] === 'string') {
          return errObj['message'] as string;
        }
      }
    } catch (e) {
      // 保底
    }
    return body === '' ? 'unknown error' : body;
  }
}
