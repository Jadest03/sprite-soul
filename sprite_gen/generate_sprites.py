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
        "Create a pixel art spritesheet of the character in the image. "
        "The spritesheet is a 4 by 4 grid of four rows of frames - "
        "first row is 3 walking frames facing down and 1 frame both arms raised, "
        "second row is 3 walking frames facing left and 1 frame jumping left, "
        "third row is 3 walking frames facing right and 1 frame jumping right, "
        "fourth row is 3 walking frames back view facing up and 1 frame lying on floor."
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
    # BFS로 테두리 연결된 흰색(>220) 픽셀 제거
    bg = (arr[:, :, 0] > 220) & (arr[:, :, 1] > 220) & (arr[:, :, 2] > 220)
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


def _detect_col_count(img):
    """가로 밀도 클러스터로 2열 vs 4열 판별."""
    arr = np.array(img.convert("RGB"))
    content = ~((arr[:, :, 0] > 230) & (arr[:, :, 1] > 230) & (arr[:, :, 2] > 230))
    col_den = content.sum(axis=0).astype(float)
    kernel = 8
    smoothed = np.convolve(col_den, np.ones(kernel) / kernel, mode="same")
    if smoothed.max() == 0:
        return 4
    threshold = smoothed.max() * 0.08
    in_cluster = smoothed[0] > threshold
    clusters = 1 if in_cluster else 0
    for v in smoothed[1:]:
        if v > threshold and not in_cluster:
            clusters += 1
            in_cluster = True
        elif v <= threshold:
            in_cluster = False
    return 2 if clusters <= 2 else 4


def _split_frames_4x2(result, out_dir, frame_size, margin, row_bounds):
    """4×2 layout: 4행 × 2열 = 8프레임."""
    FRAME_NAMES_4x2 = [
        ["walk_down_1", "arms_raised"],
        ["walk_left_1", "jump_left"],
        ["walk_right_1", "jump_right"],
        ["walk_back_1", "lying_down"],
    ]

    def _row_col_bounds_2(row_y1, row_y2, pad=5):
        strip = result.crop((0, row_y1, result.width, row_y2))
        arr2 = np.array(strip.convert("RGB"))
        den = (~((arr2[:, :, 0] > 230) & (arr2[:, :, 1] > 230) & (arr2[:, :, 2] > 230))).sum(axis=0).astype(float)
        nz = np.where(den > 2)[0]
        if len(nz) == 0:
            mid = result.width // 2
            return [0, mid, result.width]
        start, end = int(nz[0]), int(nz[-1])
        qr = (end - start) // 4
        c = (start + end) // 2
        lo, hi = max(start, c - qr), min(end, c + qr)
        valley = lo + int(np.argmin(den[lo:hi]))
        return [max(0, start - pad), valley, min(result.width, end + pad)]

    def _process(crop_img, is_lying=False):
        arr2 = np.array(crop_img.convert("RGB"))
        cont = ~((arr2[:, :, 0] > 230) & (arr2[:, :, 1] > 230) & (arr2[:, :, 2] > 230))
        row_a, col_a = np.any(cont, axis=1), np.any(cont, axis=0)
        if not row_a.any():
            return Image.new("RGBA", (frame_size, frame_size), (0, 0, 0, 0))
        ry0, ry1 = int(np.where(row_a)[0][0]), int(np.where(row_a)[0][-1])
        cx0, cx1 = int(np.where(col_a)[0][0]), int(np.where(col_a)[0][-1])
        tc = crop_img.crop((cx0, ry0, cx1 + 1, ry1 + 1))
        rgba = remove_white_bg(tc)
        alpha = np.array(rgba)[:, :, 3] > 10
        labeled, n = ndi.label(alpha)
        if n > 1:
            sizes = ndi.sum(alpha, labeled, range(1, n + 1))
            main = int(np.argmax(sizes)) + 1
            arr3 = np.array(rgba).copy()
            arr3[labeled != main, 3] = 0
            rgba = Image.fromarray(arr3, "RGBA")
        w, h = rgba.size
        target_h = int(frame_size * 0.82)
        if not is_lying and h > 10:
            scale = min(target_h / h, (frame_size - margin) / max(w, 1))
        else:
            scale = (frame_size - margin * 2) / max(w, 1)
        new_w, new_h = max(1, int(w * scale)), max(1, int(h * scale))
        scaled = rgba.resize((new_w, new_h), NEAREST)
        canvas = Image.new("RGBA", (frame_size, frame_size), (0, 0, 0, 0))
        px = (frame_size - new_w) // 2
        py = max(0, frame_size - new_h - margin)
        canvas.paste(scaled, (px, py), mask=scaled)
        return canvas

    frames = {}
    for row_idx, row_names in enumerate(FRAME_NAMES_4x2):
        y1 = row_bounds[row_idx]
        y2 = result.height if row_idx == 3 else row_bounds[row_idx + 1]
        cb = _row_col_bounds_2(y1, y2)
        for col_idx, name in enumerate(row_names):
            x1 = cb[col_idx]
            x2 = result.width if col_idx == 1 else cb[col_idx + 1]
            cell = result.crop((x1, y1, x2, y2))
            frame = _process(cell, is_lying=(name == "lying_down"))
            frames[name] = frame
            frame.save(os.path.join(out_dir, f"frame_{name}.png"))

    ANIM_MAP = {
        "idle_1":  "walk_down_1",
        "walk_1":  "walk_left_1",
        "walk_2":  "jump_left",
        "walk_3":  "walk_left_1",
        "sleep_1": "lying_down",
        "react_1": "arms_raised",
        "react_2": "walk_down_1",
    }
    WALK_ANIM = {"walk_1", "walk_2", "walk_3"}
    for anim_name, src in ANIM_MAP.items():
        frame = frames[src].copy()
        if anim_name in WALK_ANIM:
            frame = frame.transpose(Image.FLIP_LEFT_RIGHT)
        frame.save(os.path.join(out_dir, f"{anim_name}.png"))

    return frames


