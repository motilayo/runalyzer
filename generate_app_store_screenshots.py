import os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUTPUT_DIR = "/Users/motilayo/workspace/runalyzer/Media/Screenshots/AppStore"
os.makedirs(OUTPUT_DIR, exist_ok=True)

# Target App Store Connect Specifications:
# 6.7" / 6.5" Display: 1284 x 2778 (or 1242 x 2688)
WIDTH = 1284
HEIGHT = 2778

# Load fonts
FONT_HEAD_BOLD = "/System/Library/Fonts/SFNS.ttf"
FONT_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"

def get_font(size, bold=True):
    path = FONT_HEAD_BOLD if bold else "/System/Library/Fonts/HelveticaNeue.ttc"
    try:
        return ImageFont.truetype(path, size)
    except:
        return ImageFont.load_default()

def create_gradient_bg(color1, color2, glow_color, glow_center):
    img = Image.new("RGBA", (WIDTH, HEIGHT), color1)
    draw = ImageDraw.Draw(img)
    
    # Linear base gradient
    for y in range(HEIGHT):
        ratio = y / HEIGHT
        r = int(color1[0] * (1 - ratio) + color2[0] * ratio)
        g = int(color1[1] * (1 - ratio) + color2[1] * ratio)
        b = int(color1[2] * (1 - ratio) + color2[2] * ratio)
        draw.line([(0, y), (WIDTH, y)], fill=(r, g, b, 255))
        
    # Radial Glow overlay
    glow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    gx, gy = glow_center
    max_radius = 800
    for r in range(max_radius, 0, -25):
        alpha = int((1.0 - (r / max_radius) ** 1.8) * glow_color[3])
        if alpha > 0:
            glow_draw.ellipse(
                [gx - r, gy - r, gx + r, gy + r],
                fill=(glow_color[0], glow_color[1], glow_color[2], alpha)
            )
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    img = Image.alpha_composite(img, glow)
    return img

def frame_screenshot(screenshot_path, scale_factor=0.88, corner_radius=72):
    src = Image.open(screenshot_path).convert("RGBA")
    sw, sh = src.size
    
    target_w = int(sw * scale_factor)
    target_h = int(sh * scale_factor)
    src_scaled = src.resize((target_w, target_h), Image.Resampling.LANCZOS)
    
    # Rounded corners mask
    mask = Image.new("L", (target_w, target_h), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, target_w, target_h], radius=corner_radius, fill=255)
    
    # Create framed screen
    framed = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    framed.paste(src_scaled, (0, 0), mask=mask)
    
    # Bezel border
    border_draw = ImageDraw.Draw(framed)
    border_draw.rounded_rectangle([0, 0, target_w, target_h], radius=corner_radius, outline=(255, 255, 255, 40), width=4)
    border_draw.rounded_rectangle([2, 2, target_w - 2, target_h - 2], radius=corner_radius - 2, outline=(0, 0, 0, 160), width=3)
    
    # Shadow canvas
    padding = 80
    shadow_w = target_w + padding * 2
    shadow_h = target_h + padding * 2
    shadow_img = Image.new("RGBA", (shadow_w, shadow_h), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_img)
    s_draw.rounded_rectangle(
        [padding + 8, padding + 24, padding + target_w - 8, padding + target_h + 24],
        radius=corner_radius,
        fill=(0, 0, 0, 180)
    )
    shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(38))
    
    # Paste framed screen over shadow
    shadow_img.paste(framed, (padding, padding), mask=framed)
    return shadow_img

