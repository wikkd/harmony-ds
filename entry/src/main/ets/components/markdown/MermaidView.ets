/**
 * Mermaid 图表 Canvas 自绘（子集）：flowchart（TD/LR 方向、矩形/圆角/菱形节点、实虚线箭头）、
 * sequenceDiagram（参与者/消息箭头）、pie。解析失败降级为代码块展示。
 */
import { Dim } from '../../common/DesignTokens';
import { CodeBlock } from './CodeBlock';

// Canvas 中性色板：与主题无关的固定视觉（Canvas 不直接引用资源色）
const CANVAS_TEXT = '#E6000000';
const CANVAS_LINE = '#99000000';
const CANVAS_BRAND = '#0A59F7';
const CANVAS_CARD = '#FFFFFF';

class MermaidNode {
  id: string = '';
  label: string = '';
  shape: string = 'rect'; // rect | round | diamond | stadium
}

class MermaidEdge {
  from: string = '';
  to: string = '';
  label: string = '';
  dashed: boolean = false;
}

class FlowGraph {
  dir: string = 'TD';
  nodes: MermaidNode[] = [];
  edges: MermaidEdge[] = [];

  nodeById(id: string): MermaidNode | null {
    for (const n of this.nodes) {
      if (n.id === id) {
        return n;
      }
    }
    return null;
  }
}

class SeqMessage {
  from: string = '';
  to: string = '';
  text: string = '';
  dashed: boolean = false;
}

class MermaidParser {
  static parse(src: string): FlowGraph | null {
    const lines = src.replace(/\r/g, '').split('\n');
    const first = lines.length > 0 ? lines[0].trim() : '';
    if (first.startsWith('graph') || first.startsWith('flowchart')) {
      const g = new FlowGraph();
      const parts = first.split(/\s+/);
      g.dir = parts.length > 1 ? parts[1] : 'TD';
      for (let i = 1; i < lines.length; i++) {
        const line = lines[i].trim();
        if (line === '' || line.startsWith('%%')) {
          continue;
        }
        MermaidParser.parseFlowLine(g, line);
      }
      return g.nodes.length > 0 ? g : null;
    }
    return null;
  }

