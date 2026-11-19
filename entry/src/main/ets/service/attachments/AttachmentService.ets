import { fileUri, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { camera, cameraPicker } from '@kit.CameraKit';
import fs from '@ohos.file.fs';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Context } from '@kit.AbilityKit';
import { FileAttachment } from '../../model/ChatTypes';
import { ApiError, ApiErrorKind } from '../api/ApiError';
import { AppContextHolder } from '../../common/AppContextHolder';
import { Logger } from '../../common/Logger';
import { Id } from '../../common/Format';
import { SettingsStore } from '../../prefs/SettingsStore';

const TAG: string = 'AttachmentService';
/** 需要服务端版面解析的扩展名（purpose=rich_layout_recognition），其余 user_data（对齐原版） */
const RICH_EXTS: Set<string> = new Set(['pdf', 'doc', 'docx', 'ppt', 'pptx']);
const IMAGE_EXTS: Set<string> = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic']);
/** 允许上传的扩展名（文档/表格/演示/文本/代码/图片，取自原版清单的常用子集） */
const ACCEPT_EXTS: Set<string> = new Set([
  'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'csv', 'tsv',
  'txt', 'md', 'log', 'html', 'htm', 'json', 'xml', 'yaml', 'yml', 'toml', 'ini', 'conf',
  'ts', 'tsx', 'js', 'jsx', 'py', 'java', 'c', 'h', 'cpp', 'hpp', 'cs', 'go', 'rs', 'swift',
  'kt', 'rb', 'php', 'sh', 'bat', 'sql', 'vue', 'gradle', 'r', 'm', 'pl',
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'svg', 'ico', 'tif', 'tiff', 'avif',
  'epub', 'mobi', 'eml', 'msg',
]);
/** 大小上限（MB）：按 purpose 区分（对齐原版 64/32） */
const MAX_RICH_MB: number = 64;
const MAX_USER_DATA_MB: number = 32;
/** 单会话附件总数上限（对齐原版） */
const MAX_COUNT: number = 50;
/** 常见类型的真实 MIME（上传分片 Content-Type），未命中用 octet-stream */
const MIME_BY_EXT: Map<string, string> = new Map([
  ['pdf', 'application/pdf'],
  ['doc', 'application/msword'],
  ['docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'],
  ['ppt', 'application/vnd.ms-powerpoint'],
  ['pptx', 'application/vnd.openxmlformats-officedocument.presentationml.presentation'],
  ['xls', 'application/vnd.ms-excel'],
  ['xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'],
  ['png', 'image/png'], ['jpg', 'image/jpeg'], ['jpeg', 'image/jpeg'], ['gif', 'image/gif'],
  ['webp', 'image/webp'], ['bmp', 'image/bmp'], ['svg', 'image/svg+xml'], ['ico', 'image/x-icon'],
  ['tif', 'image/tiff'], ['tiff', 'image/tiff'], ['avif', 'image/avif'], ['heic', 'image/heic'],
  ['txt', 'text/plain'], ['md', 'text/markdown'], ['log', 'text/plain'],
  ['csv', 'text/csv'], ['tsv', 'text/tab-separated-values'],
  ['html', 'text/html'], ['htm', 'text/html'], ['json', 'application/json'],
  ['xml', 'text/xml'], ['yaml', 'text/yaml'], ['yml', 'text/yaml'],
  ['epub', 'application/epub+zip'],
]);
/** 文档选择器过滤项（点号后缀） */
const DOC_SUFFIX_FILTERS: string[] = [
  '.pdf', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx', '.csv', '.tsv',
  '.txt', '.md', '.log', '.html', '.htm', '.json', '.xml', '.yaml', '.yml', '.toml', '.ini', '.conf',
  '.ts', '.tsx', '.js', '.jsx', '.py', '.java', '.c', '.h', '.cpp', '.hpp', '.cs', '.go', '.rs',
  '.swift', '.kt', '.rb', '.php', '.sh', '.bat', '.sql', '.vue', '.gradle', '.r', '.m', '.pl',
  '.epub', '.mobi', '.eml', '.msg',
];

/**
 * 附件服务：picker 选择 → 拷贝到应用沙箱 → 上传 Files API（purpose 判定）→ FileAttachment。
 * 对齐原项目 attachments.ts / uploadExts.ts 的核心流程。
 */
