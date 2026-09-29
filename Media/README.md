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
1. **`Runalyst_AppPreview_1290x2796.mp4`** (2.4 MB)
   * Target: iPhone 6.9" & 6.7" Super Retina Displays (iPhone 16 Pro Max, 15 Pro Max, 14 Pro Max)
2. **`Runalyst_AppPreview_886x1920.mp4`** (1.6 MB)
   * Target: Universal tall aspect ratio accepted across all modern iPhones
3. **`raw_tour.mp4`** (9.9 MB)
   * Uncompressed capture straight from the simulator display

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
1. **`Runalyst_Promo_9x16.mp4`** (1080 × 1920, 4.4 MB)
   * Target: Instagram Reels, TikTok, YouTube Shorts, Apple Search Ads
2. **`Runalyst_Promo_16x9.mp4`** (1920 × 1080, 2.8 MB)
   * Target: Twitter/X, Product Hunt, YouTube Landscape, Website Hero

---

## 3. App Store Presentation Screenshot Carousel
Location: `Media/Screenshots/AppStore/`

High-resolution framed device cards (**1290 × 2796**) ready for App Store Connect product page upload:
1. **`01_Intelligent_Biometrics.png`** (551 KB)
   * Headline: *Intelligent Running Biometrics*
   * Subtitle: *Live cadence deltas & 30-day relative baselines*
2. **`02_AI_Coaching.png`** (573 KB)
   * Headline: *On-Device AI Coaching*
   * Subtitle: *Apple FoundationModels guidance tailored to fatigue*
3. **`03_Targeted_Drills.png`** (496 KB)
   * Headline: *Targeted Form Drills*
   * Subtitle: *Prescriptive cadence pyramids & active recovery*
4. **`04_Longitudinal_Progression.png`** (393 KB)
   * Headline: *Longitudinal Progression*
   * Subtitle: *Track efficiency factor gains and cadence over time*
5. **`05_HealthKit_Privacy.png`** (456 KB)
   * Headline: *100% Private & HealthKit-Native*
   * Subtitle: *Zero cloud tracking. Seamless Apple Watch sync.*

---

## Automation Scripts
* `generate_app_store_screenshots.py` — Re-renders all screenshot presentation cards with custom fonts, device frames, and ambient lighting.
* `generate_promo_video.py` — Renders motion frames and compiles both 9:16 vertical and 16:9 landscape marketing videos without audio.
