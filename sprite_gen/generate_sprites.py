#!/usr/bin/env python3
"""
SpriteSoul - Local Sprite Generator
Usage: python generate_sprites.py --character "girl with black hair" --output ./sprites
"""

import argparse
import os
import sys
import threading
import time
from collections import deque
import numpy as np
from PIL import Image

try:
    NEAREST = Image.Resampling.NEAREST
except AttributeError:
    NEAREST = Image.NEAREST

STATUS_FILE = None  # Godot가 읽는 진행 상태 파일 경로


def log(msg):
    """Godot와 터미널 모두에 상태 출력."""
    line = f"STATUS:{msg}"
    print(line, flush=True)
    if STATUS_FILE:
        with open(STATUS_FILE, "w", encoding="utf-8") as f:
            f.write(line)


def detect_device():
    import torch
    if torch.cuda.is_available():
        return "cuda", torch.bfloat16
    elif torch.backends.mps.is_available():
        return "mps", torch.float16
    else:
        return "cpu", torch.float32


def build_prompt(character: str, use_image_ref: bool = False) -> str:
    if use_image_ref:
        base = "Create a pixel art spritesheet of the character in the image."
    else:
        base = f"pixel art spritesheet of {character}."
    return (
        base + " "
        "The spritesheet is a 4 by 4 grid of four rows of frames - "
        "first row is 3 walking frames facing down and 1 frame both arms raised, "
        "second row is 3 walking frames facing left and 1 frame jumping left, "
        "third row is 3 walking frames facing right and 1 frame jumping right, "
        "fourth row is 3 walking frames back view facing up and 1 frame lying on floor. "
        "white background between frames, chibi style, retro RPG game sprite."
    )


