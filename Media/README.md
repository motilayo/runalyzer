# Runalyst Media & App Store Assets

This directory contains the production-ready promotional media assets, App Store Preview videos, and marketing presentation cards for **Runalyst** ([App Store Listing](https://apps.apple.com/ca/app/runalyst/id6801875079)).

---

## 1. App Store App Previews (Apple Review Compliant)
Location: `Media/AppStorePreviews/`

Meets all [Apple App Store Preview Specifications](https://developer.apple.com/app-store/app-previews/):
* **Duration:** 26.5 seconds (within the 15.0 – 30.0s requirement)
* **Framerate:** 30 fps CFR (Constant Frame Rate)
* **Video Codec:** H.264 High Profile Level 4.2, `yuv420p`
* **Audio Track:** AAC 44.1 kHz Stereo (required by App Store Connect validator)
* **Content:** Real on-device application walkthrough (Dashboard -> Run Details & AI Analysis -> Pre-Run Drills Library -> Cadence Progression)

### Deliverables:
1. **`Runalyst_AppPreview_1290x2796.mp4`** (1.5 MB)
   * Target: iPhone 6.9" & 6.7" Super Retina Displays (iPhone 16 Pro Max, 15 Pro Max, 14 Pro Max)
2. **`Runalyst_AppPreview_886x1920.mp4`** (1.1 MB)
   * Target: Universal tall aspect ratio accepted across all modern iPhones
3. **`Runalyst_AppPreview_iPad_1200x1600.mp4`** (1.1 MB)
   * Target: iPad Standard Scaled Preview (`1200 × 1600 px`) for iPad 12.9" and 13" displays
4. **`Runalyst_AppPreview_iPad_2048x2732.mp4`** (1.9 MB)
   * Target: iPad 12.9" Display slot in App Store Connect (`2048 × 2732 px`)
5. **`Runalyst_AppPreview_iPad_2064x2752.mp4`** (1.9 MB)
   * Target: iPad 13" Display slot in App Store Connect (`2064 × 2752 px`)

---

## 2. Marketing & Social Promo Videos
Location: `Media/PromoVideo/`

Designed for social launches, landing page hero backgrounds, Product Hunt, and advertisements:
* High-tempo cuts with kinetic typography overlays
* Highlights key differentiators:
  * *Intelligent Running Biometrics (VO2 Max, 30-day relative baselines)*
  * *On-Device AI Coaching (Apple FoundationModels)*
  * *Targeted Form Drills (Cadence Pyramids, Active Recovery)*
  * *Longitudinal Progression (Efficiency Factor curves)*
  * *100% Private & HealthKit-Native*

### Deliverables:
1. **`Runalyst_Promo_9x16.mp4`** (1080 × 1920, 5.8 MB)
   * Target: Instagram Reels, TikTok, YouTube Shorts, Apple Search Ads
2. **`Runalyst_Promo_16x9.mp4`** (1920 × 1080, 4.1 MB)
   * Target: Twitter/X, Product Hunt, YouTube Landscape, Website Hero

---

## 3. App Store Presentation Screenshot Carousel
Location: `Media/Screenshots/AppStore/` (and `Media/Screenshots/AppStore_1242x2688/`)

Meets Apple App Store Connect specifications for 6.7" and 6.5" displays:
* Primary Target (**1284 × 2778**): `Media/Screenshots/AppStore/`
* Alternative Target (**1242 × 2688**): `Media/Screenshots/AppStore_1242x2688/`

Ready for direct App Store Connect product page upload:
1. **`01_Intelligent_Biometrics.png`**
   * Headline: *Intelligent Running Biometrics*
   * Subtitle: *Live cadence deltas & 30-day relative baselines*
2. **`02_AI_Coaching.png`**
   * Headline: *On-Device AI Coaching*
   * Subtitle: *Apple FoundationModels guidance tailored to fatigue*
3. **`03_Targeted_Drills.png`**
   * Headline: *Targeted Form Drills*
   * Subtitle: *Prescriptive cadence pyramids & active recovery*
4. **`04_Longitudinal_Progression.png`**
   * Headline: *Longitudinal Progression*
   * Subtitle: *Track efficiency factor gains and cadence over time*
5. **`05_HealthKit_Privacy.png`**
   * Headline: *100% Private & HealthKit-Native*
   * Subtitle: *Zero cloud tracking. Seamless Apple Watch sync.*

---

## 4. iPad App Store Presentation Screenshot Carousel (12.9" & 13")
Location:
* `Media/Screenshots/iPad_2048x2732/` (Standard 12.9" iPad Pro specification: **2048 × 2732 px**)
* `Media/Screenshots/iPad_2064x2752/` (13" iPad Pro M4 specification: **2064 × 2752 px**)

Features high-resolution tablet presentation cards framing the app UI with category badges, bold typography, and ambient lighting. Ready for direct upload to the App Store Connect iPad 12.9" / 13" display slots:
1. `01_Intelligent_Biometrics.png`
2. `02_AI_Coaching.png`
3. `03_Targeted_Drills.png`
4. `04_Longitudinal_Progression.png`
5. `05_HealthKit_Privacy.png`

---

## Automation Scripts
* `generate_app_store_screenshots.py` — Renders iPhone screenshot presentation cards (1284×2778 and 1242×2688).
* `generate_ipad_screenshots.py` — Renders iPad screenshot presentation cards (2048×2732 and 2064×2752).
* `generate_promo_video.py` — Renders motion frames and compiles both 9:16 vertical and 16:9 landscape marketing videos without audio.
