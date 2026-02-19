#!/usr/bin/env python3
from __future__ import annotations

from collections import deque
from dataclasses import dataclass
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


# Defaults to the repository's appstorescreenshots directory; can be overridden
# for custom checkouts or alternate asset locations.
ROOT = Path(
    os.environ.get(
        'CAULDRON_SCREENSHOTS_ROOT',
        str(Path(__file__).resolve().parent.parent),
    )
).expanduser().resolve()
OUT_ROOT = ROOT / 'output' / 'continuous_story_v3_appstore_continuous'

IPHONE_SOURCE = ROOT / 'appscreenshots' / 'iPhone' / '1.3'
IPAD_SOURCE = ROOT / 'appscreenshots' / 'iPad' / '1.3'
MAC_SOURCE = ROOT / 'appscreenshots' / 'Mac' / '1.3'

BG_MOBILE = ROOT / 'background.png'
BG_MAC = ROOT / 'macoswallpaper.jpeg'
ICON_PATH = ROOT / 'cauldroniconpng.png'

IPHONE_FRAME = Path('/Volumes/Bezel-iPhone-17/PNG/iPhone 17 Pro Max/iPhone 17 Pro Max - Silver - Portrait.png')
IPAD_FRAME = Path('/Volumes/Bezel-iPad-Pro-M4/PNG/iPad Pro 11 - M4 - Silver - Portrait.png')
MAC_FRAME = Path('/Volumes/Bezel-MacBook-Pro-M4/PNG/MacBook Pro M4 14-inch Silver.png')

FONT_TITLE = '/Library/Fonts/SF-Pro-Display-Semibold.otf'
FONT_BODY = '/Library/Fonts/SF-Pro-Text-Medium.otf'


@dataclass(frozen=True)
class Shot:
    key: str
    title: str
    body: str


@dataclass(frozen=True)
class PlatformSpec:
    name: str
    canvas_size: tuple[int, int]
    top_area: int
    bottom_area: int
    side_margin: int
    title_size: int
    body_size: int
    text_left_margin: int
    icon_size_first: int
    bg_path: Path
    frame_path: Path
    screen_corner_radius: int
    source_ext: str
    shots: tuple[Shot, ...]


IPHONE_SHOTS = (
    Shot('cook_tab', '', 'Add. Cook. Share.'),
    Shot('recipe_view', 'Recipe View', 'Follow every recipe step by step with ingredients and timing in view.'),
    Shot('friends_tab', 'Share', 'Follow friends, swap recipes, and discover what to cook next.'),
    Shot('generate_recipe', 'Generate', 'Turn ingredients you have into instant recipe ideas.'),
    Shot('live_activity', 'Follow Along', 'Live updates keep your active cook session in sync.'),
    Shot('profile_view', 'Level Up', 'Earn progress and unlock new app icons as you cook.'),
    Shot('search_tab', 'Search', 'Find your next favorite recipe.'),
)

IPAD_SHOTS = (
    Shot('cook_tab', '', 'Add. Cook. Share.'),
    Shot('recipe_view', 'Recipe View', 'Follow every recipe step by step with ingredients and timing in view.'),
    Shot('cook_mode', 'Cook Mode', 'Follow along step by step with large, hands-on controls.'),
    Shot('friends_tab', 'Share', 'Follow friends, swap recipes, and discover what to cook next.'),
    Shot('live_activity', 'Follow Along', 'Live updates keep your active cook session in sync.'),
    Shot('profile_view', 'Level Up', 'Earn progress and unlock new app icons as you cook.'),
    Shot('search_tab', 'Search', 'Find your next favorite recipe.'),
)

MAC_SHOTS = (
    Shot('cook_tab', '', 'Add. Cook. Share.'),
    Shot('recipe_view', 'Recipe View', 'Follow every recipe step by step with ingredients and timing in view.'),
    Shot('friends_tab', 'Share', 'Follow friends, swap recipes, and discover what to cook next.'),
    Shot('generate_recipe', 'Generate', 'Turn ingredients you have into instant recipe ideas.'),
    Shot('search_tab', 'Search', 'Find your next favorite recipe.'),
    Shot('profile_view', 'Level Up', 'Earn progress and unlock new app icons as you cook.'),
    Shot('collection_view', 'Collections', 'Organize favorites into collections faster.'),
)