def _split_frames_2x2(result, out_dir, frame_size=128, margin=8):
    """2×2 layout (4 large poses): front, arms-raised, back, lying-down."""
    arr = np.array(result.convert("RGB"))
    content = ~((arr[:, :, 0] > 230) & (arr[:, :, 1] > 230) & (arr[:, :, 2] > 230))
    col_den = content.sum(axis=0).astype(float)
    row_den = content.sum(axis=1).astype(float)

    nz_x = np.where(col_den > 2)[0]
    nz_y = np.where(row_den > 2)[0]
    x0, x1 = int(nz_x[0]), int(nz_x[-1])
    y0, y1 = int(nz_y[0]), int(nz_y[-1])

    # Find deepest valley in the middle 50% of each axis
    xm, xr = (x0 + x1) // 2, (x1 - x0) // 4
    x_valley = xm - xr + int(np.argmin(col_den[xm - xr: xm + xr]))
    ym, yr = (y0 + y1) // 2, (y1 - y0) // 4
    y_valley = ym - yr + int(np.argmin(row_den[ym - yr: ym + yr]))

    raw_crops = {
        "front": result.crop((x0,       y0,       x_valley, y_valley)),
        "arms":  result.crop((x_valley, y0,       x1,       y_valley)),
        "back":  result.crop((x0,       y_valley, x_valley, y1)),
        "lying": result.crop((x_valley, y_valley, x1,       y1)),
    }

    def _process(crop_img, is_lying=False):
        arr2 = np.array(crop_img.convert("RGB"))
        cont = ~((arr2[:, :, 0] > 230) & (arr2[:, :, 1] > 230) & (arr2[:, :, 2] > 230))
        row_a, col_a = np.any(cont, axis=1), np.any(cont, axis=0)
        if not row_a.any():
            return Image.new("RGBA", (frame_size, frame_size), (0, 0, 0, 0))
        ry0, ry1 = int(np.where(row_a)[0][0]), int(np.where(row_a)[0][-1])
        cx0, cx1 = int(np.where(col_a)[0][0]), int(np.where(col_a)[0][-1])
        tc = crop_img.crop((cx0, ry0, cx1 + 1, ry1 + 1))

        rgba = remove_white_bg(tc)
        alpha = np.array(rgba)[:, :, 3] > 10
        labeled, n = ndi.label(alpha)
        if n > 1:
            sizes = ndi.sum(alpha, labeled, range(1, n + 1))
            main = int(np.argmax(sizes)) + 1
            arr3 = np.array(rgba).copy()
            arr3[labeled != main, 3] = 0
            rgba = Image.fromarray(arr3, "RGBA")

        w, h = rgba.size
        target_h = int(frame_size * 0.82)
        if not is_lying and h > 10:
            scale = min(target_h / h, (frame_size - margin) / max(w, 1))
        else:
            scale = (frame_size - margin * 2) / max(w, 1)
        new_w = max(1, int(w * scale))
        new_h = max(1, int(h * scale))
        scaled = rgba.resize((new_w, new_h), NEAREST)
        canvas = Image.new("RGBA", (frame_size, frame_size), (0, 0, 0, 0))
        px = (frame_size - new_w) // 2
        py = max(0, frame_size - new_h - margin)
        canvas.paste(scaled, (px, py), mask=scaled)
        return canvas

    processed = {
        "front": _process(raw_crops["front"]),
        "arms":  _process(raw_crops["arms"]),
        "back":  _process(raw_crops["back"]),
        "lying": _process(raw_crops["lying"], is_lying=True),
    }

    for name, img in processed.items():
        img.save(os.path.join(out_dir, f"frame_{name}.png"))

    ANIM_MAP = {
        "idle_1":  "front",
        "walk_1":  "front",
        "walk_2":  "front",
        "walk_3":  "front",
        "sleep_1": "lying",
        "react_1": "arms",
        "react_2": "front",
    }
    WALK_ANIM = {"walk_1", "walk_2", "walk_3"}
    for anim_name, src in ANIM_MAP.items():
        frame = processed[src].copy()
        if anim_name in WALK_ANIM:
            frame = frame.transpose(Image.FLIP_LEFT_RIGHT)
        frame.save(os.path.join(out_dir, f"{anim_name}.png"))

    return processed


