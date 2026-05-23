#!/usr/bin/env python3
"""
SpriteSoul - Local Sprite Generator
Usage: python generate_sprites.py --reference-image ./char.png --output ./sprites
"""

import argparse
import os
import threading
import time
from collections import deque
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

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
    import os
    if torch.cuda.is_available():
        return "cuda", torch.bfloat16
    elif torch.backends.mps.is_available():
        os.environ.setdefault("PYTORCH_MPS_HIGH_WATERMARK_RATIO", "0.0")
        return "mps", torch.float16
    else:
        return "cpu", torch.float32


def build_prompt() -> str:
    return (
        "A pixel art spritesheet of a character. "
        "The spritesheet is a 4 by 4 grid of four rows of frames - "
        "first row is 3 walking frames facing down and 1 frame both arms raised, "
        "second row is 3 walking frames facing left and 1 frame jumping left, "
        "third row is 3 walking frames facing right and 1 frame jumping right, "
        "fourth row is 3 walking frames back view facing up and 1 frame lying on floor."
    )


def k_centroid_downscale(img, factor=4):
    """각 NxN 블록에서 평균색에 가장 가까운 실제 픽셀 선택 (pixel art 특화 다운스케일)."""
    arr = np.array(img.convert("RGB")).astype(float)
    h, w = arr.shape[:2]
    nh, nw = h // factor, w // factor
    blocks = arr[:nh*factor, :nw*factor].reshape(nh, factor, nw, factor, 3)
    means = blocks.mean(axis=(1, 3))
    flat = blocks.transpose(0, 2, 1, 3, 4).reshape(nh, nw, factor * factor, 3)
    dists = ((flat - means[:, :, np.newaxis, :]) ** 2).sum(axis=3)
    idx = dists.argmin(axis=2)
    out = flat[np.arange(nh)[:, None], np.arange(nw)[None, :], idx]
    return Image.fromarray(out.astype(np.uint8), "RGB")


def _is_bg(arr_rgb):
    r = arr_rgb[:,:,0].astype(int)
    g = arr_rgb[:,:,1].astype(int)
    b = arr_rgb[:,:,2].astype(int)
    return ((r > 240) & (g > 240) & (b > 240) &
            (np.abs(r-g) < 15) & (np.abs(g-b) < 15))


def remove_white_bg(img):
    """테두리에서 BFS로 흰색/회색 배경을 투명 처리."""
    from collections import deque
    rgba = img.convert("RGBA")
    arr = np.array(rgba).copy()
    h, w = arr.shape[:2]
    bg = _is_bg(arr[:,:,:3])
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
            ny, nx = y+dy, x+dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and bg[ny, nx]:
                queue.append((ny, nx))
    arr[visited, 3] = 0
    return Image.fromarray(arr)


