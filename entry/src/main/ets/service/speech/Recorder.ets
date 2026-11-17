import { audio } from '@kit.AudioKit';
import fs from '@ohos.file.fs';
import { AppContextHolder } from '../../common/AppContextHolder';
import { Logger } from '../../common/Logger';

const TAG: string = 'Recorder';
/** ASR 要求：WAV（单声道 16-bit PCM），≤120s、≤8MiB */
const SAMPLE_RATE: number = 16000;
const MAX_BYTES: number = 8 * 1024 * 1024;
const MAX_MS: number = 120000;

/**
 * 录音器：AudioCapturer 采集 16kHz/mono/S16LE PCM，停止时封装 WAV 文件。
 * onTick 回调每秒报录音毫秒数（UI 计时）。
 */
export class Recorder {
  private capturer?: audio.AudioCapturer;
  private chunks: ArrayBuffer[] = [];
  private totalBytes: number = 0;
  private startedAt: number = 0;
  private tickTimer: number = -1;
  private stopped: boolean = false;

  onTick?: (ms: number) => void;

  async start(): Promise<void> {
    this.chunks = [];
    this.totalBytes = 0;
    this.stopped = false;
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: SAMPLE_RATE,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
    };
    const capturerInfo: audio.AudioCapturerInfo = {
      source: audio.SourceType.SOURCE_TYPE_MIC,
      capturerFlags: 0,
    };
    const info: audio.AudioCapturerOptions = {
      streamInfo: streamInfo,
      capturerInfo: capturerInfo,
    };
    this.capturer = await audio.createAudioCapturer(info);
    this.capturer.on('readData', (buffer: ArrayBuffer) => {
      if (this.stopped) {
        return;
      }
      this.chunks.push(buffer.slice(0));
      this.totalBytes += buffer.byteLength;
      if (this.totalBytes >= MAX_BYTES || Date.now() - this.startedAt >= MAX_MS) {
        // 达到上限自动停止
        this.stop().catch(() => {});
      }
    });
    await this.capturer.start();
    this.startedAt = Date.now();
    this.tickTimer = setInterval(() => {
      if (this.onTick !== undefined) {
        this.onTick(Date.now() - this.startedAt);
      }
    }, 500);
    Logger.info(TAG, 'recording started');
  }

  /** 停止并写出 WAV 文件，返回文件路径 */
  async stop(): Promise<string | null> {
    if (this.stopped) {
      return null;
    }
    this.stopped = true;
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    const capturer = this.capturer;
    if (capturer === undefined) {
      return null;
    }
    try {
      await capturer.stop();
      capturer.release();
    } catch (err) {
      Logger.warn(TAG, `capturer stop failed: ${JSON.stringify(err)}`);
    }
    this.capturer = undefined;
    if (this.totalBytes === 0) {
      return null;
    }
    // 组装 WAV
    const pcm = new Uint8Array(this.totalBytes);
    let offset = 0;
    for (const c of this.chunks) {
      pcm.set(new Uint8Array(c), offset);
      offset += c.byteLength;
    }
    const wav = Recorder.wrapWav(pcm, SAMPLE_RATE, 1, 16);
    const path = `${AppContextHolder.get().cacheDir}/rec_${Date.now()}.wav`;
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, wav.buffer as ArrayBuffer);
    fs.closeSync(file);
    Logger.info(TAG, `wav saved: ${path} (${this.totalBytes}B pcm)`);
    return path;
  }

  cancel(): void {
    this.stopped = true;
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
    const capturer = this.capturer;
    if (capturer !== undefined) {
      capturer.stop().then(() => capturer.release()).catch(() => {});
      this.capturer = undefined;
    }
    this.chunks = [];
  }

  /** 16-bit PCM → WAV（RIFF 头） */
  static wrapWav(pcm: Uint8Array, sampleRate: number, channels: number, bitsPerSample: number): Uint8Array {
    const dataSize = pcm.length;
    const byteRate = sampleRate * channels * bitsPerSample / 8;
    const blockAlign = channels * bitsPerSample / 8;
    const header = new Uint8Array(44);
    const view = new DataView(header.buffer);
    // RIFF
    header.set([0x52, 0x49, 0x46, 0x46], 0);
    view.setUint32(4, 36 + dataSize, true);
    header.set([0x57, 0x41, 0x56, 0x45], 8); // WAVE
    header.set([0x66, 0x6D, 0x74, 0x20], 12); // fmt
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true); // PCM
    view.setUint16(22, channels, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, byteRate, true);
    view.setUint16(32, blockAlign, true);
    view.setUint16(34, bitsPerSample, true);
    header.set([0x64, 0x61, 0x74, 0x61], 36); // data
    view.setUint32(40, dataSize, true);
    const out = new Uint8Array(44 + dataSize);
    out.set(header, 0);
    out.set(pcm, 44);
    return out;
  }
}
