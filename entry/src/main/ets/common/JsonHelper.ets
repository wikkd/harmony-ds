/** JSON 安全取值工具：EventParser 使用，未识别字段静默丢弃 */
export class Json {
  static rec(value: Object | undefined | null): Record<string, Object> | null {
    if (value === null || value === undefined) {
      return null;
    }
    try {
      const r = value as Record<string, Object>;
      if (r instanceof Array) {
        return null;
      }
      return r;
    } catch (e) {
      return null;
    }
  }

  static arr(value: Object | undefined | null): Array<Object> | null {
    if (value === null || value === undefined) {
      return null;
    }
    if (value instanceof Array) {
      return value as Array<Object>;
    }
    return null;
  }

  static str(value: Object | undefined | null): string | null {
    if (typeof value === 'string') {
      return value as string;
    }
    return null;
  }

  static num(value: Object | undefined | null): number | null {
    if (typeof value === 'number' && Number.isFinite(value as number)) {
      return value as number;
    }
    return null;
  }

  static int(value: Object | undefined | null): number | null {
    const n = Json.num(value);
    if (n !== null && Number.isSafeInteger(n) && n >= 0) {
      return n;
    }
    return null;
  }

  static optStr(value: Object | undefined | null): string | undefined {
    if (value === undefined) {
      return undefined;
    }
    return Json.str(value) ?? undefined;
  }

  static getRec(obj: Record<string, Object>, key: string): Record<string, Object> | null {
    return Json.rec(obj[key]);
  }

  static getStr(obj: Record<string, Object>, key: string): string | null {
    return Json.str(obj[key]);
  }

  static getInt(obj: Record<string, Object>, key: string): number | null {
    return Json.int(obj[key]);
  }

  static getArr(obj: Record<string, Object>, key: string): Array<Object> | null {
    return Json.arr(obj[key]);
  }
}