def render_card(title, subtitle, tag, screenshot_path, output_filename, glow_color, bg_gradient):
    bg = create_gradient_bg(bg_gradient[0], bg_gradient[1], glow_color, (WIDTH // 2, 700))
    draw = ImageDraw.Draw(bg)
    
    # 1. Tag pill
    font_tag = get_font(32, bold=True)
    tag_text = tag.upper()
    tb = draw.textbbox((0, 0), tag_text, font=font_tag)
    tw = tb[2] - tb[0]
    th = tb[3] - tb[1]
    
    pill_w = tw + 48
    pill_h = th + 24
    pill_x = (WIDTH - pill_w) // 2
    pill_y = 160
    
    draw.rounded_rectangle(
        [pill_x, pill_y, pill_x + pill_w, pill_y + pill_h],
        radius=pill_h // 2,
        fill=(255, 255, 255, 25),
        outline=(255, 255, 255, 60),
        width=2
    )
    draw.text((pill_x + 24, pill_y + 10), tag_text, fill=(0, 230, 200, 255), font=font_tag)
    
    # 2. Main Title (can be 2 lines if needed)
    font_title = get_font(68, bold=True)
    tb_title = draw.textbbox((0, 0), title, font=font_title)
    title_w = tb_title[2] - tb_title[0]
    title_x = (WIDTH - title_w) // 2
    title_y = pill_y + pill_h + 44
    draw.text((title_x, title_y), title, fill=(255, 255, 255, 255), font=font_title)
    
    # 3. Subtitle
    font_sub = get_font(36, bold=False)
    tb_sub = draw.textbbox((0, 0), subtitle, font=font_sub)
    sub_w = tb_sub[2] - tb_sub[0]
    sub_x = (WIDTH - sub_w) // 2
    sub_y = title_y + 84
    draw.text((sub_x, sub_y), subtitle, fill=(185, 195, 215, 230), font=font_sub)
    
    # 4. Framed Screenshot
    framed = frame_screenshot(screenshot_path, scale_factor=0.86, corner_radius=68)
    fw, fh = framed.size
    fx = (WIDTH - fw) // 2
    fy = sub_y + 70
    
    bg.paste(framed, (fx, fy), mask=framed)
    
    # Save output
    # Save primary 1284 x 2778 (6.7" / 6.9" display)
    out_path = os.path.join(OUTPUT_DIR, output_filename)
    bg_rgb = bg.convert("RGB")
    bg_rgb.save(out_path, "PNG", quality=98)
    print(f"Rendered 1284x2778: {out_path}")

    # Save 1242 x 2688 (6.5" display)
    out_1242_dir = "/Users/motilayo/workspace/runalyzer/Media/Screenshots/AppStore_1242x2688"
    os.makedirs(out_1242_dir, exist_ok=True)
    out_1242 = os.path.join(out_1242_dir, output_filename)
    bg_1242 = bg_rgb.resize((1242, 2688), Image.Resampling.LANCZOS)
    bg_1242.save(out_1242, "PNG", quality=98)

    # Save to website assets
    web_dir = "/Users/motilayo/workspace/runalyzer/website/assets/images"
    os.makedirs(web_dir, exist_ok=True)
    out_web = os.path.join(web_dir, output_filename)
    bg_rgb.save(out_web, "PNG", quality=98)

cards = [
    {
        "title": "Intelligent Running Biometrics",
        "subtitle": "Live cadence deltas & 30-day relative baselines",
        "tag": "Adaptive Metrics",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_dashboard.png",
        "output": "01_Intelligent_Biometrics.png",
        "glow": (0, 180, 255, 110),
        "bg": ((10, 14, 26), (15, 22, 42))
    },
    {
        "title": "On-Device AI Coaching",
        "subtitle": "Apple FoundationModels guidance tailored to fatigue",
        "tag": "Apple Intelligence",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_run_detail.png",
        "output": "02_AI_Coaching.png",
        "glow": (180, 60, 255, 100),
        "bg": ((14, 10, 28), (24, 14, 46))
    },
    {
        "title": "Targeted Form Drills",
        "subtitle": "Structured phase breakdown & Apple Watch export",
        "tag": "Drill Breakdown",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_drill_readout.png",
        "output": "03_Targeted_Drills.png",
        "glow": (0, 220, 140, 100),
        "bg": ((8, 22, 22), (12, 34, 34))
    },
    {
        "title": "Biomechanical Form Analysis",
        "subtitle": "Vertical bounce, ground contact time & overstride alerts",
        "tag": "Running Kinematics",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_biomechanics.png",
        "output": "04_Biomechanical_Analysis.png",
        "glow": (255, 120, 40, 105),
        "bg": ((28, 14, 10), (44, 20, 14))
    },
    {
        "title": "Curated Pre-Run Drills",
        "subtitle": "Customizable durations, workout phases & haptic cues",
        "tag": "Drill Library",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_drills.png",
        "output": "05_PreRun_Library.png",
        "glow": (0, 210, 255, 110),
        "bg": ((10, 20, 32), (14, 32, 48))
    },
    {
        "title": "Longitudinal Progression",
        "subtitle": "Track efficiency factor gains and cadence over time",
        "tag": "Deep Analytics",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_progression.png",
        "output": "06_Longitudinal_Progression.png",
        "glow": (0, 210, 255, 110),
        "bg": ((10, 18, 32), (16, 28, 50))
    },
    {
        "title": "100% Private & HealthKit-Native",
        "subtitle": "Zero cloud tracking. Seamless Apple Watch sync.",
        "tag": "Privacy First",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_settings.png",
        "output": "07_HealthKit_Privacy.png",
        "glow": (255, 80, 110, 95),
        "bg": ((24, 10, 18), (38, 14, 26))
    }
]

for c in cards:
    render_card(c["title"], c["subtitle"], c["tag"], c["screenshot"], c["output"], c["glow"], c["bg"])


