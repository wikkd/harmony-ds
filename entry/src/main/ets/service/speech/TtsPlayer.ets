import { audio } from '@kit.AudioKit';
import { Logger } from '../../common/Logger';

const TAG: string = 'TtsPlayer';
/** TTS 输出：24kHz 单声道 16-bit 裸 PCM */
const TTS_SAMPLE_RATE: number = 24000;

/**
 * TTS 流式播放：AudioRenderer（MODE_STREAM），逐块 write。
 * 首块到达即开始播放，stop() 立即停止并释放。
 */
export class TtsPlayer {
  private renderer?: audio.AudioRenderer;
  private playing: boolean = false;

  async start(): Promise<void> {
    const streamInfo: audio.AudioStreamInfo = {
      samplingRate: TTS_SAMPLE_RATE,
      channels: audio.AudioChannel.CHANNEL_1,
      sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
      encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
    };
    const rendererInfo: audio.AudioRendererInfo = {
      usage: audio.StreamUsage.STREAM_USAGE_VOICE_ASSISTANT,
      rendererFlags: 0,
    };
    const options: audio.AudioRendererOptions = {
      streamInfo: streamInfo,
      rendererInfo: rendererInfo,
    };
    this.renderer = await audio.createAudioRenderer(options);
    await this.renderer.start();
    this.playing = true;
    Logger.info(TAG, 'renderer started');
  }

  get isPlaying(): boolean {
    return this.playing;
  }

  async write(chunk: ArrayBuffer): Promise<void> {
    if (!this.playing || this.renderer === undefined) {
      return;
    }
    try {
      await this.renderer.write(chunk);
    } catch (err) {
      Logger.warn(TAG, `write failed: ${JSON.stringify(err)}`);
    }
  }

  /** 全部数据写完后调用：排空缓冲 */
  async drain(): Promise<void> {
    // 留少量时间让尾部播完
    await new Promise<void>((resolve) => {
      setTimeout(() => resolve(), 300);
    });
  }

  async stop(): Promise<void> {
    if (!this.playing) {
      return;
    }
    this.playing = false;
    const renderer = this.renderer;
    this.renderer = undefined;
    if (renderer !== undefined) {
      try {
        await renderer.stop();
        await renderer.release();
      } catch (err) {
        Logger.warn(TAG, `stop failed: ${JSON.stringify(err)}`);
      }
    }
  }
}
