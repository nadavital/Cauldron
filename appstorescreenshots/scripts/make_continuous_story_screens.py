#!/usr/bin/env python3
from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from functools import lru_cache
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
OUT_ROOT = ROOT / 'output' / 'cauldron_2_0_appstore'

IPHONE_SOURCE = ROOT / 'appscreenshots' / 'iPhone' / '2.0'
IPAD_SOURCE = ROOT / 'appscreenshots' / 'iPad' / '2.0'
MAC_SOURCE = ROOT / 'appscreenshots' / 'Mac' / '1.3'

BG_MOBILE = ROOT / 'background.png'
BG_MAC = ROOT / 'mac wallpaper'
ICON_PATH = ROOT / 'cauldroniconpng.png'

def first_existing_path(env_name: str, candidates: tuple[str, ...]) -> Path:
    if env_value := os.environ.get(env_name):
        return Path(env_value).expanduser()

    for pattern in candidates:
        matches = sorted(Path('/').glob(pattern.lstrip('/')))
        if matches:
            return matches[0]

    return Path(candidates[0])


IPHONE_FRAME = first_existing_path(
    'CAULDRON_IPHONE_FRAME',
    (
        '/Volumes/Bezel-iPhone-17/PNG/iPhone 17 Pro Max/iPhone 17 Pro Max - Silver - Portrait.png',
        '/Volumes/Bezel-iPhone-17/PNG/iPhone 17 Pro Max/*Silver*Portrait.png',
        '/Volumes/Bezel-iPhone-17/PNG/iPhone 17 Pro Max/*Portrait.png',
    ),
)
IPAD_FRAME = first_existing_path(
    'CAULDRON_IPAD_FRAME',
    (
        '/Volumes/Bezel-iPad-Pro-(M5)/PNG/iPad Pro (M5) 13" - Silver - Portrait.png',
        '/Volumes/Bezel-iPad-Pro-(M5)/PNG/iPad Pro (M5) 13"*Silver*Portrait.png',
        '/Volumes/Bezel-iPad-Pro-(M5)/PNG/iPad Pro (M5) 13"*Portrait.png',
        '/Volumes/Bezel-iPad-Pro-(M5)/PNG/iPad Pro (M5) 11"*Silver*Portrait.png',
        '/Volumes/Bezel-iPad-Pro-(M5)/PNG/iPad Pro (M5) 11"*Portrait.png',
        '/Volumes/Bezel-iPad-Pro-M5/PNG/iPad Pro 13 - M5 - Silver - Portrait.png',
        '/Volumes/Bezel-iPad-Pro-M5/PNG/iPad Pro 13*Silver*Portrait.png',
        '/Volumes/Bezel-iPad-Pro-M5/PNG/iPad Pro 13*Portrait.png',
        '/Volumes/Bezel-iPad-Pro-M5/PNG/iPad Pro 11*Silver*Portrait.png',
        '/Volumes/Bezel-iPad-Pro-M5/PNG/iPad Pro 11*Portrait.png',
    ),
)
MAC_FRAME = first_existing_path(
    'CAULDRON_MAC_FRAME',
    (
        '/Volumes/Bezel-MacBook-Pro-M5/PNG/MacBook Pro M5 14-inch Silver.png',
        '/Volumes/Bezel-MacBook-Pro-M5/PNG/MacBook Pro*14*Silver.png',
        '/Volumes/Bezel-MacBook-Pro-M5/PNG/MacBook Pro*.png',
    ),
)
WEBSITE_CAULDRON_SOURCE = Path('/Users/nadav/Desktop/Website/public/assets/cauldron')

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
    Shot('cook_tab', 'All your recipes. Finally together.', ''),
    Shot('recipe_view', 'Cook without losing your place.', ''),
    Shot('search_tab', 'Find tonight\'s answer in seconds.', ''),
    Shot('generate_recipe', 'Turn what you have into dinner.', ''),
    Shot('friends_tab', 'Share recipes, not screenshots.', ''),
    Shot('collection_view', 'Organize it your way.', ''),
    Shot('live_activity', 'Keep cooking from the Lock Screen.', ''),
)