export class AttachmentService {
  static extOf(name: string): string {
    const dot = name.lastIndexOf('.');
    if (dot < 0 || dot === name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  static purposeOf(name: string): string | null {
    const ext = AttachmentService.extOf(name);
    if (IMAGE_EXTS.has(ext)) {
      return null; // 图片不传 purpose
    }
    return RICH_EXTS.has(ext) ? 'rich_layout_recognition' : 'user_data';
  }

  static isImage(name: string): boolean {
    return IMAGE_EXTS.has(AttachmentService.extOf(name));
  }

  static isAccepted(name: string): boolean {
    return ACCEPT_EXTS.has(AttachmentService.extOf(name));
  }

  static mimeTypeOf(name: string): string {
    const mime = MIME_BY_EXT.get(AttachmentService.extOf(name));
    return mime === undefined ? 'application/octet-stream' : mime;
  }

  private static maxSizeMb(name: string): number {
    return AttachmentService.purposeOf(name) === 'user_data' ? MAX_USER_DATA_MB : MAX_RICH_MB;
  }

  /** 系统文件选择器（仅文档，不含图片） */
  static async pickDocs(currentCount: number = 0): Promise<FileAttachment[]> {
    const context = AppContextHolder.get() as Context;
    const out: FileAttachment[] = [];
    const remaining = (): number => Math.max(0, MAX_COUNT - currentCount - out.length);
    try {
      const docPicker = new picker.DocumentViewPicker();
      const docOptions = new picker.DocumentSelectOptions();
      docOptions.maxSelectNumber = 9;
      docOptions.fileSuffixFilters = DOC_SUFFIX_FILTERS;
      const uris = await docPicker.select(docOptions);
      for (const uri of uris) {
        if (remaining() <= 0) {
          break;
        }
        const att = await AttachmentService.importUri(context, uri);
        if (att !== null) {
          out.push(att);
        }
      }
    } catch (err) {
      Logger.warn(TAG, `doc pick failed: ${JSON.stringify(err)}`);
    }
    return out;
  }

  /** 系统相册（仅图片） */
  static async pickPhotos(currentCount: number = 0): Promise<FileAttachment[]> {
    const context = AppContextHolder.get() as Context;
    const out: FileAttachment[] = [];
    const remaining = (): number => Math.max(0, MAX_COUNT - currentCount - out.length);
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const photoOptions = new photoAccessHelper.PhotoSelectOptions();
      photoOptions.maxSelectNumber = 9;
      photoOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      const result = await photoPicker.select(photoOptions);
      if (result.photoUris !== undefined) {
        for (const uri of result.photoUris) {
          if (remaining() <= 0) {
            break;
          }
          const att = await AttachmentService.importUri(context, uri);
          if (att !== null) {
            out.push(att);
          }
        }
      }
    } catch (err) {
      Logger.warn(TAG, `photo pick failed: ${JSON.stringify(err)}`);
    }
    return out;
  }

  /** 系统相机拍照（CameraPicker，无需相机权限）；照片经沙箱临时文件导入后清理 */
  static async capture(currentCount: number = 0): Promise<FileAttachment[]> {
    const context = AppContextHolder.get() as Context;
    const out: FileAttachment[] = [];
    if (currentCount >= MAX_COUNT) {
      return out;
    }
    const tmp = `${context.cacheDir}/cam_${Id.next()}.jpg`;
    try {
      const f = fs.openSync(tmp, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.closeSync(f);
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK,
        saveUri: fileUri.getUriFromPath(tmp),
      };
      const result = await cameraPicker.pick(context, [cameraPicker.PickerMediaType.PHOTO], profile);
      if (result.resultCode !== 0 || result.resultUri === '') {
        return out; // 取消或失败
      }
      const att = await AttachmentService.importUri(context, result.resultUri);
      if (att !== null) {
        out.push(att);
      }
    } catch (err) {
      Logger.warn(TAG, `camera pick failed: ${JSON.stringify(err)}`);
    } finally {
      try {
        fs.unlinkSync(tmp);
      } catch (e) {
        // 忽略
      }
    }
    return out;
  }

  /** 拷贝 picker uri 到沙箱并生成附件对象 */
  static async importUri(context: Context, uri: string): Promise<FileAttachment | null> {
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const displayName = AttachmentService.uriFileName(uri);
      if (!AttachmentService.isAccepted(displayName)) {
        Logger.warn(TAG, `unsupported ext: ${displayName}`);
        fs.closeSync(file);
        return null;
      }
      if (stat.size > AttachmentService.maxSizeMb(displayName) * 1024 * 1024) {
        Logger.warn(TAG, `oversize: ${displayName} ${stat.size}`);
        fs.closeSync(file);
        return null;
      }
      const localPath = `${context.cacheDir}/att_${Id.next()}_${displayName}`;
      const dst = fs.openSync(localPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.copyFileSync(file.fd, dst.fd);
      fs.closeSync(file);
      fs.closeSync(dst);
      const att = new FileAttachment();
      att.id = Id.next();
      att.serverId = null;
      att.name = displayName;
      att.size = stat.size;
      att.isImage = AttachmentService.isImage(displayName);
      att.mimeType = '';
      att.localPath = localPath;
      return att;
    } catch (err) {
      Logger.warn(TAG, `import uri failed: ${JSON.stringify(err)}`);
      return null;
    }
  }

  private static uriFileName(uri: string): string {
    // file://media/.../xxx.jpg 或 file://docs/...?name=xxx
    let t = uri;
    const q = t.lastIndexOf('?');
    if (q > 0) {
      t = t.substring(0, q);
    }
    const slash = t.lastIndexOf('/');
    let name = slash >= 0 ? t.substring(slash + 1) : t;
    if (name === '') {
      name = 'file';
    }
    return name;
  }

  /** 附件本地路径 */
  static localPathOf(att: FileAttachment): string {
    return att.localPath;
  }

  /** 上传到 Files API，返回 serverId */
  static async upload(apiKey: string, att: FileAttachment): Promise<string> {
    const localPath = AttachmentService.localPathOf(att);
    if (localPath === '') {
      const kind: ApiErrorKind | 'upload' = 'upload';
      throw new ApiError(kind, 'no local file');
    }
    const stat = fs.statSync(localPath);
    const file = fs.openSync(localPath, fs.OpenMode.READ_ONLY);
    const bytes = new Uint8Array(stat.size);
    fs.readSync(file.fd, bytes.buffer as ArrayBuffer, { offset: 0, length: stat.size });
    fs.closeSync(file);

    const boundary = `ds${Date.now()}${Math.floor(Math.random() * 1e8)}`;
    const purpose = AttachmentService.purposeOf(att.name);
    const parts: Uint8Array[] = [];
    const enc = util.TextEncoder.create('utf-8');
    if (purpose !== null) {
      parts.push(enc.encodeInto(`--${boundary}\r\nContent-Disposition: form-data; name="purpose"\r\n\r\n${purpose}\r\n`));
    }
    const mime = AttachmentService.mimeTypeOf(att.name);
    parts.push(enc.encodeInto(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${att.name}"\r\nContent-Type: ${mime}\r\n\r\n`));
    parts.push(bytes);
    parts.push(enc.encodeInto(`\r\n--${boundary}--\r\n`));
    let total = 0;
    for (const p of parts) {
      total += p.length;
    }
    const body = new Uint8Array(total);
    let off = 0;
    for (const p of parts) {
      body.set(p, off);
      off += p.length;
    }

    const req = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: {
          'x-api-key': apiKey,
          'anthropic-beta': 'files-api-2025-04-14',
          'Content-Type': `multipart/form-data; boundary=${boundary}`,
        },
        extraData: body.buffer as ArrayBuffer,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 300000,
      };
      const resp = await req.request(`${SettingsStore.get().apiOrigin.replace(/\/+$/, '')}/anthropic/v1/files`, options);
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new ApiError('http', AttachmentService.errorMessage(resp.result as string), resp.responseCode);
      }
      const parsed = JSON.parse(resp.result as string) as Record<string, Object>;
      const id = parsed['id'];
      if (typeof id !== 'string' || id === '') {
        throw new ApiError('protocol', resp.result as string);
      }
      att.serverId = id;
      return id;
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