def _detect_col_count(img):
    """가로 밀도 피크 수로 2열 vs 4열 판별."""
    from scipy.signal import find_peaks
    arr = np.array(img.convert("RGB"))
    content = ~((arr[:,:,0]>230)&(arr[:,:,1]>230)&(arr[:,:,2]>230))
    col_den = content.sum(axis=0).astype(float)
    smoothed = np.convolve(col_den, np.ones(16)/16, mode="same")
    max_v = smoothed.max()
    if max_v == 0:
        return 4
    w = len(smoothed)
    peaks, _ = find_peaks(smoothed, height=max_v * 0.3, distance=w // 6)
    return 4 if len(peaks) >= 3 else 2


def _filter_largest_component(rgba_img):
    """가장 큰 연결 컴포넌트만 남기고 아티팩트 제거."""
    arr = np.array(rgba_img)
    alpha = arr[:,:,3] > 10
    if not alpha.any():
        return rgba_img
    labeled, n = ndi.label(alpha)
    if n <= 1:
        return rgba_img
    sizes = ndi.sum(alpha, labeled, range(1, n+1))
    main = int(np.argmax(sizes)) + 1
    out = arr.copy()
    out[labeled != main, 3] = 0
    return Image.fromarray(out, "RGBA")


def _split_2x2(result, out_dir, frame_size=128, margin=8):
    """2×2 layout: 4 large poses (front / arms / back / lying)."""
    w, h = result.size
    hw, hh = w // 2, h // 2

    raw = {
        "front": result.crop((0,  0,  hw, hh)),
        "arms":  result.crop((hw, 0,  w,  hh)),
        "back":  result.crop((0,  hh, hw, h)),
        "lying": result.crop((hw, hh, w,  h)),
    }

    frames = {}
    for name, cell in raw.items():
        rgba = _filter_largest_component(remove_white_bg(cell))
        arr = np.array(rgba)
        a = arr[:,:,3] > 10
        if not a.any():
            frames[name] = Image.new("RGBA", (frame_size, frame_size), (0,0,0,0))
            continue
        ys, xs = np.where(a)
        crop = rgba.crop((int(xs.min()), int(ys.min()), int(xs.max())+1, int(ys.max())+1))
        cw, ch = crop.size
        if name == "lying":
            scale = (frame_size - margin*2) / max(cw, 1)
            nw, nh = frame_size - margin*2, max(1, int(ch*scale))
        else:
            target_h = int(frame_size * 0.82)
            scale = min(target_h / max(ch, 1), (frame_size-margin*2) / max(cw, 1))
            nw, nh = max(1, int(cw*scale)), max(1, int(ch*scale))
        scaled = crop.resize((nw, nh), NEAREST)
        canvas = Image.new("RGBA", (frame_size, frame_size), (0,0,0,0))
        canvas.paste(scaled, ((frame_size-nw)//2, max(0, frame_size-nh-margin)), mask=scaled)
        frames[name] = canvas
        canvas.save(os.path.join(out_dir, f"frame_{name}.png"))

    ANIM_MAP = {
        "idle_1":   ("front", False),
        "idle_2":   ("front", False),
        "idle_3":   ("front", False),
        "walk_l_1": ("front", False),
        "walk_l_2": ("front", False),
        "walk_l_3": ("front", False),
        "walk_r_1": ("front", True),
        "walk_r_2": ("front", True),
        "walk_r_3": ("front", True),
        "sleep_1":  ("lying", False),
        "react_1":  ("arms",  False),
        "react_2":  ("front", False),
    }
    for anim_name, (src, flip) in ANIM_MAP.items():
        frame = frames[src].copy()
        if flip:
            frame = frame.transpose(Image.FLIP_LEFT_RIGHT)
        frame.save(os.path.join(out_dir, f"{anim_name}.png"))
    return frames


def split_frames(result, out_dir, frame_size=128, margin=8):
    """스프라이트시트를 프레임으로 분할.

    핵심 설계:
    - 고정 그리드 분할 (밸리 감지 없음 → 생성마다 일관)
    - 행 단위 공통 bounding box → 순간이동 방지
    - idle 행 기준 단일 스케일 → 크기 일관
    - walk_left 행 직접 + mirror → 방향 보장
    """
    w, h = result.size
    col_count = _detect_col_count(result)

    # 2×2 감지: 이미지를 4등분했을 때 실질 행이 2개 이하면 large-pose 레이아웃
    arr = np.array(result.convert("RGB"))
    content_rows = ~((arr[:,:,0]>230)&(arr[:,:,1]>230)&(arr[:,:,2]>230))
    h4 = h // 4
    row_has = [bool(content_rows[i*h4:(i+1)*h4].any()) for i in range(4)]
    if sum(row_has) < 3:
        return _split_2x2(result, out_dir, frame_size, margin)

    if col_count == 4:
        FRAME_NAMES = [
            ["walk_down_1", "walk_down_2", "walk_down_3", "arms_raised"],
            ["walk_left_1", "walk_left_2", "walk_left_3", "jump_left"],
            ["walk_right_1","walk_right_2","walk_right_3","jump_right"],
            ["walk_back_1", "walk_back_2", "walk_back_3", "lying_down"],
        ]
    else:  # 4×2
        FRAME_NAMES = [
            ["walk_down_1", "arms_raised"],
            ["walk_left_1", "jump_left"],
            ["walk_right_1","jump_right"],
            ["walk_back_1", "lying_down"],
        ]

    cell_w = w // col_count
    cell_h = h // 4

    # 1패스: 고정 그리드 분할 + 배경 제거
    cells = {}
    for ri, row_names in enumerate(FRAME_NAMES):
        for ci, name in enumerate(row_names):
            cell = result.crop((ci*cell_w, ri*cell_h, (ci+1)*cell_w, (ri+1)*cell_h))
            cells[name] = _filter_largest_component(remove_white_bg(cell))

    # 2패스: 행 단위 공통 character bbox (순간이동 방지)
    def char_bbox(img):
        a = np.array(img)[:,:,3] > 10
        if not a.any():
            return None
        ys, xs = np.where(a)
        return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())

    row_bbox = {}
    for ri, row_names in enumerate(FRAME_NAMES):
        bbs = [b for b in (char_bbox(cells[n]) for n in row_names) if b is not None]
        if not bbs:
            row_bbox[ri] = (0, 0, cell_w-1, cell_h-1)
        else:
            row_bbox[ri] = (
                min(b[0] for b in bbs), min(b[1] for b in bbs),
                max(b[2] for b in bbs), max(b[3] for b in bbs),
            )

    # 3패스: idle 행(row 0) 기준 전역 스케일 계산
    ib = row_bbox[0]
    idle_char_h = ib[3] - ib[1]
    target_h = int(frame_size * 0.82)
    global_scale = target_h / max(idle_char_h, 1)

    LYING = {"lying_down"}

    # 4패스: 행 공통 bbox로 크롭 → 스케일 → 캔버스 배치
    frames = {}
    for ri, row_names in enumerate(FRAME_NAMES):
        bx0, by0, bx1, by1 = row_bbox[ri]
        pad = 2
        cx0 = max(0, bx0-pad);     cy0 = max(0, by0-pad)
        cx1 = min(cell_w, bx1+pad+1); cy1 = min(cell_h, by1+pad+1)

        for name in row_names:
            crop = cells[name].crop((cx0, cy0, cx1, cy1))
            cw, ch = crop.size
            if cw < 1 or ch < 1:
                frames[name] = Image.new("RGBA", (frame_size, frame_size), (0,0,0,0))
                continue

            if name in LYING:
                scale = (frame_size - margin*2) / max(cw, 1)
                nw, nh = frame_size - margin*2, max(1, int(ch*scale))
            else:
                scale = min(global_scale, (frame_size-margin*2) / max(cw, 1))
                nw, nh = max(1, int(cw*scale)), max(1, int(ch*scale))

            scaled = crop.resize((nw, nh), NEAREST)
            canvas = Image.new("RGBA", (frame_size, frame_size), (0,0,0,0))
            canvas.paste(scaled, ((frame_size-nw)//2, max(0, frame_size-nh-margin)), mask=scaled)
            frames[name] = canvas
            canvas.save(os.path.join(out_dir, f"frame_{name}.png"))

    # 5패스: ANIM_MAP — walk_left/walk_right 행을 각 방향에 직접 사용
    def has_content(name):
        f = frames.get(name)
        return f is not None and np.array(f)[:,:,3].max() > 10

    if col_count == 4:
        wl2 = "walk_left_2" if has_content("walk_left_2") else "walk_left_1"
        wl3 = "walk_left_3" if has_content("walk_left_3") else "walk_left_1"
        wr2 = "walk_right_2" if has_content("walk_right_2") else "walk_right_1"
        wr3 = "walk_right_3" if has_content("walk_right_3") else "walk_right_1"
        ANIM_MAP = {
            "idle_1":   ("walk_down_1",  False),
            "idle_2":   ("walk_down_2",  False),
            "idle_3":   ("walk_down_3",  False),
            "walk_l_1": ("walk_left_1",  False),
            "walk_l_2": (wl2,            False),
            "walk_l_3": (wl3,            False),
            "walk_r_1": ("walk_right_1", False),
            "walk_r_2": (wr2,            False),
            "walk_r_3": (wr3,            False),
            "sleep_1":  ("lying_down",   False),
            "react_1":  ("arms_raised",  False),
            "react_2":  ("jump_left",    True),
        }
    else:  # 4×2: walk 프레임 1개
        ANIM_MAP = {
            "idle_1":   ("walk_down_1", False),
            "idle_2":   ("walk_down_1", False),
            "idle_3":   ("walk_down_1", False),
            "walk_l_1": ("walk_left_1", False),
            "walk_l_2": ("walk_left_1", False),
            "walk_l_3": ("walk_left_1", False),
            "walk_r_1": ("walk_left_1", True),
            "walk_r_2": ("walk_left_1", True),
            "walk_r_3": ("walk_left_1", True),
            "sleep_1":  ("lying_down",  False),
            "react_1":  ("arms_raised", False),
            "react_2":  ("walk_down_1", False),
        }

    for anim_name, (src, flip) in ANIM_MAP.items():
        frame = frames[src].copy()
        if flip:
            frame = frame.transpose(Image.FLIP_LEFT_RIGHT)
        frame.save(os.path.join(out_dir, f"{anim_name}.png"))

    return frames


def _patch_tqdm_for_download():
    """huggingface_hub 다운로드 진행률을 STATUS로 출력하도록 tqdm 패치."""
    import tqdm.auto as _ta
    _orig = _ta.tqdm

    class _DownloadTqdm(_orig):
        def update(self, n=1):
            super().update(n)
            if self.total and self.n is not None:
                pct = int(100 * min(self.n, self.total) / self.total)
                dl  = self.n / 1_048_576
                tot = self.total / 1_048_576
                if tot >= 1000:
                    size_str = f"{dl/1024:.2f}GB / {tot/1024:.2f}GB"
                else:
                    size_str = f"{dl:.0f}MB / {tot:.0f}MB"
                log(f"DOWNLOAD:{pct}:{size_str}")

    _ta.tqdm = _DownloadTqdm


def _disk_download_progress_thread(stop_event, model_id, expected_gb=13.0):
    """tqdm이 안 잡힐 때 캐시 폴더 크기로 직접 진행률 계산."""
    cache_dir = os.path.join(os.path.expanduser("~"), ".cache", "huggingface", "hub")
    model_dir = os.path.join(cache_dir, "models--" + model_id.replace("/", "--"))
    expected = expected_gb * 1024 ** 3
    while not stop_event.is_set():
        time.sleep(3)
        if not os.path.exists(model_dir):
            continue
        total = sum(
            os.path.getsize(os.path.join(dp, f))
            for dp, _, files in os.walk(model_dir)
            for f in files
        )
        pct = min(99, int(100 * total / expected))
        dl = total / 1024 ** 3
        log(f"DOWNLOAD:{pct}:{dl:.1f}GB / {expected_gb:.0f}GB")


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

    steps = args.steps if args.steps else (15 if device != "cpu" else 8)
    if device == "cpu":
        log(f"CPU 모드: {steps}스텝 (시간이 오래 걸릴 수 있어요)")

    from huggingface_hub import try_to_load_from_cache
    cached = try_to_load_from_cache("black-forest-labs/FLUX.2-klein-base-4B", "model_index.json")
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
        t = threading.Thread(
            target=_disk_download_progress_thread,
            args=(stop_event, "black-forest-labs/FLUX.2-klein-base-4B", 13.0),
            daemon=True,
        )
        t.start()

    hf_token = args.hf_token or os.environ.get("HF_TOKEN", "")
    if hf_token:
        from huggingface_hub import login
        login(token=hf_token, add_to_git_credential=False)

    from diffusers import DiffusionPipeline
    pipe = DiffusionPipeline.from_pretrained(
        "black-forest-labs/FLUX.2-klein-base-4B",
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

    prompt = build_prompt()
    generator = torch.Generator(device).manual_seed(args.seed)

    def on_step_end(pipe, step, timestep, callback_kwargs):
        log(f"STEP:{step + 1}:{steps}")
        return callback_kwargs

    log(f"스프라이트 생성 시작 ({steps}스텝)")

    ref_img = None
    if args.reference_image:
        ref_img = Image.open(args.reference_image).convert("RGB").resize((512, 512), Image.LANCZOS)

    result = pipe(
        prompt=prompt,
        image=ref_img,
        num_inference_steps=steps,
        guidance_scale=5.0,
        height=512,
        width=512,
        generator=generator,
        callback_on_step_end=on_step_end,
        callback_on_step_end_tensor_inputs=["latents"],
    ).images[0]
    log("이미지 생성 완료, 프레임 분리 중...")

    os.makedirs(args.output, exist_ok=True)
    result.save(os.path.join(args.output, "spritesheet_raw.png"))

    kc = k_centroid_downscale(result, factor=4)           # 512→128
    result_px = kc.resize(result.size, NEAREST)           # 128→512 (pixel art 느낌)
    result_px.save(os.path.join(args.output, "spritesheet_processed.png"))

    split_frames(result_px, args.output)
    log("완료")

    # Godot가 감지하는 완료 신호
    print("DONE", flush=True)
    if STATUS_FILE:
        with open(STATUS_FILE, "w", encoding="utf-8") as f:
            f.write("DONE")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SpriteSoul Sprite Generator")

    parser.add_argument("--output",    default="./sprites", help="출력 디렉토리")
    parser.add_argument("--seed",      type=int, default=42)
    parser.add_argument("--steps",     type=int, default=None, help="추론 스텝 (기본: GPU=64, CPU=20)")
    parser.add_argument("--hf-token",       default="", help="HuggingFace 토큰 (또는 HF_TOKEN 환경변수)")
    parser.add_argument("--status-file",    default="", help="Godot용 진행 상태 파일 경로")
    parser.add_argument("--reference-image", default="", help="캐릭터 참고 이미지 경로 (img2img 모드)")
    args = parser.parse_args()
    generate(args)