IPAD_SHOTS = (
    Shot('cook_tab', 'All your recipes. Finally together.', ''),
    Shot('recipe_view', 'Cook without losing your place.', ''),
    Shot('search_results', 'Find tonight\'s answer in seconds.', ''),
    Shot('friends_tab', 'Share recipes, not screenshots.', ''),
    Shot('cook_mode', 'Cook with everything in view.', ''),
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

WEBSITE_SOURCE_NAMES = {
    'cook_tab': 'cook_tab.jpg',
    'recipe_view': 'recipe_view.jpg',
    'generate_recipe': 'generate_recipe.jpg',
    'search_tab': 'explore_tab.jpg',
    'groceries_tab': 'groceries_tab.jpg',
}

IPHONE_FALLBACK_SHOTS = (
    Shot('cook_tab', '', 'Add. Cook. Share.'),
    Shot('recipe_view', 'Recipe View', 'Follow every recipe step by step with ingredients and timing in view.'),
    Shot('generate_recipe', 'Generate', 'Turn ingredients you have into instant recipe ideas.'),
    Shot('search_tab', 'Search', 'Find your next favorite recipe.'),
    Shot('groceries_tab', 'Groceries', 'Build a smart grocery list from any recipe.'),
)

SPECS = (
    PlatformSpec(
        name='iPhone',
        canvas_size=(1320, 2868),
        top_area=350,
        bottom_area=40,
        side_margin=72,
        title_size=104,
        body_size=56,
        text_left_margin=96,
        icon_size_first=118,
        bg_path=BG_MOBILE,
        frame_path=IPHONE_FRAME,
        screen_corner_radius=132,
        source_ext='.PNG',
        shots=IPHONE_SHOTS,
    ),
    PlatformSpec(
        name='iPad',
        canvas_size=(2048, 2732),
        top_area=400,
        bottom_area=80,
        side_margin=136,
        title_size=128,
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


def remove_ipad_window_resize_indicator(shot: Image.Image) -> Image.Image:
    """Remove capture-only iPad window chrome before placing a full-screen app in a device frame."""
    cleaned = shot.copy()
    corner_size = 72
    x0 = shot.width - corner_size
    y0 = shot.height - corner_size
    corner = shot.crop((x0, y0, shot.width, shot.height))
    replacement = shot.crop((x0 - corner_size, y0, x0, shot.height))

    # The system handle is a neutral-gray arc. Restrict the repair to those
    # pixels so nearby app content remains intact, then softly expand the mask
    # to include the antialiased edge of the glyph.
    mask = Image.new('L', (corner_size, corner_size), 0)
    mask_pixels = mask.load()
    corner_pixels = corner.load()
    for y in range(corner_size):
        for x in range(corner_size):
            red, green, blue = corner_pixels[x, y]
            brightness = (red + green + blue) / 3
            if max(red, green, blue) - min(red, green, blue) <= 8 and 55 <= brightness <= 190:
                mask_pixels[x, y] = 255

    mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.2))
    cleaned.paste(replacement, (x0, y0), mask)
    return cleaned


def compose_generated_mobile_frame(
    screenshot_path: Path,
    screen_corner_radius: int,
    pad: int = 54,
    remove_window_resize_indicator: bool = False,
) -> Image.Image:
    shot = Image.open(screenshot_path).convert('RGB')
    if remove_window_resize_indicator:
        shot = remove_ipad_window_resize_indicator(shot)
    shell = Image.new('RGBA', (shot.width + pad * 2, shot.height + pad * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shell)
    radius = screen_corner_radius + pad
    draw.rounded_rectangle(
        (0, 0, shell.width - 1, shell.height - 1),
        radius=radius,
        fill=(154, 155, 157, 255),
    )
    draw.rounded_rectangle(
        (6, 6, shell.width - 7, shell.height - 7),
        radius=radius - 6,
        fill=(24, 24, 24, 255),
    )
    draw.rounded_rectangle(
        (pad - 8, pad - 8, shell.width - pad + 7, shell.height - pad + 7),
        radius=screen_corner_radius + 8,
        fill=(6, 6, 6, 255),
    )
    screen = shot.convert('RGBA')
    mask = rounded_mask(shot.size, screen_corner_radius)
    shell.paste(screen, (pad, pad), mask)
    return shell


def compose_generated_mac_frame(screenshot_path: Path, corner_radius: int) -> Image.Image:
    shot = crop_black_border(Image.open(screenshot_path).convert('RGB')).convert('RGBA')
    pad = 42
    title_h = 56
    frame = Image.new('RGBA', (shot.width + pad * 2, shot.height + pad * 2 + title_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(frame)
    outer = (0, 0, frame.width - 1, frame.height - 1)
    draw.rounded_rectangle(outer, radius=corner_radius + 28, fill=(232, 228, 219, 255))
    draw.rounded_rectangle(
        (pad, pad + title_h, pad + shot.width, pad + title_h + shot.height),
        radius=corner_radius,
        fill=(255, 255, 255, 255),
    )
    for i, color in enumerate(((255, 95, 87), (255, 189, 46), (40, 201, 64))):
        x = pad + 22 + i * 34
        y = pad + 25
        draw.ellipse((x, y, x + 16, y + 16), fill=color + (255,))
    mask = rounded_mask(shot.size, corner_radius)
    frame.paste(shot, (pad, pad + title_h), mask)
    return frame


def crop_to_visible_alpha(img: Image.Image, threshold: int = 10) -> Image.Image:
    a = img.split()[-1].point(lambda px: 255 if px > threshold else 0)
    bbox = a.getbbox()
    return img.crop(bbox) if bbox else img


def crop_black_border(img: Image.Image, threshold: int = 10) -> Image.Image:
    gray = img.convert('L')
    mask = gray.point(lambda px: 255 if px > threshold else 0)
    bbox = mask.getbbox()
    return img.crop(bbox) if bbox else img


def load_mobile_background(path: Path, size: tuple[int, int]) -> Image.Image:
    # Start from the shipping light-mode canvas. Brand depth is added across the
    # full sequence in build_continuous_strip so adjacent screenshots remain a
    # single restrained artwork rather than seven unrelated gradients.
    return Image.new('RGB', size, (246, 241, 234))


def compose_mobile_frame(frame_path: Path, screenshot_path: Path, screen_corner_radius: int) -> Image.Image:
    if not frame_path.exists():
        return compose_generated_mobile_frame(
            screenshot_path,
            screen_corner_radius,
            remove_window_resize_indicator=frame_path == IPAD_FRAME,
        )

    frame = Image.open(frame_path).convert('RGBA')
    shot = Image.open(screenshot_path).convert('RGB')
    if frame_path == IPAD_FRAME:
        shot = remove_ipad_window_resize_indicator(shot)
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


@lru_cache(maxsize=4)
def make_generated_mac_wallpaper(size: tuple[int, int]) -> Image.Image:
    w, h = size
    column = Image.new('RGB', (1, h))
    px = column.load()
    top = (247, 236, 216)
    mid = (238, 169, 92)
    bottom = (89, 78, 67)
    for y in range(h):
        t = y / max(1, h - 1)
        if t < 0.60:
            u = t / 0.60
            color = tuple(round(top[i] * (1 - u) + mid[i] * u) for i in range(3))
        else:
            u = (t - 0.60) / 0.40
            color = tuple(round(mid[i] * (1 - u) + bottom[i] * u) for i in range(3))
        px[0, y] = color
    bg = column.resize(size, Image.Resampling.BICUBIC)

    overlay = Image.new('RGBA', size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    draw.polygon(
        [(-w * 0.08, h * 0.90), (w * 0.40, h * 0.22), (w * 0.68, h * 0.54), (w * 0.14, h * 1.08)],
        fill=(255, 244, 203, 118),
    )
    draw.polygon(
        [(w * 0.30, -h * 0.08), (w * 1.10, h * 0.44), (w * 0.92, h * 0.78), (w * 0.10, h * 0.26)],
        fill=(255, 184, 93, 92),
    )
    draw.polygon(
        [(w * 0.62, -h * 0.04), (w * 1.08, h * 0.14), (w * 0.82, h * 0.92), (w * 0.48, h * 0.70)],
        fill=(72, 66, 61, 82),
    )
    return Image.alpha_composite(bg.convert('RGBA'), overlay.filter(ImageFilter.GaussianBlur(18))).convert('RGB')


def compose_macbook_frame(frame_path: Path, screenshot_path: Path, wallpaper: Image.Image | None, corner_radius: int) -> Image.Image:
    if not frame_path.exists():
        return compose_generated_mac_frame(screenshot_path, corner_radius)

    frame = Image.open(frame_path).convert('RGBA')
    shot = crop_black_border(Image.open(screenshot_path).convert('RGB'))
    x0, y0, x1, y1 = find_screen_bbox(frame)
    sw, sh = x1 - x0 + 1, y1 - y0 + 1

    if wallpaper is None:
        screen_bg = make_generated_mac_wallpaper((sw, sh)).convert('RGBA')
    else:
        screen_bg = fit_cover(wallpaper, (sw, sh)).convert('RGBA')

    # Floating app window on top of wallpaper inside the Mac screen.
    window_w = int(round(sw * 0.78))
    window_h = int(round(window_w * shot.height / shot.width))
    if window_h > int(sh * 0.70):
        window_h = int(sh * 0.70)
        window_w = int(round(window_h * shot.width / shot.height))

    window_img = fit_cover(shot, (window_w, window_h)).convert('RGBA')
    window_mask = rounded_mask((window_w, window_h), corner_radius)
    window = Image.new('RGBA', (window_w, window_h), (0, 0, 0, 0))
    window.paste(window_img, (0, 0), window_mask)
    shadow = Image.new('RGBA', (window_w + 80, window_h + 80), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle((40, 40, 40 + window_w, 40 + window_h), radius=corner_radius, fill=(0, 0, 0, 105))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))

    sx = (sw - window_w) // 2
    sy = int(round((sh - window_h) * 0.48))

    screen_bg.paste(shadow, (sx - 40, sy - 34), shadow)
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

    if spec.name in ('iPhone', 'iPad'):
        line_boxes = [draw.textbbox((0, 0), line, font=title_font) for line in title_lines]
        line_heights = [box[3] - box[1] for box in line_boxes]
        total_height = sum(line_heights) + max(0, len(title_lines) - 1) * 4
        cy = max(54, (spec.top_area - total_height) // 2 - 8)
        for line, box, line_height in zip(title_lines, line_boxes, line_heights):
            line_width = box[2] - box[0]
            draw.text(
                ((spec.canvas_size[0] - line_width) // 2, cy),
                line,
                font=title_font,
                fill=(39, 38, 37),
            )
            cy += line_height + 4
        return

    ty = 114 if spec.name == 'iPad' else 96
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
    # Warm paper base with a nearly imperceptible vertical lift toward the copy.
    column = Image.new('RGB', (1, ph))
    pixels = column.load()
    top = (251, 248, 243)
    bottom = (244, 237, 228)
    for y in range(ph):
        t = y / max(1, ph - 1)
        pixels[0, y] = tuple(round(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
    strip = column.resize((total_w, ph), Image.Resampling.BICUBIC).convert('RGBA')

    # Low-contrast Cauldron-orange light moves through the sequence. The glows
    # sit behind the device, leaving the headline area quiet and highly legible.
    glow = Image.new('RGBA', (total_w, ph), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    glow_specs = (
        (0.55, 0.76, 0.95, (255, 153, 51, 66)),
        (2.05, 0.62, 0.78, (224, 103, 31, 48)),
        (3.65, 0.82, 1.05, (255, 190, 92, 64)),
        (5.20, 0.68, 0.88, (240, 100, 73, 44)),
        (6.65, 0.80, 0.92, (255, 153, 51, 62)),
    )
    for panel_x, y_ratio, diameter_ratio, color in glow_specs:
        diameter = int(pw * diameter_ratio)
        cx = int(panel_x * pw)
        cy = int(ph * y_ratio)
        draw.ellipse(
            (cx - diameter // 2, cy - diameter // 2, cx + diameter // 2, cy + diameter // 2),
            fill=color,
        )

    # One broad, continuous ribbon suggests heat/steam without turning the
    # screenshots into patterned posters. It is intentionally strongest below
    # the copy and drifts across panels when viewed as a set.
    ribbon_points = [
        (-pw, int(ph * 0.77)),
        (int(total_w * 0.18), int(ph * 0.66)),
        (int(total_w * 0.40), int(ph * 0.80)),
        (int(total_w * 0.62), int(ph * 0.64)),
        (int(total_w * 0.82), int(ph * 0.78)),
        (total_w + pw, int(ph * 0.67)),
    ]
    draw.line(ribbon_points, fill=(255, 153, 51, 34), width=360, joint='curve')
    draw.line(ribbon_points, fill=(224, 103, 31, 28), width=46, joint='curve')

    glow = glow.filter(ImageFilter.GaussianBlur(150))
    return Image.alpha_composite(strip, glow).convert('RGB')


def source_path(spec: PlatformSpec, key: str) -> Path:
    if spec.name == 'iPhone':
        expected = IPHONE_SOURCE / f'{key}{spec.source_ext}'
        if expected.exists():
            return expected
        if key in WEBSITE_SOURCE_NAMES:
            fallback = WEBSITE_CAULDRON_SOURCE / WEBSITE_SOURCE_NAMES[key]
            if fallback.exists():
                return fallback
        return expected
    if spec.name == 'iPad':
        return IPAD_SOURCE / f'{key}{spec.source_ext}'
    return MAC_SOURCE / f'{key}{spec.source_ext}'


def render_platform(spec: PlatformSpec, icon_source: Image.Image) -> None:
    if spec.name in ('iPhone', 'iPad'):
        for shot in spec.shots:
            if shot.body:
                raise ValueError(f'{spec.name} screenshot {shot.key} must not use below-device copy')
            if len(shot.title.split()) > 8:
                raise ValueError(f'{spec.name} screenshot {shot.key} headline exceeds eight words')

    out_dir = OUT_ROOT / spec.name
    out_dir.mkdir(parents=True, exist_ok=True)
    for stale_output in out_dir.glob('*.png'):
        stale_output.unlink()

    bg = load_mobile_background(spec.bg_path, spec.canvas_size)
    strip = build_continuous_strip(bg, spec.canvas_size, len(spec.shots))

    mac_wall = Image.open(BG_MAC).convert('RGB') if spec.name == 'Mac' and BG_MAC.exists() else None

    for i, shot in enumerate(spec.shots, start=1):
        x0 = (i - 1) * spec.canvas_size[0]
        panel = strip.crop((x0, 0, x0 + spec.canvas_size[0], spec.canvas_size[1])).convert('RGB')

        shot_path = source_path(spec, shot.key)
        if spec.name == 'Mac':
            device = compose_macbook_frame(spec.frame_path, shot_path, mac_wall, spec.screen_corner_radius)
        else:
            device = compose_mobile_frame(spec.frame_path, shot_path, spec.screen_corner_radius)

        place_device(panel, device, spec.top_area, spec.bottom_area, spec.side_margin)
        draw_copy(panel, shot, spec, i, icon_source)

        out_path = out_dir / f'{i:02d}_{shot.key}.png'
        panel.save(out_path, format='PNG', optimize=True)
        print(f'wrote {out_path}')


def write_sequence_preview(spec: PlatformSpec) -> None:
    platform = spec.name
    files = [
        OUT_ROOT / platform / f'{index:02d}_{shot.key}.png'
        for index, shot in enumerate(spec.shots, start=1)
    ]
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
    qa_dir = OUT_ROOT / 'qa'
    qa_dir.mkdir(parents=True, exist_ok=True)
    preview = qa_dir / f'{platform.lower()}_sequence_contact_sheet.png'
    strip.save(full, format='PNG', optimize=True)
    strip.resize((strip.width // 4, strip.height // 4), Image.Resampling.LANCZOS).save(
        preview, format='PNG', optimize=True
    )
    print(f'wrote {full}')
    print(f'wrote {preview}')


def write_iphone_65_outputs(spec: PlatformSpec) -> None:
    """Derive the required 6.5-inch set from the approved 6.9-inch composition."""
    out_dir = OUT_ROOT / 'iPhone-6.5'
    out_dir.mkdir(parents=True, exist_ok=True)
    for stale_output in out_dir.glob('*.png'):
        stale_output.unlink()

    for index, shot in enumerate(spec.shots, start=1):
        source = OUT_ROOT / spec.name / f'{index:02d}_{shot.key}.png'
        output = out_dir / source.name
        fit_cover(Image.open(source).convert('RGB'), (1284, 2778)).save(
            output,
            format='PNG',
            optimize=True,
        )
        print(f'wrote {output}')


def main() -> None:
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    icon_path = ICON_PATH
    if not icon_path.exists():
        icon_path = ROOT.parent / 'CauldronIcon.png'
    icon = Image.open(icon_path).convert('RGBA')

    for spec in SPECS:
        if spec.name == 'iPhone' and not IPHONE_SOURCE.exists():
            spec = PlatformSpec(
                name=spec.name,
                canvas_size=spec.canvas_size,
                top_area=spec.top_area,
                bottom_area=spec.bottom_area,
                side_margin=spec.side_margin,
                title_size=spec.title_size,
                body_size=spec.body_size,
                text_left_margin=spec.text_left_margin,
                icon_size_first=spec.icon_size_first,
                bg_path=spec.bg_path,
                frame_path=spec.frame_path,
                screen_corner_radius=spec.screen_corner_radius,
                source_ext=spec.source_ext,
                shots=IPHONE_FALLBACK_SHOTS,
            )

        missing_sources = [source_path(spec, shot.key) for shot in spec.shots if not source_path(spec, shot.key).exists()]
        if missing_sources:
            print(f'skipping {spec.name}: missing {missing_sources[0]}')
            continue

        render_platform(spec, icon)
        write_sequence_preview(spec)
        if spec.name == 'iPhone':
            write_iphone_65_outputs(spec)

    print(f'Done. Output root: {OUT_ROOT}')


if __name__ == '__main__':
    main()
