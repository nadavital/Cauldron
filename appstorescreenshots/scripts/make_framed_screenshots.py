#!/usr/bin/env python3
from __future__ import annotations

from collections import deque
from dataclasses import dataclass
import os
from pathlib import Path

from PIL import Image


# Defaults to the repository's appstorescreenshots directory; can be overridden
# for custom checkouts or alternate asset locations.
ROOT = Path(
    os.environ.get(
        "CAULDRON_SCREENSHOTS_ROOT",
        str(Path(__file__).resolve().parent.parent),
    )
).expanduser().resolve()
SOURCE_ROOT = ROOT / "appscreenshots"
OUTPUT_ROOT = ROOT / "output" / "framed"


@dataclass(frozen=True)
class FrameSpec:
    platform: str
    source_dir: Path
    frame_path: Path
    appstore_target_size: tuple[int, int]


SPECS = (
    FrameSpec(
        platform="iPhone",
        source_dir=SOURCE_ROOT / "iPhone" / "1.3",
        frame_path=Path(
            "/Volumes/Bezel-iPhone-17/PNG/iPhone 17 Pro Max/"
            "iPhone 17 Pro Max - Silver - Portrait.png"
        ),
        appstore_target_size=(1320, 2868),
    ),
    FrameSpec(
        platform="iPad",
        source_dir=SOURCE_ROOT / "iPad" / "1.3",
        frame_path=Path(
            "/Volumes/Bezel-iPad-Pro-M4/PNG/"
            "iPad Pro 11 - M4 - Silver - Portrait.png"
        ),
        appstore_target_size=(1668, 2388),
    ),
)


def find_screen_bbox(frame: Image.Image) -> tuple[int, int, int, int]:
    alpha = frame.split()[-1]
    width, height = frame.size
    cx, cy = width // 2, height // 2

    if alpha.getpixel((cx, cy)) != 0:
        raise ValueError("Frame center is not transparent; cannot infer screen aperture.")

    queue = deque([(cx, cy)])
    seen = {(cx, cy)}
    min_x = max_x = cx
    min_y = max_y = cy

    while queue:
        x, y = queue.popleft()
        if x < min_x:
            min_x = x
        if x > max_x:
            max_x = x
        if y < min_y:
            min_y = y
        if y > max_y:
            max_y = y

        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (
                0 <= nx < width
                and 0 <= ny < height
                and (nx, ny) not in seen
                and alpha.getpixel((nx, ny)) == 0
            ):
                seen.add((nx, ny))
                queue.append((nx, ny))

    return min_x, min_y, max_x, max_y


def fit_cover(image: Image.Image, target_size: tuple[int, int]) -> Image.Image:
    target_w, target_h = target_size
    src_w, src_h = image.size
    scale = max(target_w / src_w, target_h / src_h)
    scaled_w = int(round(src_w * scale))
    scaled_h = int(round(src_h * scale))
    resized = image.resize((scaled_w, scaled_h), Image.Resampling.LANCZOS)

    left = (scaled_w - target_w) // 2
    top = (scaled_h - target_h) // 2
    return resized.crop((left, top, left + target_w, top + target_h))


def compose_raw(source: Image.Image, frame: Image.Image, screen_bbox: tuple[int, int, int, int]) -> Image.Image:
    min_x, min_y, max_x, max_y = screen_bbox
    screen_w = max_x - min_x + 1
    screen_h = max_y - min_y + 1

    screen_image = fit_cover(source, (screen_w, screen_h))
    background = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    background.paste(screen_image, (min_x, min_y))

    return Image.alpha_composite(background, frame)


def compose_appstore(raw: Image.Image, target_size: tuple[int, int]) -> Image.Image:
    out_w, out_h = target_size
    raw_w, raw_h = raw.size

    # Keep full device visible with breathing room while preserving upload dimensions.
    scale = min((out_w * 0.96) / raw_w, (out_h * 0.96) / raw_h)
    placed_w = int(round(raw_w * scale))
    placed_h = int(round(raw_h * scale))
    resized = raw.resize((placed_w, placed_h), Image.Resampling.LANCZOS)

    canvas = Image.new("RGB", (out_w, out_h), (245, 241, 234))
    x = (out_w - placed_w) // 2
    y = (out_h - placed_h) // 2
    canvas.paste(resized, (x, y), resized)
    return canvas


def process_spec(spec: FrameSpec) -> None:
    frame = Image.open(spec.frame_path).convert("RGBA")
    screen_bbox = find_screen_bbox(frame)

    raw_out_dir = OUTPUT_ROOT / "raw" / spec.platform
    appstore_out_dir = OUTPUT_ROOT / "appstore" / spec.platform
    raw_out_dir.mkdir(parents=True, exist_ok=True)
    appstore_out_dir.mkdir(parents=True, exist_ok=True)

    input_files = sorted(
        path
        for path in spec.source_dir.iterdir()
        if path.is_file() and path.suffix.lower() == ".png"
    )
    if not input_files:
        raise RuntimeError(f"No PNG files found in {spec.source_dir}")

    print(f"[{spec.platform}] frame={spec.frame_path.name} screen_bbox={screen_bbox}")
    for source_path in input_files:
        source = Image.open(source_path).convert("RGB")

        raw = compose_raw(source, frame, screen_bbox)
        appstore = compose_appstore(raw, spec.appstore_target_size)

        raw_out_path = raw_out_dir / source_path.name
        appstore_out_path = appstore_out_dir / source_path.name

        raw.save(raw_out_path, format="PNG", optimize=True)
        appstore.save(appstore_out_path, format="PNG", optimize=True)
        print(f"  wrote {raw_out_path}")
        print(f"  wrote {appstore_out_path}")


def main() -> None:
    for spec in SPECS:
        process_spec(spec)

    print("\nDone.")
    print(f"Output root: {OUTPUT_ROOT}")


if __name__ == "__main__":
    main()