  /** 一行：A[文本] --> B(文本) 或 A ---|label| B */
  private static parseFlowLine(g: FlowGraph, line: string): void {
    const edgeMatch = /(---|-->|-\.->|==>)\s*(?:\|([^|]*)\|\s*)?/g;
    // 提取所有节点定义与边
    const nodeRe = /([A-Za-z0-9_]+)\s*(\(|\[|\{)?\s*([^)\]}]*)?\s*(\)|\]|\})?/g;
    // 简化实现：按边符号切分
    const edgeSplit = line.split(/(\-\->|\-\.\->|==\>|---)/);
    if (edgeSplit.length >= 3) {
      const left = edgeSplit[0].trim();
      const arrow = edgeSplit[1];
      let right = edgeSplit[edgeSplit.length - 1].trim();
      let label = '';
      const pipeIdx = right.indexOf('|');
      if (pipeIdx >= 0 && right.endsWith('|')) {
        label = right.substring(pipeIdx + 1, right.length - 1).trim();
        right = right.substring(0, pipeIdx).trim();
      } else if (pipeIdx >= 0) {
        label = right.substring(pipeIdx + 1).trim();
        right = right.substring(0, pipeIdx).trim();
      }
      const from = MermaidParser.upsertNode(g, left);
      const to = MermaidParser.upsertNode(g, right);
      if (from !== null && to !== null) {
        const e = new MermaidEdge();
        e.from = from.id;
        e.to = to.id;
        e.label = label;
        e.dashed = arrow === '-.->';
        g.edges.push(e);
      }
    } else {
      // 单独的节点定义行
      MermaidParser.upsertNode(g, line);
    }
  }

  private static upsertNode(g: FlowGraph, raw: string): MermaidNode | null {
    const t = raw.trim();
    if (t === '') {
      return null;
    }
    let id = t;
    let label = t;
    let shape = 'rect';
    const open = t.search(/[(\[{]/);
    if (open > 0) {
      id = t.substring(0, open).trim();
      const openCh = t.charAt(open);
      const closeCh = openCh === '(' ? ')' : openCh === '[' ? ']' : '}';
      const close = t.lastIndexOf(closeCh);
      label = close > open ? t.substring(open + 1, close).trim() : t.substring(open + 1).trim();
      shape = openCh === '(' ? (label.startsWith('/') ? 'stadium' : 'round') : openCh === '{' ? 'diamond' : 'rect';
    }
    let node = g.nodeById(id);
    if (node === null) {
      node = new MermaidNode();
      node.id = id;
      g.nodes.push(node);
    }
    if (label !== '') {
      node.label = label;
      node.shape = shape;
    }
    return node;
  }
}

@ComponentV2
export struct MermaidView {
  @Param code: string = '';
  @State fail: boolean = false;

  aboutToAppear(): void {
    if (MermaidParser.parse(this.code) === null) {
      this.fail = true;
    }
  }

  build() {
    if (this.fail) {
      Column() {
        CodeBlock({ code: this.code, lang: 'mermaid' })
      }
      .width('100%')
    } else {
      Column() {
        Canvas(this.context)
          .width('100%')
          .height(this.canvasHeight())
          .onReady(() => {
            this.draw();
          })
      }
      .width('100%')
      .backgroundColor($r('app.color.code_block_bg'))
      .borderRadius(Dim.radiusM)
    }
  }

  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  private graph(): FlowGraph {
    return MermaidParser.parse(this.code) as FlowGraph;
  }

  private canvasHeight(): number {
    const g = this.graph();
    const vertical = g.dir === 'TD' || g.dir === 'TB';
    if (vertical) {
      return Math.max(160, (this.maxDepth(g) + 1) * 110 + 60);
    }
    return (g.nodes.length > 0 ? 2 : 2) * 90 + 40;
  }

  private maxDepth(g: FlowGraph): number {
    // 层次 = 最长路径（简单 BFS 近似，防环）
    const depth: Map<string, number> = new Map();
    for (const n of g.nodes) {
      depth.set(n.id, 0);
    }
    for (let iter = 0; iter < g.nodes.length; iter++) {
      let changed = false;
      for (const e of g.edges) {
        const d = (depth.get(e.from) ?? 0) + 1;
        if (d > (depth.get(e.to) ?? 0)) {
          depth.set(e.to, d);
          changed = true;
        }
      }
      if (!changed) {
        break;
      }
    }
    let max = 0;
    for (const v of depth.values()) {
      if (v > max) {
        max = v;
      }
    }
    return max;
  }

  private draw(): void {
    const ctx = this.context;
    const w = ctx.width;
    const g = this.graph();
    ctx.clearRect(0, 0, w, 10000);
    ctx.fillStyle = '#00000000';
    const textColor = CANVAS_TEXT;
    const lineColor = CANVAS_LINE;
    const brandColor = CANVAS_BRAND;
    const cardColor = CANVAS_CARD;

    ctx.font = '14px sans-serif';
    const vertical = g.dir === 'TD' || g.dir === 'TB';

    // 层次布局
    const depth: Map<string, number> = new Map();
    for (const n of g.nodes) {
      depth.set(n.id, 0);
    }
    for (let iter = 0; iter < g.nodes.length; iter++) {
      let changed = false;
      for (const e of g.edges) {
        const d = (depth.get(e.from) ?? 0) + 1;
        if (d > (depth.get(e.to) ?? 0)) {
          depth.set(e.to, d);
          changed = true;
        }
      }
      if (!changed) {
        break;
      }
    }
    // 分层分组
    const layers: MermaidNode[][] = [];
    for (const n of g.nodes) {
      const d = depth.get(n.id) ?? 0;
      while (layers.length <= d) {
        layers.push([]);
      }
      layers[d].push(n);
    }
    // 节点尺寸与位置
    const pos: Map<string, number[]> = new Map(); // [cx, cy]
    const size: Map<string, number[]> = new Map(); // [w, h]
    for (let d = 0; d < layers.length; d++) {
      const layer = layers[d];
      let totalW = 0;
      const widths: number[] = [];
      for (const n of layer) {
        const tw = ctx.measureText(n.label).width + 36;
        const nw = Math.max(72, Math.min(220, tw));
        widths.push(nw);
        size.set(n.id, [nw, 40]);
        totalW += nw;
      }
      const gap = 24;
      let x = (w - (totalW + gap * (layer.length - 1))) / 2;
      if (x < 8) {
        x = 8;
      }
      const cy = vertical ? 40 + d * 110 : 40;
      for (let i = 0; i < layer.length; i++) {
        const cx = vertical ? x + widths[i] / 2 : 60 + d * 170;
        pos.set(layer[i].id, [cx, cy]);
        if (vertical) {
          x += widths[i] + gap;
        }
      }
    }
    // 画边
    ctx.strokeStyle = lineColor;
    ctx.fillStyle = lineColor;
    ctx.lineWidth = 1.5;
    for (const e of g.edges) {
      const p1 = pos.get(e.from);
      const p2 = pos.get(e.to);
      if (p1 === undefined || p2 === undefined) {
        continue;
      }
      const s1 = size.get(e.from) ?? [72, 40];
      const s2 = size.get(e.to) ?? [72, 40];
      ctx.setLineDash(e.dashed ? [5, 4] : []);
      ctx.beginPath();
      if (vertical) {
        const y1 = p1[1] + s1[1] / 2;
        const y2 = p2[1] - s2[1] / 2;
        ctx.moveTo(p1[0], y1);
        ctx.lineTo(p2[0], y2 - 6);
        ctx.stroke();
        // 箭头
        ctx.beginPath();
        ctx.moveTo(p2[0], y2);
        ctx.lineTo(p2[0] - 4, y2 - 7);
        ctx.lineTo(p2[0] + 4, y2 - 7);
        ctx.closePath();
        ctx.fill();
        if (e.label !== '') {
          ctx.fillStyle = textColor;
          ctx.fillText(e.label, (p1[0] + p2[0]) / 2 - ctx.measureText(e.label).width / 2, (y1 + y2) / 2 - 4);
          ctx.fillStyle = lineColor;
        }
      } else {
        const x1 = p1[0] + s1[0] / 2;
        const x2 = p2[0] - s2[0] / 2;
        ctx.moveTo(x1, p1[1]);
        ctx.lineTo(x2 - 6, p2[1]);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(x2, p2[1]);
        ctx.lineTo(x2 - 7, p2[1] - 4);
        ctx.lineTo(x2 - 7, p2[1] + 4);
        ctx.closePath();
        ctx.fill();
        if (e.label !== '') {
          ctx.fillStyle = textColor;
          ctx.fillText(e.label, (x1 + x2) / 2 - ctx.measureText(e.label).width / 2, p1[1] - 6);
          ctx.fillStyle = lineColor;
        }
      }
    }
    ctx.setLineDash([]);
    // 画节点
    for (const n of g.nodes) {
      const p = pos.get(n.id);
      const s = size.get(n.id);
      if (p === undefined || s === undefined) {
        continue;
      }
      const x = p[0] - s[0] / 2;
      const y = p[1] - s[1] / 2;
      ctx.fillStyle = cardColor;
      ctx.strokeStyle = brandColor;
      ctx.lineWidth = 1.5;
      if (n.shape === 'diamond') {
        ctx.beginPath();
        ctx.moveTo(p[0], y);
        ctx.lineTo(x + s[0], p[1]);
        ctx.lineTo(p[0], y + s[1]);
        ctx.lineTo(x, p[1]);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();
      } else {
        const r = n.shape === 'round' || n.shape === 'stadium' ? s[1] / 2 : 8;
        ctx.beginPath();
        ctx.roundRect(x, y, s[0], s[1], r);
        ctx.fill();
        ctx.stroke();
      }
      ctx.fillStyle = textColor;
      ctx.fillText(n.label, p[0] - ctx.measureText(n.label).width / 2, p[1] + 5);
    }
  }
}
