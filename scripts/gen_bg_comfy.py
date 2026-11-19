# -*- coding: utf-8 -*-
"""
gen_bg_comfy.py — 用本机 ComfyUI（qwen-image-2.1）生成图标渐变底图候选。
AI 只画背景（无文字/图形）；HD 字样由 gen_icon.py 的矢量白稿合成，保证小尺寸清晰。

用法：python scripts/gen_bg_comfy.py
产物：scripts/_bg/bg_<名>.png（1024x1024）
"""
import json
import os
import sys
import time
import urllib.request
import uuid

URL = 'http://127.0.0.1:8188'
# 本机回环地址不走系统代理（Git Bash/系统代理会劫持 127.0.0.1）
urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({})))
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '_bg')
UNET = 'qwen-image-2.1-Q8_0.gguf'
CLIP = 'qwen3vl_8b_int8_convrot.safetensors'
CLIP_TYPE = 'qwen_image'
VAE = 'qwen_image_2.1_vae_bf16.safetensors'

# 候选底图提词：只描述背景，明令无文字无图形
CANDIDATES = [
    ('A', 7, '极简高级的应用图标背景：深蓝到靛蓝的丝滑对角渐变，左上方一团柔和的淡蓝色光晕，'
             '底部略微加深，画面纯净，无任何文字与图形，细腻如丝绸的微光质感，高清'),
    ('B', 21, '深蓝紫色抽象渐变背景，右上角一条柔和的极光光带缓缓流动，整体干净通透，'
              '无文字无物体，高级感，应用图标背景，柔和漫射光'),
    ('C', 42, '纯净的宝蓝色渐变背景，中央偏左上有柔和光斑，四周渐渐沉入深蓝，'
              '极简主义，顺滑如丝绸，无文字，无图形'),
]
NEGATIVE = '文字, 字母, 汉字, 标志, 图标, 物体, 人物, 复杂图案, 噪点, 边框'
STEPS, CFG = 25, 1.0


def http(method, path, body=None, timeout=30):
    req = urllib.request.Request(URL + path, method=method)
    data = None
    if body is not None:
        data = json.dumps(body).encode('utf-8')
        req.add_header('Content-Type', 'application/json')
    with urllib.request.urlopen(req, data=data, timeout=timeout) as r:
        return r.read()


def wait_ready(timeout=180):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            stats = json.loads(http('GET', '/system_stats', timeout=5))
            print('ComfyUI ready:', stats.get('system', {}).get('comfyui_version'))
            return
        except Exception:
            time.sleep(2)
    raise SystemExit('ComfyUI 180s 内未就绪')


def build_graph(prompt, negative, seed, prefix):
    return {
        '1': {'class_type': 'UnetLoaderGGUF', 'inputs': {'unet_name': UNET}},
        '2': {'class_type': 'CLIPLoader', 'inputs': {'clip_name': CLIP, 'type': CLIP_TYPE}},
        '3': {'class_type': 'VAELoader', 'inputs': {'vae_name': VAE}},
        '4': {'class_type': 'CLIPTextEncode', 'inputs': {'clip': ['2', 0], 'text': prompt}},
        '4n': {'class_type': 'CLIPTextEncode', 'inputs': {'clip': ['2', 0], 'text': negative}},
        '5': {'class_type': 'EmptyLatentImage',
              'inputs': {'width': 1024, 'height': 1024, 'batch_size': 1}},
        '6': {'class_type': 'KSampler',
              'inputs': {'model': ['1', 0], 'positive': ['4', 0], 'negative': ['4n', 0],
                         'latent_image': ['5', 0], 'seed': seed, 'steps': STEPS, 'cfg': CFG,
                         'sampler_name': 'euler', 'scheduler': 'simple', 'denoise': 1.0}},
        '7': {'class_type': 'VAEDecode', 'inputs': {'samples': ['6', 0], 'vae': ['3', 0]}},
        '8': {'class_type': 'SaveImage',
              'inputs': {'images': ['7', 0], 'filename_prefix': 'icon_bg/' + prefix}},
    }


def submit_and_wait(graph, label, timeout=600):
    pid = json.loads(http('POST', '/prompt',
                          body={'prompt': graph, 'client_id': uuid.uuid4().hex}))['prompt_id']
    print(f'[{label}] submitted {pid}')
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(3)
        hist = json.loads(http('GET', f'/history/{pid}', timeout=15))
        entry = hist.get(pid)
        if not entry:
            continue
        if entry.get('status', {}).get('status_str') == 'error':
            raise SystemExit(f'[{label}] 生成失败: {json.dumps(entry.get("status"))[:400]}')
        outs = entry.get('outputs', {})
        for node_out in outs.values():
            for img in node_out.get('images', []):
                data = http('GET', f"/view?filename={img['filename']}&"
                                   f"subfolder={img['subfolder']}&type={img['type']}", timeout=60)
                path = os.path.join(OUT, f'bg_{label}.png')
                with open(path, 'wb') as f:
                    f.write(data)
                print(f'[{label}] saved -> {path}')
                return path
    raise SystemExit(f'[{label}] 等待超时')


def main():
    os.makedirs(OUT, exist_ok=True)
    wait_ready()
    for label, seed, prompt in CANDIDATES:
        graph = build_graph(prompt, NEGATIVE, seed, label)
        submit_and_wait(graph, label)


if __name__ == '__main__':
    sys.exit(main())