def detect_grid_valleys(img, n_rows=4, n_cols=4, pad=5):
    arr = np.array(img.convert("RGB"))
    content = ~((arr[:, :, 0] > 230) & (arr[:, :, 1] > 230) & (arr[:, :, 2] > 230))
    col_den = content.sum(axis=0).astype(float)
    row_den = content.sum(axis=1).astype(float)

    def find_bounds(density, n):
        nz = np.where(density > 2)[0]
        start, end = int(nz[0]), int(nz[-1])
        section_w = (end - start) // n
        bounds = [max(0, start - pad)]
        for i in range(1, n):
            center = start + i * section_w
            lo = max(start, center - section_w // 3)
            hi = min(end, center + section_w // 3)
            bounds.append(lo + int(np.argmin(density[lo:hi])))
        bounds.append(min(len(density), end + pad))
        return bounds

    return find_bounds(col_den, n_cols), find_bounds(row_den, n_rows)


def tight_crop(img):
    arr = np.array(img.convert("RGB"))
    content = ~((arr[:, :, 0] > 230) & (arr[:, :, 1] > 230) & (arr[:, :, 2] > 230))
    rows = np.any(content, axis=1)
    cols = np.any(content, axis=0)
    if not rows.any():
        return img
    y0, y1 = int(np.where(rows)[0][0]), int(np.where(rows)[0][-1])
    x0, x1 = int(np.where(cols)[0][0]), int(np.where(cols)[0][-1])
    return img.crop((x0, y0, x1 + 1, y1 + 1))


def remove_white_bg(img):
    """테두리에서 BFS로 흰 배경(>235)만 투명 처리."""
    rgba = img.convert("RGBA")
    arr = np.array(rgba).copy()
    h, w = arr.shape[:2]
    bg = (arr[:, :, 0] > 235) & (arr[:, :, 1] > 235) & (arr[:, :, 2] > 235)
    visited = np.zeros((h, w), dtype=bool)
    queue = deque()
    for x in range(w):
        if bg[0, x]:   queue.append((0, x))
        if bg[h-1, x]: queue.append((h-1, x))
    for y in range(h):
        if bg[y, 0]:   queue.append((y, 0))
        if bg[y, w-1]: queue.append((y, w-1))
    while queue:
        y, x = queue.popleft()
        if visited[y, x] or not bg[y, x]:
            continue
        visited[y, x] = True
        for dy, dx in ((-1,0),(1,0),(0,-1),(0,1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and bg[ny, nx]:
                queue.append((ny, nx))
    arr[visited, 3] = 0
    return Image.fromarray(arr)


def split_frames(result, out_dir, frame_size=128, margin=8):
    FRAME_NAMES = [
        ["walk_down_1", "walk_down_2", "walk_down_3", "arms_raised"],
        ["walk_left_1", "walk_left_2", "walk_left_3", "jump_left"],
        ["walk_right_1", "walk_right_2", "walk_right_3", "jump_right"],
        ["walk_back_1", "walk_back_2", "walk_back_3", "lying_down"],
    ]
    ANIM_MAP = {
        "idle_1":  "walk_down_1",
        "idle_2":  "arms_raised",
        "walk_1":  "walk_right_1",
        "walk_2":  "walk_right_2",
        "walk_3":  "walk_right_3",
        "sleep_1": "lying_down",
        "sleep_2": "lying_down",
        "react_1": "arms_raised",
        "react_2": "walk_down_1",
    }

    col_bounds, row_bounds = detect_grid_valleys(result)

    # 1패스: 타이트 크롭 + 최대 크기 파악
    tight_frames = {}
    max_w, max_h = 0, 0
    for row_idx, row_names in enumerate(FRAME_NAMES):
        for col_idx, name in enumerate(row_names):
            x1 = col_bounds[col_idx]
            y1 = row_bounds[row_idx]
            x2 = result.width  if col_idx == 3 else col_bounds[col_idx + 1]
            y2 = result.height if row_idx == 3 else row_bounds[row_idx + 1]
            tc = tight_crop(result.crop((x1, y1, x2, y2)))
            tight_frames[name] = tc
            max_w = max(max_w, tc.width)
            max_h = max(max_h, tc.height)

    # 2패스: 동일 캔버스 크기로 정규화 → frame_size 리사이즈 (투명 배경)
    canvas_dim = max(max_w + margin * 2, max_h + margin * 2)
    raw_frames = {}
    for name, tc in tight_frames.items():
        tc_rgba = remove_white_bg(tc)
        canvas = Image.new("RGBA", (canvas_dim, canvas_dim), (0, 0, 0, 0))
        canvas.paste(tc_rgba, ((canvas_dim - tc.width) // 2, (canvas_dim - tc.height) // 2), mask=tc_rgba)
        frame = canvas.resize((frame_size, frame_size), NEAREST)
        raw_frames[name] = frame
        frame.save(os.path.join(out_dir, f"frame_{name}.png"))

    # Godot 애니메이션 파일 저장
    for anim_name, src in ANIM_MAP.items():
        raw_frames[src].copy().save(os.path.join(out_dir, f"{anim_name}.png"))

    return raw_frames


def _patch_tqdm_for_download():
    """huggingface_hub 다운로드 진행률을 STATUS로 출력하도록 tqdm 패치."""
    import tqdm.auto as _ta
    _orig = _ta.tqdm

    class _DownloadTqdm(_orig):
        def update(self, n=1):
            super().update(n)
            if self.total and self.total > 1_000_000 and self.n is not None:
                pct = int(100 * min(self.n, self.total) / self.total)
                dl  = self.n / 1_048_576
                tot = self.total / 1_048_576
                if tot >= 1000:
                    size_str = f"{dl/1024:.2f}GB / {tot/1024:.2f}GB"
                else:
                    size_str = f"{dl:.0f}MB / {tot:.0f}MB"
                log(f"DOWNLOAD:{pct}:{size_str}")

    _ta.tqdm = _DownloadTqdm


def _load_progress_thread(stop_event, estimated_secs=90):
    """캐시에서 메모리 로드 시 경과/예상 시간을 LOAD: 형식으로 출력."""
    start = time.time()
    while not stop_event.is_set():
        elapsed = time.time() - start
        pct = min(94, int(95 * elapsed / estimated_secs))
        remaining = max(0, int(estimated_secs - elapsed))
        mins_r, secs_r = divmod(remaining, 60)
        if remaining > 5:
            eta = f"예상 {mins_r}분 {secs_r:02d}초 남음" if mins_r else f"예상 {secs_r}초 남음"
        else:
            eta = "거의 완료..."
        log(f"LOAD:{pct}:{eta}")
        time.sleep(2)


def generate(args):
    global STATUS_FILE
    STATUS_FILE = args.status_file

    import torch

    device, dtype = detect_device()
    log(f"디바이스: {device.upper()}")

    use_image_ref = bool(args.reference_image)
    steps = args.steps if args.steps else (64 if device != "cpu" else 20)
    if device == "cpu":
        log(f"CPU 모드: {steps}스텝 (시간이 오래 걸릴 수 있어요)")

    from huggingface_hub import try_to_load_from_cache
    cached = try_to_load_from_cache("black-forest-labs/FLUX.2-klein-4B", "model_index.json")
    is_download = cached is None

    if is_download:
        _patch_tqdm_for_download()
        log("DOWNLOAD:0:다운로드 준비 중...")
    else:
        log("LOAD:0:모델 메모리 로드 중...")

    stop_event = threading.Event()
    if not is_download:
        t = threading.Thread(target=_load_progress_thread, args=(stop_event,), daemon=True)
        t.start()
    else:
        t = None

    hf_token = args.hf_token or os.environ.get("HF_TOKEN", "")
    if hf_token:
        from huggingface_hub import login
        login(token=hf_token, add_to_git_credential=False)

    from diffusers import DiffusionPipeline
    pipe = DiffusionPipeline.from_pretrained(
        "black-forest-labs/FLUX.2-klein-4B",
        torch_dtype=dtype,
    )

    pipe.load_lora_weights(
        "svntax-dev/pixel_spritesheet_4walk_small_lora_v1",
        weight_name="pixel_4walk_small_flux2_klein_base_4b_v1.safetensors",
    )
    pipe = pipe.to(device)
    stop_event.set()
    if t:
        t.join(timeout=1)
    log("모델 로드 완료")

    prompt = build_prompt(args.character, use_image_ref)
    generator = torch.Generator(device).manual_seed(args.seed)

    def on_step_end(pipe, step, timestep, callback_kwargs):
        log(f"STEP:{step + 1}:{steps}")
        return callback_kwargs

    log(f"스프라이트 생성 시작 ({steps}스텝)")

    ref_img = None
    if use_image_ref:
        ref_img = Image.open(args.reference_image).convert("RGB")

    result = pipe(
        prompt=prompt,
        image=ref_img,
        num_inference_steps=steps,
        guidance_scale=0.5,
        height=512,
        width=512,
        generator=generator,
        callback_on_step_end=on_step_end,
        callback_on_step_end_tensor_inputs=["latents"],
    ).images[0]
    log("이미지 생성 완료, 프레임 분리 중...")

    os.makedirs(args.output, exist_ok=True)
    result.save(os.path.join(args.output, "spritesheet_raw.png"))

    split_frames(result, args.output)
    log("완료")

    # Godot가 감지하는 완료 신호
    print("DONE", flush=True)
    if STATUS_FILE:
        with open(STATUS_FILE, "w", encoding="utf-8") as f:
            f.write("DONE")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SpriteSoul Sprite Generator")
    parser.add_argument("--character", required=True, help="캐릭터 설명 (영문)")
    parser.add_argument("--output",    default="./sprites", help="출력 디렉토리")
    parser.add_argument("--seed",      type=int, default=42)
    parser.add_argument("--steps",     type=int, default=None, help="추론 스텝 (기본: GPU=64, CPU=20)")
    parser.add_argument("--hf-token",       default="", help="HuggingFace 토큰 (또는 HF_TOKEN 환경변수)")
    parser.add_argument("--status-file",    default="", help="Godot용 진행 상태 파일 경로")
    parser.add_argument("--reference-image", default="", help="캐릭터 참고 이미지 경로 (img2img 모드)")
    args = parser.parse_args()
    generate(args)
