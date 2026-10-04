import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUTPUT_DIR_2048 = "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPad_2048x2732"
OUTPUT_DIR_2064 = "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPad_2064x2752"
os.makedirs(OUTPUT_DIR_2048, exist_ok=True)
os.makedirs(OUTPUT_DIR_2064, exist_ok=True)

# Base iPad 12.9" Specification: 2048 x 2732
WIDTH = 2048
HEIGHT = 2732

FONT_HEAD_BOLD = "/System/Library/Fonts/SFNS.ttf"
FONT_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"

def get_font(size, bold=True):
    path = FONT_HEAD_BOLD if bold else "/System/Library/Fonts/HelveticaNeue.ttc"
    try:
        return ImageFont.truetype(path, size)
    except:
        return ImageFont.load_default()

def create_gradient_bg(color1, color2, glow_color, glow_center, w=WIDTH, h=HEIGHT):
    img = Image.new("RGBA", (w, h), color1)
    draw = ImageDraw.Draw(img)
    
    # Linear base gradient
    for y in range(h):
        ratio = y / h
        r = int(color1[0] * (1 - ratio) + color2[0] * ratio)
        g = int(color1[1] * (1 - ratio) + color2[1] * ratio)
        b = int(color1[2] * (1 - ratio) + color2[2] * ratio)
        draw.line([(0, y), (w, y)], fill=(r, g, b, 255))
        
    # Radial Glow overlay
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    gx, gy = glow_center
    max_radius = 1200
    for r in range(max_radius, 0, -30):
        alpha = int((1.0 - (r / max_radius) ** 1.8) * glow_color[3])
        if alpha > 0:
            glow_draw.ellipse(
                [gx - r, gy - r, gx + r, gy + r],
                fill=(glow_color[0], glow_color[1], glow_color[2], alpha)
            )
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    img = Image.alpha_composite(img, glow)
    return img

def frame_device(screen_path, target_width=1560, corner_radius=52):
    src = Image.open(screen_path).convert("RGBA")
    sw, sh = src.size
    scale = target_width / sw
    target_height = int(sh * scale)
    src_scaled = src.resize((target_width, target_height), Image.Resampling.LANCZOS)
    
    # Rounded corners mask for device bezel
    mask = Image.new("L", (target_width, target_height), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, target_width, target_height], radius=corner_radius, fill=255)
    
    framed = Image.new("RGBA", (target_width, target_height), (0, 0, 0, 0))
    framed.paste(src_scaled, (0, 0), mask=mask)
    
    # Bezel border
    border_draw = ImageDraw.Draw(framed)
    border_draw.rounded_rectangle([0, 0, target_width, target_height], radius=corner_radius, outline=(255, 255, 255, 45), width=4)
    border_draw.rounded_rectangle([2, 2, target_width - 2, target_height - 2], radius=corner_radius - 2, outline=(0, 0, 0, 160), width=3)
    
    # Deep ambient drop shadow
    pad = 80
    sw_canvas = target_width + pad * 2
    sh_canvas = target_height + pad * 2
    shadow_img = Image.new("RGBA", (sw_canvas, sh_canvas), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_img)
    s_draw.rounded_rectangle(
        [pad + 16, pad + 32, pad + target_width - 16, pad + target_height + 32],
        radius=corner_radius,
        fill=(0, 0, 0, 210)
    )
    shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(52))
    shadow_img.paste(framed, (pad, pad), mask=framed)
    return shadow_img

