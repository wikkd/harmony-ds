import { picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
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
/** 需要服务端版面解析的扩展名（purpose=rich_layout_recognition），其余 user_data */
const RICH_EXTS: Set<string> = new Set(['pdf', 'doc', 'docx', 'ppt', 'pptx']);
const IMAGE_EXTS: Set<string> = new Set(['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic']);
const MAX_FILE_MB: number = 100;

export interface FileObject {
  id: string;
  sizeBytes: number;
  filename: string;
  mimeType: string;
}

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

  /** 系统文件选择器（文档+图片混合） */
  static async pick(): Promise<FileAttachment[]> {
    const context = AppContextHolder.get() as Context;
    const out: FileAttachment[] = [];
    // 文档
    try {
      const docPicker = new picker.DocumentViewPicker();
      const docOptions = new picker.DocumentSelectOptions();
      docOptions.maxSelectNumber = 9;
      const uris = await docPicker.select(docOptions);
      for (const uri of uris) {
        const att = await AttachmentService.importUri(context, uri);
        if (att !== null) {
          out.push(att);
        }
      }
    } catch (err) {
      Logger.warn(TAG, `doc pick failed: ${JSON.stringify(err)}`);
    }
    // 图片
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const photoOptions = new photoAccessHelper.PhotoSelectOptions();
      photoOptions.maxSelectNumber = 9;
      photoOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      const result = await photoPicker.select(photoOptions);
      if (result.photoUris !== undefined) {
        for (const uri of result.photoUris) {
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

  /** 拷贝 picker uri 到沙箱并生成附件对象 */
  static async importUri(context: Context, uri: string): Promise<FileAttachment | null> {
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      if (stat.size > MAX_FILE_MB * 1024 * 1024) {
        fs.closeSync(file);
        return null;
      }
      const displayName = AttachmentService.uriFileName(uri);
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
    parts.push(enc.encodeInto(`--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="${att.name}"\r\nContent-Type: application/octet-stream\r\n\r\n`));
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
