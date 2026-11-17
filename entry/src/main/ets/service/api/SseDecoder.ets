/**
 * SSE（text/event-stream）解析，按 WHATWG 规范实现，逐行移植自原项目 sse.ts。
 * 字节流 → UTF-8 解码（ApiClient）→ 按 CRLF/LF/CR 切行 → 字段累积 → 空行派发事件。
 * 注释行（如服务端保活的 `: keep-alive`）忽略；retry 不处理。
 */
export class ServerSentEvent {
  event: string = '';
  data: string = '';
  lastEventId: string = '';
}

export class ServerSentEventDecoder {
  private buffer: string = '';
  private data: string = '';
  private hasData: boolean = false;
  private eventType: string = '';
  private lastEventId: string = '';

  /** 输入一段已解码的文本，返回其中完整的事件 */
  push(text: string): ServerSentEvent[] {
    this.buffer += text;
    const events: ServerSentEvent[] = [];
    let lineStart = 0;
    for (;;) {
      // 找下一个换行（\r\n / \r / \n）；结尾孤立的 \r 等下一段再判断
      const idxRn = this.buffer.indexOf('\r\n', lineStart);
      const idxCr = this.buffer.indexOf('\r', lineStart);
      const idxLf = this.buffer.indexOf('\n', lineStart);
      let breakIdx = -1;
      let breakLen = 0;
      if (idxRn !== -1 && (idxCr === -1 || idxRn <= idxCr) && (idxLf === -1 || idxRn <= idxLf)) {
        breakIdx = idxRn;
        breakLen = 2;
      } else if (idxCr !== -1 && (idxLf === -1 || idxCr < idxLf)) {
        if (idxCr === this.buffer.length - 1) {
          // 结尾的 CR 可能是 CRLF 的前半
          break;
        }
        breakIdx = idxCr;
        breakLen = 1;
      } else if (idxLf !== -1) {
        breakIdx = idxLf;
        breakLen = 1;
      } else {
        break;
      }
      const line = this.buffer.substring(lineStart, breakIdx);
      lineStart = breakIdx + breakLen;
      const ev = this.processLine(line);
      if (ev !== null) {
        events.push(ev);
      }
    }
    this.buffer = this.buffer.substring(lineStart);
    return events;
  }

  /** 流结束：结尾的 CR 是完整的换行，其余未以空行结尾的事件按规范丢弃 */
  end(): ServerSentEvent[] {
    let ev: ServerSentEvent | null = null;
    if (this.buffer.endsWith('\r')) {
      ev = this.processLine(this.buffer.substring(0, this.buffer.length - 1));
    }
    this.buffer = '';
    this.data = '';
    this.hasData = false;
    this.eventType = '';
    return ev !== null ? [ev] : [];
  }

  private processLine(line: string): ServerSentEvent | null {
    if (line === '') {
      return this.dispatch();
    }
    if (line.startsWith(':')) {
      return null;
    }
    const colon = line.indexOf(':');
    const field = colon === -1 ? line : line.substring(0, colon);
    let value = colon === -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    if (field === 'data') {
      this.data = this.hasData ? `${this.data}\n${value}` : value;
      this.hasData = true;
    } else if (field === 'event') {
      this.eventType = value;
    } else if (field === 'id') {
      if (!value.includes('\u0000')) {
        this.lastEventId = value;
      }
    }
    return null;
  }

  private dispatch(): ServerSentEvent | null {
    let ev: ServerSentEvent | null = null;
    if (this.hasData) {
      ev = new ServerSentEvent();
      ev.event = this.eventType === '' ? 'message' : this.eventType;
      ev.data = this.data;
      ev.lastEventId = this.lastEventId;
    }
    this.data = '';
    this.hasData = false;
    this.eventType = '';
    return ev;
  }
}
