#!/usr/bin/env python3
from __future__ import annotations

from collections import deque
from dataclasses import dataclass
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


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

PLAYCOUNT_6_9_TEMPLATE = Path(
    os.environ.get(
        "CAULDRON_IPHONE_FRAME_TEMPLATE",
        "/Users/nadav/Desktop/playCount/AppStoreScreenshots/Framed-6.9/01-your-music-ranked.png",
    )
).expanduser()
WEBSITE_CAULDRON_SOURCE = Path("/Users/nadav/Desktop/Website/public/assets/cauldron")


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

WEBSITE_IPHONE_SHOTS = (
    ("cook_tab.jpg", "01-add-cook-share.png"),
    ("recipe_view.jpg", "02-cook-with-confidence.png"),
    ("generate_recipe.jpg", "03-generate-fresh-ideas.png"),
    ("explore_tab.jpg", "04-discover-recipes-fast.png"),
    ("groceries_tab.jpg", "05-shop-from-any-recipe.png"),
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


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


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


def compose_with_playcount_iphone_template(source: Image.Image) -> Image.Image:
    if not PLAYCOUNT_6_9_TEMPLATE.exists():
        raise RuntimeError(f"Missing iPhone frame template at {PLAYCOUNT_6_9_TEMPLATE}")

    canvas = Image.new("RGB", (1320, 2868), (245, 241, 234))
    device_frame = (145, 530, 1030, 2190)
    screen_rect = (39, 42, 952, 2072)
    template = Image.open(PLAYCOUNT_6_9_TEMPLATE).convert("RGBA").crop(
        (
            device_frame[0],
            device_frame[1],
            device_frame[0] + device_frame[2],
            device_frame[1] + device_frame[3],
        )
    )

    sx, sy, sw, sh = screen_rect
    screen = fit_cover(source.convert("RGB"), (sw, sh)).convert("RGBA")
    mask = rounded_mask((sw, sh), 94)
    template.paste(Image.new("RGBA", (sw, sh), (0, 0, 0, 255)), (sx, sy), mask)
    template.paste(screen, (sx, sy), mask)

    shadow = Image.new("RGBA", template.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    draw.rounded_rectangle((18, 18, template.width - 18, template.height - 18), radius=150, fill=(0, 0, 0, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))

    x, y = device_frame[0], device_frame[1]
    patch = canvas.crop((x, y, x + template.width, y + template.height)).convert("RGBA")
    patch = Image.alpha_composite(patch, shadow)
    patch = Image.alpha_composite(patch, template)
    canvas.paste(patch.convert("RGB"), (x, y))
    return canvas


def input_files_for_spec(spec: FrameSpec) -> list[tuple[Path, str]]:
    if spec.source_dir.exists():
        return [
            (path, path.name)
            for path in sorted(spec.source_dir.iterdir())
            if path.is_file() and path.suffix.lower() in (".png", ".jpg", ".jpeg")
        ]

    if spec.platform == "iPhone" and all((WEBSITE_CAULDRON_SOURCE / name).exists() for name, _ in WEBSITE_IPHONE_SHOTS):
        return [(WEBSITE_CAULDRON_SOURCE / name, output_name) for name, output_name in WEBSITE_IPHONE_SHOTS]

    return []


def process_spec(spec: FrameSpec) -> None:
    input_files = input_files_for_spec(spec)
    if not input_files:
        print(f"[{spec.platform}] skipped: no screenshots found in {spec.source_dir}")
        return

    raw_out_dir = OUTPUT_ROOT / "raw" / spec.platform
    appstore_out_dir = OUTPUT_ROOT / "appstore" / spec.platform
    raw_out_dir.mkdir(parents=True, exist_ok=True)
    appstore_out_dir.mkdir(parents=True, exist_ok=True)

    if spec.frame_path.exists():
        frame = Image.open(spec.frame_path).convert("RGBA")
        screen_bbox = find_screen_bbox(frame)
        print(f"[{spec.platform}] frame={spec.frame_path.name} screen_bbox={screen_bbox}")

        for source_path, output_name in input_files:
            source = Image.open(source_path).convert("RGB")
            raw = compose_raw(source, frame, screen_bbox)
            appstore = compose_appstore(raw, spec.appstore_target_size)

            raw_out_path = raw_out_dir / output_name
            appstore_out_path = appstore_out_dir / output_name

            raw.save(raw_out_path, format="PNG", optimize=True)
            appstore.save(appstore_out_path, format="PNG", optimize=True)
            print(f"  wrote {raw_out_path}")
            print(f"  wrote {appstore_out_path}")
        return

    if spec.platform == "iPhone":
        print(f"[{spec.platform}] frame template={PLAYCOUNT_6_9_TEMPLATE}")
        for source_path, output_name in input_files:
            source = Image.open(source_path).convert("RGB")
            appstore = compose_with_playcount_iphone_template(source)
            appstore_out_path = appstore_out_dir / output_name
            appstore.save(appstore_out_path, format="PNG", optimize=True)
            print(f"  wrote {appstore_out_path}")
        return

    print(f"[{spec.platform}] skipped: missing frame at {spec.frame_path}")


def main() -> None:
    for spec in SPECS:
        process_spec(spec)

    print("\nDone.")
    print(f"Output root: {OUTPUT_ROOT}")


if __name__ == "__main__":
    main()
