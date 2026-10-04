import os
from PIL import Image, ImageDraw, ImageFont

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
    
    # Minimalist sleek bezel border for device framing against black
    border_draw = ImageDraw.Draw(framed)
    border_draw.rounded_rectangle([0, 0, target_width, target_height], radius=corner_radius, outline=(255, 255, 255, 75), width=3)
    border_draw.rounded_rectangle([2, 2, target_width - 2, target_height - 2], radius=corner_radius - 2, outline=(0, 0, 0, 160), width=2)
    
    return framed

def render_ipad_card(title, subtitle, screen_path, output_filename):
    # Pure solid black background
    bg = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 255))
    draw = ImageDraw.Draw(bg)
    
    # 1. Main Title (White)
    font_title = get_font(92, bold=True)
    tb_title = draw.textbbox((0, 0), title, font=font_title)
    title_w = tb_title[2] - tb_title[0]
    title_x = (WIDTH - title_w) // 2
    title_y = 150
    draw.text((title_x, title_y), title, fill=(255, 255, 255, 255), font=font_title)
    
    # 2. Subtitle (White / Soft White)
    font_sub = get_font(46, bold=False)
    tb_sub = draw.textbbox((0, 0), subtitle, font=font_sub)
    sub_w = tb_sub[2] - tb_sub[0]
    sub_x = (WIDTH - sub_w) // 2
    sub_y = title_y + 115
    draw.text((sub_x, sub_y), subtitle, fill=(230, 230, 235, 255), font=font_sub)
    
    # 3. Framed Screen
    framed = frame_device(screen_path, target_width=1560, corner_radius=52)
    fw, fh = framed.size
    fx = (WIDTH - fw) // 2
    fy = sub_y + 90
    
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
        "screen": "Media/Screenshots/iPad_Raw/screen_dashboard.png",
        "output": "01_Intelligent_Biometrics.png",
    },
    {
        "title": "On-Device AI Coaching",
        "subtitle": "Apple FoundationModels guidance tailored to fatigue",
        "screen": "Media/Screenshots/iPad_Raw/screen_run_detail.png",
        "output": "02_AI_Coaching.png",
    },
    {
        "title": "Targeted Form Drills",
        "subtitle": "Structured phase breakdown & Apple Watch export",
        "screen": "Media/Screenshots/iPad_Raw/screen_drill_readout.png",
        "output": "03_Targeted_Drills.png",
    },
    {
        "title": "Biomechanical Form Analysis",
        "subtitle": "Vertical bounce, ground contact time & overstride alerts",
        "screen": "Media/Screenshots/iPad_Raw/screen_biomechanics.png",
        "output": "04_Biomechanical_Analysis.png",
    },
    {
        "title": "Curated Pre-Run Drills",
        "subtitle": "Customizable durations, workout phases & haptic cues",
        "screen": "Media/Screenshots/iPad_Raw/screen_drills.png",
        "output": "05_PreRun_Library.png",
    },
    {
        "title": "Longitudinal Progression",
        "subtitle": "Track efficiency factor gains and cadence over time",
        "screen": "Media/Screenshots/iPad_Raw/screen_progression.png",
        "output": "06_Longitudinal_Progression.png",
    },
    {
        "title": "100% Private & HealthKit-Native",
        "subtitle": "Zero cloud tracking. Seamless Apple Watch sync.",
        "screen": "Media/Screenshots/iPad_Raw/screen_settings.png",
        "output": "07_HealthKit_Privacy.png",
    }
]

for c in cards:
    render_ipad_card(c["title"], c["subtitle"], c["screen"], c["output"])