SPECS = (
    PlatformSpec(
        name='iPhone',
        canvas_size=(1284, 2778),
        top_area=378,
        bottom_area=310,
        side_margin=84,
        title_size=144,
        body_size=56,
        text_left_margin=96,
        icon_size_first=118,
        bg_path=BG_MOBILE,
        frame_path=IPHONE_FRAME,
        screen_corner_radius=96,
        source_ext='.PNG',
        shots=IPHONE_SHOTS,
    ),
    PlatformSpec(
        name='iPad',
        canvas_size=(2048, 2732),
        top_area=338,
        bottom_area=248,
        side_margin=152,
        title_size=156,
        body_size=58,
        text_left_margin=134,
        icon_size_first=110,
        bg_path=BG_MOBILE,
        frame_path=IPAD_FRAME,
        screen_corner_radius=64,
        source_ext='.PNG',
        shots=IPAD_SHOTS,
    ),
    PlatformSpec(
        name='Mac',
        canvas_size=(2560, 1600),
        top_area=316,
        bottom_area=142,
        side_margin=136,
        title_size=128,
        body_size=52,
        text_left_margin=128,
        icon_size_first=98,
        bg_path=BG_MOBILE,
        frame_path=MAC_FRAME,
        screen_corner_radius=22,
        source_ext='.png',
        shots=MAC_SHOTS,
    ),
)


def wrap_text(text: str, font: ImageFont.FreeTypeFont, max_width: int) -> list[str]:
    words = text.split()
    out: list[str] = []
    line = ''
    for word in words:
        candidate = f'{line} {word}'.strip()
        if not line or font.getlength(candidate) <= max_width:
            line = candidate
        else:
            out.append(line)
            line = word
    if line:
        out.append(line)
    return out


def find_screen_bbox(frame_rgba: Image.Image) -> tuple[int, int, int, int]:
    a = frame_rgba.split()[-1]
    w, h = frame_rgba.size
    sx, sy = w // 2, h // 2
    if a.getpixel((sx, sy)) != 0:
        raise RuntimeError(f'Frame center for {frame_rgba.size} is not transparent.')

    q = deque([(sx, sy)])
    seen = {(sx, sy)}
    minx = maxx = sx
    miny = maxy = sy

    while q:
        x, y = q.popleft()
        minx = min(minx, x)
        maxx = max(maxx, x)
        miny = min(miny, y)
        maxy = max(maxy, y)

        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and a.getpixel((nx, ny)) == 0:
                seen.add((nx, ny))
                q.append((nx, ny))

    return (minx, miny, maxx, maxy)