def split_frames(result, out_dir, frame_size=128, margin=8):
    FRAME_NAMES = [
        ["walk_down_1", "walk_down_2", "walk_down_3", "arms_raised"],
        ["walk_left_1", "walk_left_2", "walk_left_3", "jump_left"],
        ["walk_right_1", "walk_right_2", "walk_right_3", "jump_right"],
        ["walk_back_1", "walk_back_2", "walk_back_3", "lying_down"],
    ]
    col_bounds, row_bounds = detect_grid_valleys(result)

    # 2×2 layout detection: if any detected row section is too thin, the LoRA
    # generated 4 large poses (front/arms/back/lying) instead of 16 walk-cycle frames.
    row_heights = [row_bounds[i + 1] - row_bounds[i] for i in range(len(row_bounds) - 1)]
    if min(row_heights) < 60:
        return _split_frames_2x2(result, out_dir, frame_size, margin)

    col_count = _detect_col_count(result)
    if col_count == 2:
        return _split_frames_4x2(result, out_dir, frame_size, margin, row_bounds)

    def _row_col_bounds(row_y1, row_y2, n=4, pad=5):
        """특정 행의 밀도로 컬럼 경계를 독립 검출."""
        strip = result.crop((0, row_y1, result.width, row_y2))
        arr = np.array(strip.convert("RGB"))
        den = (~((arr[:,:,0]>230)&(arr[:,:,1]>230)&(arr[:,:,2]>230))).sum(axis=0).astype(float)
        nz = np.where(den > 2)[0]
        if len(nz) == 0:
            return col_bounds
        start, end = int(nz[0]), int(nz[-1])
        sw = (end - start) // n
        bounds = [max(0, start - pad)]
        for i in range(1, n):
            c = start + i * sw
            lo, hi = max(start, c - sw // 3), min(end, c + sw // 3)
            bounds.append(lo + int(np.argmin(den[lo:hi])))
        bounds.append(min(result.width, end + pad))
        return bounds

    # walk_left/walk_down 행은 각 행의 밀도로 컬럼 경계 독립 검출
    walk_down_col_bounds = _row_col_bounds(row_bounds[0], row_bounds[1])
    walk_left_col_bounds = _row_col_bounds(row_bounds[1], row_bounds[2])

    def _smart_crop(img, density_threshold=0.04):
        """가로는 density 필터(아티팩트 제거), 세로는 tight 기준(발끝 보존)."""
        arr = np.array(img.convert("RGB"))
        content = ~((arr[:, :, 0] > 230) & (arr[:, :, 1] > 230) & (arr[:, :, 2] > 230))
        col_den = content.sum(axis=0) / max(content.shape[0], 1)
        col_mask = col_den > density_threshold
        row_any = content.any(axis=1)
        if not col_mask.any() or not row_any.any():
            return tight_crop(img)
        x0, x1 = int(np.where(col_mask)[0][0]), int(np.where(col_mask)[0][-1])
        y0, y1 = int(np.where(row_any)[0][0]), int(np.where(row_any)[0][-1])
        return img.crop((x0, y0, x1 + 1, y1 + 1))

    def _filter_largest_component(rgba_img):
        """rembg alpha 기반으로 가장 큰 연결 컴포넌트만 남기고 아티팩트 제거."""
        arr = np.array(rgba_img)
        alpha = arr[:, :, 3] > 10
        if not alpha.any():
            return rgba_img
        labeled, n = ndi.label(alpha)
        if n <= 1:
            return rgba_img
        sizes = ndi.sum(alpha, labeled, range(1, n + 1))
        main_label = int(np.argmax(sizes)) + 1
        mask = labeled == main_label
        result = arr.copy()
        result[~mask, 3] = 0
        return Image.fromarray(result, "RGBA")

    # 1패스: 모든 행 독립 컬럼 경계 + connected component 아티팩트 제거
    walk_right_col_bounds = _row_col_bounds(row_bounds[2], row_bounds[3])
    walk_back_col_bounds  = _row_col_bounds(row_bounds[3], result.height)
    ROW_COL_BOUNDS = {
        0: walk_down_col_bounds,
        1: walk_left_col_bounds,
        2: walk_right_col_bounds,
        3: walk_back_col_bounds,
    }
    tight_frames = {}
    for row_idx, row_names in enumerate(FRAME_NAMES):
        cb = ROW_COL_BOUNDS[row_idx]
        for col_idx, name in enumerate(row_names):
            x1 = cb[col_idx]
            y1 = row_bounds[row_idx]
            x2 = result.width  if col_idx == 3 else cb[col_idx + 1]
            y2 = result.height if row_idx == 3 else row_bounds[row_idx + 1]
            cell = result.crop((x1, y1, x2, y2))
            tight_frames[name] = _smart_crop(cell)

    # 1.5패스: 스케일링 전 원본 기준으로 유효성 계산
    # tight_crop은 RGB라 RGBA 변환 시 alpha=255 → remove_white_bg로 실제 불투명 픽셀 계산
    def _is_empty_tight(tc, min_opaque=500) -> bool:
        arr = np.array(remove_white_bg(tc))
        return int((arr[:, :, 3] > 10).sum()) < min_opaque

    empty_flags = {name: _is_empty_tight(tc) for name, tc in tight_frames.items()}
    # walk_left가 walk_right보다 안정적으로 생성됨 → walk 기준 행으로 사용
    # Companion.gd에서 flip_h로 방향 전환하므로 left 프레임으로도 동작
    walk2_valid = not empty_flags["walk_left_2"]
    walk3_valid = not empty_flags["walk_left_3"]

    # 2패스: 캐릭터 높이 기준 정규화 → frame_size 정사각 캔버스 (투명 배경)
    # 모든 서있는 프레임을 동일 높이로 스케일해 애니메이션 크기 일관성 확보
    LYING_FRAMES = {"lying_down"}
    target_char_h = int(frame_size * 0.82)

    raw_frames = {}
    for name, tc in tight_frames.items():
        tc_rgba = _filter_largest_component(remove_white_bg(tc))
        w, h = tc_rgba.size

        if name not in LYING_FRAMES and h > 10:
            # 높이 우선으로 스케일, 너비가 프레임을 초과하면 너비 기준으로 재조정
            scale = min(target_char_h / h, (frame_size - margin) / max(w, 1))
            new_w = max(1, int(w * scale))
            new_h = max(1, int(h * scale))
        else:
            scale = (frame_size - margin * 2) / max(w, 1)
            new_w = frame_size - margin * 2
            new_h = max(1, int(h * scale))

        tc_scaled = tc_rgba.resize((new_w, new_h), NEAREST)
        canvas = Image.new("RGBA", (frame_size, frame_size), (0, 0, 0, 0))
        paste_x = (frame_size - new_w) // 2
        paste_y = frame_size - new_h - margin  # 바닥 정렬로 발 위치 일관성
        canvas.paste(tc_scaled, (paste_x, max(0, paste_y)), mask=tc_scaled)
        raw_frames[name] = canvas
        canvas.save(os.path.join(out_dir, f"frame_{name}.png"))

    # 3패스: 빈 프레임 폴백 (empty_flags 재사용)
    for row_names in FRAME_NAMES:
        fallback = next((raw_frames[n] for n in row_names if not empty_flags[n]), None)
        if fallback is None:
            continue
        for name in row_names:
            if empty_flags[name]:
                raw_frames[name] = fallback.copy()
                fallback.copy().save(os.path.join(out_dir, f"frame_{name}.png"))

    # 4패스: 유효 프레임에 따라 ANIM_MAP 동적 결정

    if walk2_valid and walk3_valid:
        walk_2_src, walk_3_src = "walk_left_2", "walk_left_3"
    elif walk2_valid:
        walk_2_src, walk_3_src = "walk_left_2", "jump_left"
    else:
        walk_2_src, walk_3_src = "jump_left", "walk_left_1"

    def _pixel_count(name: str) -> int:
        arr = np.array(raw_frames[name])
        return int((arr[:, :, 3] > 10).sum())

    idle_src = max(["walk_down_1", "walk_down_2", "walk_down_3"], key=_pixel_count)

    ANIM_MAP = {
        "idle_1":  idle_src,
        "walk_1":  "walk_left_1",
        "walk_2":  walk_2_src,
        "walk_3":  walk_3_src,
        "sleep_1": "lying_down",
        "react_1": "arms_raised",
        "react_2": idle_src,
    }

    # walk 프레임은 walk_left 기반이라 오른쪽을 향하도록 미러링
    WALK_ANIM = {"walk_1", "walk_2", "walk_3"}
    for anim_name, src in ANIM_MAP.items():
        frame = raw_frames[src].copy()
        if anim_name in WALK_ANIM:
            frame = frame.transpose(Image.FLIP_LEFT_RIGHT)
        frame.save(os.path.join(out_dir, f"{anim_name}.png"))

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

    steps = args.steps if args.steps else (28 if device != "cpu" else 20)
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
        guidance_scale=3.5,
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

    parser.add_argument("--output",    default="./sprites", help="출력 디렉토리")
    parser.add_argument("--seed",      type=int, default=42)
    parser.add_argument("--steps",     type=int, default=None, help="추론 스텝 (기본: GPU=64, CPU=20)")
    parser.add_argument("--hf-token",       default="", help="HuggingFace 토큰 (또는 HF_TOKEN 환경변수)")
    parser.add_argument("--status-file",    default="", help="Godot용 진행 상태 파일 경로")
    parser.add_argument("--reference-image", default="", help="캐릭터 참고 이미지 경로 (img2img 모드)")
    args = parser.parse_args()
    generate(args)
