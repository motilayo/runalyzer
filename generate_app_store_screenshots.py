import os
from PIL import Image, ImageDraw, ImageFont

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

def frame_screenshot(screenshot_path, scale_factor=0.86, corner_radius=68):
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
    
    # Minimalist sleek bezel border for device framing against black
    border_draw = ImageDraw.Draw(framed)
    border_draw.rounded_rectangle([0, 0, target_w, target_h], radius=corner_radius, outline=(255, 255, 255, 75), width=3)
    border_draw.rounded_rectangle([2, 2, target_w - 2, target_h - 2], radius=corner_radius - 2, outline=(0, 0, 0, 160), width=2)
    
    return framed

def render_card(title, subtitle, screenshot_path, output_filename):
    # Pure solid black background
    bg = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 255))
    draw = ImageDraw.Draw(bg)
    
    # 1. Main Title (White)
    font_title = get_font(72, bold=True)
    tb_title = draw.textbbox((0, 0), title, font=font_title)
    title_w = tb_title[2] - tb_title[0]
    title_x = (WIDTH - title_w) // 2
    title_y = 160
    draw.text((title_x, title_y), title, fill=(255, 255, 255, 255), font=font_title)
    
    # 2. Subtitle (White / Soft White)
    font_sub = get_font(38, bold=False)
    tb_sub = draw.textbbox((0, 0), subtitle, font=font_sub)
    sub_w = tb_sub[2] - tb_sub[0]
    sub_x = (WIDTH - sub_w) // 2
    sub_y = title_y + 94
    draw.text((sub_x, sub_y), subtitle, fill=(230, 230, 235, 255), font=font_sub)
    
    # 3. Framed Screenshot
    framed = frame_screenshot(screenshot_path, scale_factor=0.86, corner_radius=68)
    fw, fh = framed.size
    fx = (WIDTH - fw) // 2
    fy = sub_y + 85
    
    bg.paste(framed, (fx, fy), mask=framed)
    
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
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_dashboard.png",
        "output": "01_Intelligent_Biometrics.png",
    },
    {
        "title": "On-Device AI Coaching",
        "subtitle": "Apple FoundationModels guidance tailored to fatigue",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_run_detail.png",
        "output": "02_AI_Coaching.png",
    },
    {
        "title": "Targeted Form Drills",
        "subtitle": "Structured phase breakdown & Apple Watch export",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_drill_readout.png",
        "output": "03_Targeted_Drills.png",
    },
    {
        "title": "Biomechanical Form Analysis",
        "subtitle": "Vertical bounce, ground contact time & overstride alerts",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_biomechanics.png",
        "output": "04_Biomechanical_Analysis.png",
    },
    {
        "title": "Curated Pre-Run Drills",
        "subtitle": "Customizable durations, workout phases & haptic cues",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_drills.png",
        "output": "05_PreRun_Library.png",
    },
    {
        "title": "Longitudinal Progression",
        "subtitle": "Track efficiency factor gains and cadence over time",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_progression.png",
        "output": "06_Longitudinal_Progression.png",
    },
    {
        "title": "100% Private & HealthKit-Native",
        "subtitle": "Zero cloud tracking. Seamless Apple Watch sync.",
        "screenshot": "/Users/motilayo/workspace/runalyzer/Media/Screenshots/iPhone_Raw/screen_settings.png",
        "output": "07_HealthKit_Privacy.png",
    }
]

for c in cards:
    render_card(c["title"], c["subtitle"], c["screenshot"], c["output"])