def fit_cover(src: Image.Image, target_size: tuple[int, int]) -> Image.Image:
    tw, th = target_size
    sw, sh = src.size
    scale = max(tw / sw, th / sh)
    nw = int(round(sw * scale))
    nh = int(round(sh * scale))
    resized = src.resize((nw, nh), Image.Resampling.LANCZOS)
    x = (nw - tw) // 2
    y = (nh - th) // 2
    return resized.crop((x, y, x + tw, y + th))


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new('L', size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def crop_to_visible_alpha(img: Image.Image, threshold: int = 10) -> Image.Image:
    a = img.split()[-1].point(lambda px: 255 if px > threshold else 0)
    bbox = a.getbbox()
    return img.crop(bbox) if bbox else img


def crop_black_border(img: Image.Image, threshold: int = 10) -> Image.Image:
    gray = img.convert('L')
    mask = gray.point(lambda px: 255 if px > threshold else 0)
    bbox = mask.getbbox()
    return img.crop(bbox) if bbox else img


def compose_mobile_frame(frame_path: Path, screenshot_path: Path, screen_corner_radius: int) -> Image.Image:
    frame = Image.open(frame_path).convert('RGBA')
    shot = Image.open(screenshot_path).convert('RGB')
    x0, y0, x1, y1 = find_screen_bbox(frame)
    sw, sh = x1 - x0 + 1, y1 - y0 + 1

    screen = fit_cover(shot, (sw, sh)).convert('RGBA')
    mask = rounded_mask((sw, sh), screen_corner_radius)
    clipped = Image.new('RGBA', (sw, sh), (0, 0, 0, 0))
    clipped.paste(screen, (0, 0), mask)

    base = Image.new('RGBA', frame.size, (0, 0, 0, 0))
    base.paste(clipped, (x0, y0), clipped)
    out = Image.alpha_composite(base, frame)
    return crop_to_visible_alpha(out)


def compose_macbook_frame(frame_path: Path, screenshot_path: Path, wallpaper: Image.Image, corner_radius: int) -> Image.Image:
    frame = Image.open(frame_path).convert('RGBA')
    shot = crop_black_border(Image.open(screenshot_path).convert('RGB'))
    x0, y0, x1, y1 = find_screen_bbox(frame)
    sw, sh = x1 - x0 + 1, y1 - y0 + 1

    screen_bg = fit_cover(wallpaper, (sw, sh)).convert('RGBA')

    # Floating app window on top of wallpaper inside the Mac screen.
    window_w = int(round(sw * 0.86))
    window_h = int(round(window_w * shot.height / shot.width))
    if window_h > int(sh * 0.80):
        window_h = int(sh * 0.80)
        window_w = int(round(window_h * shot.width / shot.height))

    window_img = fit_cover(shot, (window_w, window_h)).convert('RGBA')
    window_mask = rounded_mask((window_w, window_h), corner_radius)
    window = Image.new('RGBA', (window_w, window_h), (0, 0, 0, 0))
    window.paste(window_img, (0, 0), window_mask)

    sx = (sw - window_w) // 2
    sy = int(round((sh - window_h) * 0.53))

    screen_bg.paste(window, (sx, sy), window)

    base = Image.new('RGBA', frame.size, (0, 0, 0, 0))
    base.paste(screen_bg, (x0, y0), screen_bg)
    out = Image.alpha_composite(base, frame)
    return crop_to_visible_alpha(out)


def paste_rgba_without_halo(panel_rgb: Image.Image, overlay_rgba: Image.Image, x: int, y: int) -> None:
    w, h = overlay_rgba.size
    patch = panel_rgb.crop((x, y, x + w, y + h)).convert('RGBA')
    merged = Image.alpha_composite(patch, overlay_rgba)
    panel_rgb.paste(merged.convert('RGB'), (x, y))


def place_device(panel_rgb: Image.Image, device_rgba: Image.Image, top_area: int, bottom_area: int, side_margin: int) -> None:
    cw, ch = panel_rgb.size
    aw = cw - (2 * side_margin)
    ah = ch - top_area - bottom_area

    scale = min(aw / device_rgba.width, ah / device_rgba.height)
    pw = int(round(device_rgba.width * scale))
    ph = int(round(device_rgba.height * scale))

    placed = device_rgba.resize((pw, ph), Image.Resampling.LANCZOS)
    x = (cw - pw) // 2
    y = top_area + (ah - ph) // 2

    paste_rgba_without_halo(panel_rgb, placed, x, y)


def draw_copy(panel_rgb: Image.Image, shot: Shot, spec: PlatformSpec, idx: int, icon_source: Image.Image) -> None:
    draw = ImageDraw.Draw(panel_rgb)
    title_font = ImageFont.truetype(FONT_TITLE, spec.title_size)

    max_width = spec.canvas_size[0] - (2 * spec.text_left_margin)
    title_lines = wrap_text(shot.title, title_font, max_width)

    ty = 130 if spec.name == 'iPhone' else (114 if spec.name == 'iPad' else 96)
    if idx == 1:
        brand_text = 'Cauldron'
        brand_bbox = draw.textbbox((spec.text_left_margin, ty), brand_text, font=title_font)
        text_h = brand_bbox[3] - brand_bbox[1]
        icon_px = min(spec.icon_size_first, max(48, int(round(text_h * 0.94))))
        icon = icon_source.resize((icon_px, icon_px), Image.Resampling.LANCZOS)
        x = spec.text_left_margin
        text_mid_y = (brand_bbox[1] + brand_bbox[3]) / 2
        icon_y = int(round(text_mid_y - (icon_px / 2)))
        panel_rgb.paste(icon, (x, icon_y), icon)
        draw.text((x + icon_px + 18, ty), brand_text, font=title_font, fill=(39, 38, 37))
    else:
        cy = ty
        for line in title_lines:
            draw.text((spec.text_left_margin, cy), line, font=title_font, fill=(39, 38, 37))
            h = draw.textbbox((0, 0), line, font=title_font)[3]
            cy += h + 6

    by = spec.canvas_size[1] - spec.bottom_area + 40
    if spec.name in ('iPad', 'Mac'):
        # Keep subtitle copy on one line for larger-screen marketing shots.
        body_size = spec.body_size
        body_font = ImageFont.truetype(FONT_BODY, body_size)
        while body_size > 28 and body_font.getlength(shot.body) > max_width:
            body_size -= 1
            body_font = ImageFont.truetype(FONT_BODY, body_size)
        draw.text((spec.text_left_margin, by), shot.body, font=body_font, fill=(58, 56, 55))
    else:
        body_font = ImageFont.truetype(FONT_BODY, spec.body_size)
        body_lines = wrap_text(shot.body, body_font, max_width)
        cy = by
        for line in body_lines:
            draw.text((spec.text_left_margin, cy), line, font=body_font, fill=(58, 56, 55))
            h = draw.textbbox((0, 0), line, font=body_font)[3]
            cy += h + 4


def build_continuous_strip(bg_img: Image.Image, panel_size: tuple[int, int], count: int) -> Image.Image:
    pw, ph = panel_size
    total_w = pw * count
    # Stretch one background image across the full sequence width so adjacent panels
    # form a single continuous artwork when placed side-by-side.
    return bg_img.resize((total_w, ph), Image.Resampling.LANCZOS).convert('RGB')


def source_path(spec: PlatformSpec, key: str) -> Path:
    if spec.name == 'iPhone':
        return IPHONE_SOURCE / f'{key}{spec.source_ext}'
    if spec.name == 'iPad':
        return IPAD_SOURCE / f'{key}{spec.source_ext}'
    return MAC_SOURCE / f'{key}{spec.source_ext}'


def render_platform(spec: PlatformSpec, icon_source: Image.Image) -> None:
    out_dir = OUT_ROOT / spec.name
    out_dir.mkdir(parents=True, exist_ok=True)

    bg = Image.open(spec.bg_path).convert('RGB')
    strip = build_continuous_strip(bg, spec.canvas_size, len(spec.shots))

    mac_wall = Image.open(BG_MAC).convert('RGB') if spec.name == 'Mac' else None

    for i, shot in enumerate(spec.shots, start=1):
        x0 = (i - 1) * spec.canvas_size[0]
        panel = strip.crop((x0, 0, x0 + spec.canvas_size[0], spec.canvas_size[1])).convert('RGB')

        shot_path = source_path(spec, shot.key)
        if spec.name == 'Mac':
            assert mac_wall is not None
            device = compose_macbook_frame(spec.frame_path, shot_path, mac_wall, spec.screen_corner_radius)
        else:
            device = compose_mobile_frame(spec.frame_path, shot_path, spec.screen_corner_radius)

        place_device(panel, device, spec.top_area, spec.bottom_area, spec.side_margin)
        draw_copy(panel, shot, spec, i, icon_source)

        out_path = out_dir / f'{i:02d}_{shot.key}.png'
        panel.save(out_path, format='PNG', optimize=True)
        print(f'wrote {out_path}')


def write_sequence_preview(platform: str) -> None:
    files = sorted((OUT_ROOT / platform).glob('*.png'))
    if not files:
        return

    ims = [Image.open(f).convert('RGB') for f in files]
    total_w = sum(im.width for im in ims)
    h = max(im.height for im in ims)
    strip = Image.new('RGB', (total_w, h))

    x = 0
    for im in ims:
        strip.paste(im, (x, 0))
        x += im.width

    full = OUT_ROOT / f'{platform.lower()}_sequence_strip.png'
    preview = OUT_ROOT / f'{platform.lower()}_sequence_strip_preview.png'
    strip.save(full, format='PNG', optimize=True)
    strip.resize((strip.width // 4, strip.height // 4), Image.Resampling.LANCZOS).save(
        preview, format='PNG', optimize=True
    )
    print(f'wrote {full}')
    print(f'wrote {preview}')


def main() -> None:
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    icon = Image.open(ICON_PATH).convert('RGBA')

    for spec in SPECS:
        render_platform(spec, icon)
        write_sequence_preview(spec.name)

    print(f'Done. Output root: {OUT_ROOT}')


if __name__ == '__main__':
    main()