def render_ipad_card(title, subtitle, tag, screen_path, output_filename, glow_color, bg_gradient):
    bg = create_gradient_bg(bg_gradient[0], bg_gradient[1], glow_color, (WIDTH // 2, 750))
    draw = ImageDraw.Draw(bg)
    
    # 1. Tag pill
    font_tag = get_font(36, bold=True)
    tag_text = tag.upper()
    tb = draw.textbbox((0, 0), tag_text, font=font_tag)
    tw = tb[2] - tb[0]
    th = tb[3] - tb[1]
    
    pill_w = tw + 52
    pill_h = th + 26
    pill_x = (WIDTH - pill_w) // 2
    pill_y = 110
    
    draw.rounded_rectangle(
        [pill_x, pill_y, pill_x + pill_w, pill_y + pill_h],
        radius=pill_h // 2,
        fill=(255, 255, 255, 28),
        outline=(255, 255, 255, 65),
        width=2
    )
    draw.text((pill_x + 26, pill_y + 11), tag_text, fill=(0, 230, 200, 255), font=font_tag)
    
    # 2. Main Title
    font_title = get_font(88, bold=True)
    tb_title = draw.textbbox((0, 0), title, font=font_title)
    title_w = tb_title[2] - tb_title[0]
    title_x = (WIDTH - title_w) // 2
    title_y = pill_y + pill_h + 34
    draw.text((title_x, title_y), title, fill=(255, 255, 255, 255), font=font_title)
    
    # 3. Subtitle
    font_sub = get_font(44, bold=False)
    tb_sub = draw.textbbox((0, 0), subtitle, font=font_sub)
    sub_w = tb_sub[2] - tb_sub[0]
    sub_x = (WIDTH - sub_w) // 2
    sub_y = title_y + 104
    draw.text((sub_x, sub_y), subtitle, fill=(185, 195, 215, 230), font=font_sub)
    
    # 4. Framed Screen
    framed = frame_device(screen_path, target_width=1560, corner_radius=52)
    fw, fh = framed.size
    fx = (WIDTH - fw) // 2
    fy = sub_y + 70
    
    bg.paste(framed, (fx, fy), mask=framed)
    
    # Save 2048 x 2732 (12.9" iPad Pro)
    out_2048 = os.path.join(OUTPUT_DIR_2048, output_filename)
    bg_rgb = bg.convert("RGB")
    bg_rgb.save(out_2048, "PNG", quality=98)
    
    # Save 2064 x 2752 (13" iPad Pro M4)
    out_2064 = os.path.join(OUTPUT_DIR_2064, output_filename)
    bg_2064 = bg_rgb.resize((2064, 2752), Image.Resampling.LANCZOS)
    bg_2064.save(out_2064, "PNG", quality=98)
    
    print(f"Generated 2048x2732: {out_2048}")
    print(f"Generated 2064x2752: {out_2064}")

cards = [
    {
        "title": "Intelligent Running Biometrics",
        "subtitle": "Live cadence deltas & 30-day relative baselines",
        "tag": "Adaptive Metrics",
        "screen": "Media/Screenshots/iPad_Raw/screen_dashboard.png",
        "output": "01_Intelligent_Biometrics.png",
        "glow": (0, 180, 255, 110),
        "bg": ((10, 14, 26), (15, 22, 42))
    },
    {
        "title": "On-Device AI Coaching",
        "subtitle": "Apple FoundationModels guidance tailored to fatigue",
        "tag": "Apple Intelligence",
        "screen": "Media/Screenshots/iPad_Raw/screen_run_detail.png",
        "output": "02_AI_Coaching.png",
        "glow": (180, 60, 255, 100),
        "bg": ((14, 10, 28), (24, 14, 46))
    },
    {
        "title": "Targeted Form Drills",
        "subtitle": "Structured phase breakdown & Apple Watch export",
        "tag": "Drill Breakdown",
        "screen": "Media/Screenshots/iPad_Raw/screen_drill_readout.png",
        "output": "03_Targeted_Drills.png",
        "glow": (0, 220, 140, 100),
        "bg": ((8, 22, 22), (12, 34, 34))
    },
    {
        "title": "Biomechanical Form Analysis",
        "subtitle": "Vertical bounce, ground contact time & overstride alerts",
        "tag": "Running Kinematics",
        "screen": "Media/Screenshots/iPad_Raw/screen_biomechanics.png",
        "output": "04_Biomechanical_Analysis.png",
        "glow": (255, 120, 40, 105),
        "bg": ((28, 14, 10), (44, 20, 14))
    },
    {
        "title": "Curated Pre-Run Drills",
        "subtitle": "Customizable durations, workout phases & haptic cues",
        "tag": "Drill Library",
        "screen": "Media/Screenshots/iPad_Raw/screen_drills.png",
        "output": "05_PreRun_Library.png",
        "glow": (0, 210, 255, 110),
        "bg": ((10, 20, 32), (14, 32, 48))
    },
    {
        "title": "Longitudinal Progression",
        "subtitle": "Track efficiency factor gains and cadence over time",
        "tag": "Deep Analytics",
        "screen": "Media/Screenshots/iPad_Raw/screen_progression.png",
        "output": "06_Longitudinal_Progression.png",
        "glow": (0, 210, 255, 110),
        "bg": ((10, 18, 32), (16, 28, 50))
    },
    {
        "title": "100% Private & HealthKit-Native",
        "subtitle": "Zero cloud tracking. Seamless Apple Watch sync.",
        "tag": "Privacy First",
        "screen": "Media/Screenshots/iPad_Raw/screen_settings.png",
        "output": "07_HealthKit_Privacy.png",
        "glow": (255, 80, 110, 95),
        "bg": ((24, 10, 18), (38, 14, 26))
    }
]

for c in cards:
    render_ipad_card(c["title"], c["subtitle"], c["tag"], c["screen"], c["output"], c["glow"], c["bg"])


