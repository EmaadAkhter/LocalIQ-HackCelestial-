# LocalIQ Design System

> **Visual Source of Truth:** Stitch Project `projects/17179764269708401757`
> **Project Title:** LocalIQ: AI Mumbai Experience App
> **Device Targets:** Responsive Mobile (iOS/Android Viewports) & Ultra-Wide Desktop (1280px – 2560px)
> **Brand Position:** "Discover Local. Smarter." — An unhurried, authentic neighborhood intelligence and cultural discovery platform tailored to Mumbai's kinetic energy and storied heritage.

---

## 1. Brand Identity & Visual North Star

### 1.1 The Creative North Star: "The Warm Editorial Sanctuary"
LocalIQ moves away from aggressive corporate gradients, cold dark-mode crypto aesthetics, and clinical travel lists. Instead, it embodies **The Warm Editorial Sanctuary** — a tactile, magazine-grade visual publication that respects the cadence of Mumbai.

- **Organic Asymmetry & Tonal Depth:** Layouts embrace varied visual rhythms, oversized editorial typography, staggered card heights, and generous breathing room.
- **The "No-Divider" Rule:** Structural separation is achieved exclusively through background tone shifts and spatial nesting—never through harsh, opaque 1px separator lines.
- **Atmospheric Warmth:** Drawing inspiration from Marine Drive twilights, terracotta street pottery in Kumbharwada, colonial stone arcades of Horniman Circle, and warm cutting chai.
- **Official Brand Emblem:** Charcoal Walnut Gateway of India silhouette encased inside a Mumbai Sunset Coral location pin with soft sand water ripples (free of cold blues or purples).

---

## 2. Color Palette & Token Architecture

The design system is built upon a dual-tier semantic token architecture derived from Google Material Design 3 and tailored for warm ambient readability.

### 2.1 Primary & Accent Colors
| Token Name | Hex Code | Semantic Role & Usage |
| :--- | :--- | :--- |
| `primary` | `#B52603` | Primary affirmative action, active route highlight, key brand headers |
| `primary-container` | `#FF5A36` | **Mumbai Sunset Coral** — Primary CTA buttons, interactive active chips, map pins |
| `primary-hover` | `#E44E2C` | Active/hover state for primary container surfaces |
| `primary-subtle` | `#FFF0ED` | Soft coral background tint for badge highlights and active pill halos |
| `primary-fixed` | `#FFDAD2` | Selection tint and high-contrast ambient badge backing |
| `primary-fixed-dim` | `#FFB4A3` | Secondary coral highlight, inverse primary link |
| `on-primary` | `#FFFFFF` | Text/icons placed over `primary` or `primary-container` |
| `on-primary-container`| `#5A0C00` | Deep burnt umber for high-contrast text on soft coral surfaces |
| `on-primary-fixed` | `#3D0600` | Darkest contrast text on fixed primary chips |
| `on-primary-fixed-variant` | `#8C1900` | Subtle contrast metadata over fixed primary surfaces |

### 2.2 Secondary & Neutral Stone Tokens
| Token Name | Hex Code | Semantic Role & Usage |
| :--- | :--- | :--- |
| `secondary` | `#615E57` | Warm Charcoal Slate — Body copy secondary, distance metadata, subtle icons |
| `secondary-container`| `#E7E2D9` | **Sand / Warm Pebble** — Filter pill default background, category badges |
| `secondary-fixed` | `#E7E2D9` | Fixed tonal chips and ambient badge surfaces |
| `secondary-fixed-dim`| `#CBC6BD` | Inactive chip borders, subtle disabled fills |
| `on-secondary` | `#FFFFFF` | Contrasting white text over solid secondary elements |
| `on-secondary-container`| `#67645D` | Medium charcoal text on sand container pills |
| `on-secondary-fixed` | `#1D1B16` | Deepest neutral text on secondary fixed surfaces |
| `on-secondary-fixed-variant` | `#494640` | Secondary description text on fixed container items |

### 2.3 Tertiary & Botanical Green Tokens (Affinity & Verified Status)
| Token Name | Hex Code | Semantic Role & Usage |
| :--- | :--- | :--- |
| `tertiary` | `#006D30` | **Botanical Emerald** — 90%+ match affinity, "Open Now" pulse dot, "Free" tag |
| `tertiary-container`| `#43A55D` | Verdant Mint Green — Active plan confirmation state, progress highlights |
| `tertiary-fixed` | `#95F8A7` | High-visibility affinity pill background |
| `tertiary-fixed-dim`| `#79DB8D` | Soft green badge background for "High Affinity" pill indicators |
| `on-tertiary` | `#FFFFFF` | Crisp white text on dark green indicators |
| `on-tertiary-container`| `#003313` | Deep forest text on light green containers |
| `on-tertiary-fixed` | `#00210A` | Maximum contrast text on tertiary badges |
| `on-tertiary-fixed-variant` | `#005323` | Medium green text for verified status sub-labels |

### 2.4 Surface Hierarchy & Canvas Tiers (The Warm Paper Stack)
Treat surfaces as physical sheets of fine, unbleached handmade paper layered over one another:

```
[Layer 3] surface-container-lowest (#FFFFFF)  --> Elevated Interactive Cards / Modals
[Layer 2] surface-container (#F9EBE6 / #F2ECE1)--> Nesting Group Cards / Input Fields
[Layer 1] surface-container-low (#FFF1EC / #FAF6EE) --> Section Alternations & Scrims
[Layer 0] background / surface (#FFF8F6 / #FCFAF5)  --> Foundational Canvas Base
```

| Surface Token | Hex Code | Physical / Visual Function |
| :--- | :--- | :--- |
| `background` / `surface` | `#FFF8F6` / `#FCFAF5` | Primary warm cream canvas base; eliminates eye fatigue |
| `surface-bright` | `#FFF8F6` | Floating card badges, high-key ambient highlight |
| `surface-dim` | `#E4D7D2` | Recessed areas, inactive scroll rails |
| `surface-container-lowest` | `#FFFFFF` | **Pure Card White** — Elevated actionable feed cards, search dialogs |
| `surface-container-low` | `#FFF1EC` / `#FAF6EE` | Subtle background tint for alternating content sections |
| `surface-container` | `#F9EBE6` / `#F2ECE1` | Warm terracotta/sand tint for search inputs, step bars, badge chips |
| `surface-container-high`| `#F3E5E0` | Hover states on container elements, thumbnail backdrops |
| `surface-container-highest` | `#EDE0DB` / `#E4DCD0` | Active navigation pill background, tactile keyboard shortcut badges |
| `surface-variant` | `#EDE0DB` | Inactive tab background, structural grouping blocks |

### 2.5 Text, Outline & Border Tokens
| Token Name | Hex Code / Value | Semantic Role & Usage |
| :--- | :--- | :--- |
| `on-surface` / `on-background` | `#211A17` / `#2E2724` | **Charcoal Walnut** — High-contrast primary reading text, headlines |
| `on-surface-variant` | `#5B403A` / `#6E645F` | Charcoal Muted — Body copy, subtitles, editorial quotes, icons |
| `outline` | `#8F7069` | High-contrast accessible strokes, form boundaries |
| `outline-variant` | `#E3BEB6` / `#E4DCD0` | **Sand Hairline** — Subtle 1px translucent inner borders (10%–40% opacity) |
| `inverse-surface` | `#362F2C` | Deep charcoal tooltips and dark toasts |
| `inverse-on-surface` | `#FCEEE9` | Light cream text on inverse surfaces |
| `inverse-primary` | `#FFB4A3` | Soft coral accent on dark inverse panels |

### 2.6 Error & Alert Tokens
| Token Name | Hex Code | Semantic Role & Usage |
| :--- | :--- | :--- |
| `error` | `#BA1A1A` | Validation errors, closures, critical disruptions |
| `error-container` | `#FFDAD6` | Soft blush background for error warnings |
| `on-error` | `#FFFFFF` | White text on solid red surfaces |
| `on-error-container` | `#93000A` | Deep crimson text on error container pills |

### 2.7 Foundational Dark / Night-Mode Variant Tokens
*(From the project's Cinematic Cyber-Glass baseline)*
- **Canvas Base:** `#0B0D12` (OLED foundational black)
- **Surface Layer 1:** `#0F131D` (Midnight Slate)
- **Surface Layer 2 (Raised):** `#1A1F2C` (Modal bottom sheets, elevated cards)
- **Floating Glass:** `rgba(26, 31, 44, 0.72)` paired with `backdrop-filter: blur(16px)` and `border: 1px solid rgba(255, 255, 255, 0.08)`
- **Text Primary:** `#F8FAFC`, **Text Secondary:** `#94A3B8`, **Text Muted:** `#64748B`
- **Dynamic Glow Bloom:** Tinted with Cyber Cyan (`#00E5FF` at 15% opacity, 20px blur radius)

---

## 3. Typography Hierarchy

The typography pairs the geometric authority of **Manrope** (and **Plus Jakarta Sans**) with the editorial grace of **Newsreader** and the functional clarity of **DM Sans** (and **Inter**). Machine calculations, coordinates, and telemetry utilize **JetBrains Mono**.

### 3.1 Font Families
```css
--font-display: 'Manrope', 'Plus Jakarta Sans', sans-serif;
--font-editorial: 'Newsreader', serif;
--font-body: 'DM Sans', 'Inter', sans-serif;
--font-mono: 'JetBrains Mono', monospace;
```

### 3.2 Typographic Scale Table
| Token Name | Font Family | Size | Line Height | Letter Spacing | Weight | Usage Example |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `display-hero-lg` | Manrope | 44px–76px | 0.98 (98%) | `-0.04em` | 700 / 800 | Desktop Asymmetric Hero: `"WHAT DO YOU feel like DOING?"` |
| `display-lg` | Manrope | 36px | 44px | `-0.03em` | 700 / 800 | Section Titles: `"YOU DON'T NEED A PLAN."` |
| `display-lg-mobile`| Manrope | 28px | 36px | `-0.025em` | 700 | Mobile Greeting: `"Good evening, Kabir"` |
| `headline-lg` | Manrope | 24px | 32px | `-0.02em` | 700 | Experience Detail Title, Modal Headers |
| `headline-md` | Manrope | 20px | 28px | `-0.015em` | 600 | Card Headings: `"Street food after dark"`, Section Sub-headers |
| `headline-sm` | Manrope | 18px | 24px | `-0.01em` | 600 | Compact Card Titles, Module Questions: `"What are you up for?"` |
| `title-editorial` | Newsreader | 20px | 28px | `0.0em` | 400 (Italic) | Poetic Subtitles: *"Quiet skies over the Arabian Sea tonight."* |
| `body-editorial-italic` | Newsreader | 15px | 22px | `+0.01em` | 400 (Italic) | Brand Tagline: *"Discover Local. Smarter."*, Photo Scrim Sub-captions |
| `body-lg` | DM Sans | 16px | 24px | `-0.01em` | 400 | Conversational Search Inputs, Introductory Deck Text |
| `body-md` | DM Sans | 14px | 20px | `0.0em` | 400 | Card Descriptions, Itinerary Body Copy, Default App Text |
| `body-sm` | DM Sans | 12px | 16px | `0.0em` | 400 | Timestamps, Fine Disclaimers |
| `label-lg` | DM Sans | 14px | 18px | `+0.01em` | 500 / 600 | Desktop Nav Links, Primary Buttons, Action Anchors |
| `label-md` | DM Sans | 12px | 16px | `+0.02em` | 500 / 600 | Filter Pills, Secondary Buttons, Form Field Labels |
| `label-sm` | DM Sans | 11px | 14px | `+0.03em` | 600 | Match Score Pills, Metadata Chips, Time & Cost Badges |
| `label-caps` | JetBrains Mono| 10px | 14px | `+0.08em` | 700 | Uppercase Category Badges: `COMMUNITY LED TRAIL` |
| `mono-metric` | JetBrains Mono| 14px | 18px | `-0.02em` | 600 | Transit Departure Times, GPS Coordinates, Numeric Telemetry |
| `mono-data-sm` | JetBrains Mono| 11px | 14px | `+0.02em` | 500 | Live crowd indicators, Step countdowns |

---

## 4. Spacing, Grid & Spatial System

The spatial framework is grounded in an **8dp Spatial Grid System** with a **4dp Micro-Baseline** for dense telemetry alignments.

### 4.1 Spacing Scale Tokens
| Token | REM Value | Pixel Value | Typical Application |
| :--- | :--- | :--- | :--- |
| `space-xs` | `0.25rem` | 4px | Icon-to-text gap, badge micro-padding, pulse dot offset |
| `space-sm` | `0.5rem` | 8px | Button padding-y, card item gap, chip inner horizontal gap |
| `space-md` | `1.0rem` | 16px | Card body padding, input horizontal padding, grid gutters |
| `space-lg` | `1.5rem` | 24px | Section bottom margins, hero column gap, modal internal spacing |
| `space-xl` | `2.25rem` | 36px | Major section vertical padding, page hero separation |
| `gutter` | `1.0rem` | 16px | Standard mobile grid gutter |
| `gutter-sm` | `0.5rem` | 8px | Compact pill carousel gutter |
| `margin` | `1.25rem` | 20px | Mobile screen edge padding (`px-margin`) |
| `margin-desktop` | `2.0rem` | 32px | Desktop outer screen margin (`px-8` / `px-12`) |

### 4.2 Layout Grid & Breakpoints
- **Mobile Viewport (`< 640px`):** Single fluid column, `px-margin` (20px) outer padding, bottom padding reserved for floating navigation (`pb-20` / `pb-safe` + 80px).
- **Tablet / Foldable (`640px – 1024px`):** 2-to-3 column grid, `margin: 1.5rem` (24px).
- **Desktop Grid (`1024px – 1600px+`):** 12-column asymmetric layout with `max-w-7xl` (1280px) or `max-w-[1600px]`, 24px–32px gutters.
- **Split Radar View (`xl: 1280px+`):** Dual-pane view (Sticky Interactive Map Radar on left/right at 45%–50% viewport width, scrollable filter list on alternate pane).
- **Safe-Area Insets:**
  - Header padding: `pt-safe` (`padding-top: env(safe-area-inset-top, 0px)`)
  - Floating Nav padding: `pb-safe` (`padding-bottom: env(safe-area-inset-bottom, 0px)`)
  - Minimum touch target: **48x48dp** on all interactive surfaces.

---

## 5. Border Radius & Elevation Tiers

### 5.1 Corner Radius Scale
| Radius Token | Value | Applied Components |
| :--- | :--- | :--- |
| `rounded-DEFAULT` | `0.25rem` (4px) | Data tags, status chips, drag handle bars |
| `rounded-lg` | `0.5rem` (8px) | Compact photo thumbnails (w-20 h-20), inner menu items |
| `rounded-xl` | `0.75rem` (12px) | Compact horizontal cards, filter dropdowns, modal controls |
| `rounded-2xl` | `1.0rem` (16px) | Standard Feed Experience Cards, search containers, hero imagery |
| `rounded-3xl` | `1.5rem` (24px) | Modal bottom sheet top corners, large magazine feature cards |
| `rounded-full` | `9999px` | Floating 5-tab nav bar, primary CTA buttons, filter chips, search input |

### 5.2 Elevation, Depth & Frosted Glass Architecture
Depth is primarily established via **Tonal Stacking** and frosted glassmorphism rather than heavy black drop shadows.

```css
/* Layer 1: Ambient Card Elevation */
box-shadow: 0 1px 8px rgba(46, 39, 36, 0.04);

/* Layer 2: Elevated Interactive Card / Hover */
box-shadow: 0 4px 20px -2px rgba(46, 39, 36, 0.08);

/* Layer 3: Floating Navigation Glass Bar (Top Header / Bottom Bar) */
background: rgba(255, 248, 246, 0.90);
backdrop-filter: blur(20px);
box-shadow: 0 -2px 12px rgba(46, 39, 36, 0.06);

/* Layer 4: Floating Pill Highlight Badges (Photo Scrim Overlays) */
background: rgba(255, 255, 255, 0.90);
backdrop-filter: blur(8px);
box-shadow: 0 1px 4px rgba(46, 39, 36, 0.12);

/* Ghost Border Fallback */
border: 1px solid rgba(227, 190, 182, 0.40); /* outline-variant at 40% */
```

---

## 6. Component Patterns & Interactive States

### 6.1 Buttons & Interactive CTAs
1. **Primary Pill Action (`bg-primary-container`):**
   - Background: `#FF5A36`, Text: `#FFFFFF`, Font: `label-md` / `label-lg`, Shape: `rounded-full`.
   - Dimensions: Min-height 48px, horizontal padding `px-5` / `px-6`.
   - Feedback: Tap scale `active:scale-95` / `active:scale-[0.98]`, subtle transition `duration-200`.
2. **"Add to Plan" Interactive Tile Button:**
   - Full-width card button with `bg-primary-container text-on-primary rounded-xl`.
   - On Click Interaction: Icon transitions from `add` to `check`; text changes from `"Add to plan"` to `"Added to plan"`; background shifts temporarily to `bg-tertiary-container` for 2.4s.
3. **Conversational Action Button:**
   - Inline flex button with trailing `arrow_forward` icon, `shadow-sm`, active scaling.
4. **Vibe Pills / Filter Chips:**
   - Inactive: `bg-surface-container hover:bg-surface-container-high text-on-surface rounded-full px-3.5 py-1.5`.
   - Active: `bg-primary text-on-primary shadow-sm rounded-full px-3.5 py-1.5 font-semibold`.
5. **Icon Action Buttons (44px–48px hit target):**
   - `w-11 h-11 rounded-full flex items-center justify-center text-on-surface-variant hover:text-on-surface hover:bg-surface-container transition-colors`.
   - Material Symbols icon size: 20px–24px.

### 6.2 Experience Cards & Feed Tiles
1. **Standard Vertical Experience Card:**
   - Container: `bg-surface-container-lowest rounded-2xl overflow-hidden shadow-sm flex flex-col`.
   - Imagery: 16:9 full-bleed photo (height 192px–288px), `object-cover`, hover scale `group-hover:scale-105 duration-700 ease-out`.
   - Top Badges:
     - Top-Left: Match Score Badge (`bg-surface-container-lowest/90 backdrop-blur-sm px-2.5 py-1 rounded-full flex items-center gap-1 shadow-sm` with leading filled flame or star icon).
     - Top-Right: Price Badge (`Free` or `₹400 for two`).
   - Content: Category chip (`bg-secondary-container text-on-secondary-container font-label-sm rounded-full`) + Locality + Distance (`· Colaba · 2.4 km`).
   - Title: `font-headline-sm` or `font-headline-md` in `text-on-surface`.
   - Description: `font-body-md text-on-surface-variant line-clamp-2`.
   - Footer Action: Full-width `"Add to plan"` button or `"Explore Route"` link with bookmark toggle.
2. **Compact Horizontal Card:**
   - Container: `bg-surface-container-lowest p-space-sm rounded-xl flex items-center gap-space-md shadow-sm`.
   - Thumbnail: `w-20 h-20 rounded-lg overflow-hidden shrink-0`.
   - Information: Truncated title, neighborhood tag, price indicator in bold emerald.
   - Bookmark Icon Button: Interactive toggle (`bookmark_border` to filled `bookmark` in `text-primary`).
3. **Hero Asymmetric Feature Visual Card:**
   - Container: Rounded-2xl with bottom gradient scrim (`bg-gradient-to-t from-on-surface/80 via-transparent to-transparent`).
   - Overlay Content: Top label in `text-primary-fixed`, title in `font-headline-sm text-surface-container-lowest`, italic deck text in `text-outline-variant`.

### 6.3 Conversational Search Module ("What are you up for?")
- Container: `bg-surface-container-lowest p-space-md rounded-2xl shadow-md`.
- Header: Direct question in `font-headline-sm` with trailing `explore` icon in `text-primary`.
- Search Pill: `bg-surface-container-low focus-within:bg-surface-container rounded-xl px-space-md py-3` with leading `search` icon and trailing `mic` icon for voice discovery.
- Action: Right-aligned `"Find something"` button with trailing arrow.

### 6.4 Quick Picks 4-Column Grid
- 4 tactile tiles: `Plan trip` (`edit_calendar`), `Hidden gems` (`diamond`), `Surprise me` (`casino`), `Near me` (`near_me`).
- Tile Container: `w-14 h-14 rounded-2xl bg-surface-container flex items-center justify-center text-primary group-active:scale-95 transition-transform shadow-sm`.
- Caption: `font-label-sm text-on-surface text-center`.

### 6.5 Step Sequence & Planner Progress
- Monolithic numbered steps (`01`, `02`, `03`...) rendered in bold `font-headline-sm text-primary-container`.
- Step card pill: `bg-surface-container-lowest text-on-surface rounded-xl p-space-xs shadow-sm`.
- Step title in uppercase `font-label-sm text-on-surface` with active selection summary in `text-secondary`.

### 6.6 Navigation Patterns
1. **Mobile Bottom Navigation (Floating Glass Pill):**
   - Position: Fixed bottom, `h-20` (80px), `pb-safe`, `bg-surface/95 backdrop-blur-xl shadow-[0_-2px_12px_rgba(46,39,36,0.06)]`.
   - Layout: 5 equal columns:
     - `Home` (`home`)
     - `Explore` (`explore`)
     - `Plan` (`auto_awesome`)
     - `Map` (`location_on`)
     - `Profile` (`person`)
   - Active Indicator: Active item receives `text-primary font-bold`; inactive receives `text-on-surface-variant hover:text-on-surface`.
2. **Mobile Fixed Header:**
   - Height: 64px (`h-16`), `pt-safe`, `bg-surface/90 backdrop-blur-xl`.
   - Content: Brand Emblem + Wordmark ("LocalIQ"), Location chip ("Mumbai"), Search & Notification icon buttons with primary dot indicator, circular profile avatar.
3. **Desktop Fixed Global Header:**
   - Height: 80px (`h-20`), full-width `px-8` with `bg-surface/85 backdrop-blur-md shadow-[0_1px_8px_rgba(46,39,36,0.06)]`.
   - Navigation Links: Pill-shaped group (`bg-surface-container-low/70 p-1.5 rounded-full`) containing `Discover`, `Explore Experiences`, `Plan & Itineraries`, `Map Radar`, `Group Consensus`, `Local Guides`.
   - Search: Inline pill search bar with `⌘K` keyboard shortcut badge.
   - User Section: Sign-in link, "Start Exploring" primary coral button, user profile avatar with name.
4. **Desktop Sticky Sub-Header Filter Bar:**
   - Height: 56px, `bg-surface/95 backdrop-blur-md sticky top-20 z-40 shadow-sm`.
   - Location chip with radius selector ("Bandra West, Mumbai · within 2.0 km"), horizontal scroll filter pills, view switcher button ("Split Map + List").

---

## 7. Imagery & Visual Hierarchy Guidelines

### 7.1 Photography & Color Grading Aesthetic
- **Authentic Documentary Photography:** Imagery must highlight genuine Mumbai life—weathered warehouse textures, morning sea fog, hand-crafted kulhad tea cups, colonial wooden balconies, and vibrant hand-painted murals.
- **Warm Color Grading:** Photos feature warm amber, umber, sand, and terracotta cast (vintage 35mm film mood).
- **Prohibited Aesthetics:** Cold neon cyan, generic stock photos of corporate high-rises, over-saturated tourist snapshots, or clinical white backgrounds.

### 7.2 Photographic Scrim Rules
All image cards containing overlaid typography must utilize an intentional gradient scrim:
```css
/* Bottom Scrim for Light/Dark Legibility */
background: linear-gradient(
   to top,
   rgba(33, 26, 23, 0.85) 0%,
   rgba(33, 26, 23, 0.40) 50%,
  transparent 100%
);
```

### 7.3 Visual Dominance & Hierarchy
1. **Hero Display Typographic Contrast:** Pair ultra-bold sans-serif titles with italic serif commentary (`WHAT DO YOU` in bold Manrope + `feel like` in italic Newsreader).
2. **Micro-Telemetry Dividing Lines:** Machine data (scores, km, prices) are formatted with bullet separators (`· Colaba · 2.4 km · ₹400`).
3. **Pulsing Status Dots:** Live status indicators utilize a small 6px animated pulsing green or coral dot (`w-1.5 h-1.5 rounded-full bg-tertiary animate-pulse`).

---

## 8. Screen Inventory Reference (Visual Ground Truth)

The design system is extracted directly from the active Stitch project screens:

| Screen Identifier | Screen Title | Viewport | Core Design Tokens Represented |
| :--- | :--- | :--- | :--- |
| `0501ef35d0484c369cdb2159187c15cd` | LocalIQ Home — Focused Experience | Mobile (780x3728) | Mobile header, conversational search, quick picks, feed cards, bottom 5-tab bar |
| `84faf9c64f244e9692122e0ea406d899` | LocalIQ — Discover Local. Smarter. | Desktop (2560x7816)| Desktop global header, 12-col asymmetric hero, discovery strip, monolithic steps |
| `74b9ab48b2fa4177b44e37dcb8c90a2f` | LocalIQ Plan My Trip - Mature Edition | Mobile (780x3388) | Multi-step trip planner, slider thumb styling, duration chips, pace selector |
| `2666211e4e1d444d989d7fe62fdaebf0` | LocalIQ Explore Feed - Mature Edition | Mobile (780x3838) | Category horizontal carousel, feed item rhythm, bookmark interactions |
| `e05e4aa5793e4431b07734e2583f8a54` | LocalIQ 3-Day Itinerary View | Mobile (780x4514) | Day timeline cards, walking path indicators, route overview map cards |
| `34b9e21314c74972a114c422142ed06d` | LocalIQ Web — Map Radar & Spatial | Desktop (2682x4006)| Sticky sub-header, split map + list view, radar radius selector, map pins |
| `8a7571bd78d44a238216fffca3a6e40e` | LocalIQ Web — 3-Day Itinerary Studio | Desktop (2670x5814)| Multi-day column studio, timeline nodes, curator verification badge |
| `deee40c5cf704fd4960b83d54baf2ca0` | LocalIQ Web — Plan Your Mumbai Time | Desktop (2560x4870)| Route architect layout, visual step sequence bar, preference pills |
| `e43ef91a4b56467c9bc866564d47a6a3` | LocalIQ Experience Detail | Mobile (780x5632) | Back header, 4:3 documentary hero photo, affinity match badge, sticky booking footer |
| `d0bdfd92d93146efbc7e9a9cf2cd7345` | LocalIQ Random Meetup - Mature Edition | Mobile (780x4062) | Community meetup cards, avatar groupings, consensus vote pills |
| `012bba18e03f459c9a8f0e80bd33d480` | LocalIQ Official Warm Logo Emblem | Vector (100x100) | Gateway of India silhouette inside coral location pin with sand ripples |

---

## 9. Implementation Checklist for Developers

When implementing components based on this design system:
- [ ] Ensure **Manrope** (or Plus Jakarta Sans), **Newsreader**, **DM Sans**, and **JetBrains Mono** fonts are imported via Google Fonts.
- [ ] Set background default to `#FFF8F6` (or `#FCFAF5`) and base text color to `#211A17` (Charcoal Walnut).
- [ ] Use `primary-container` (`#FF5A36`) for main CTAs and active states with `active:scale-[0.98]` micro-interactions.
- [ ] Enforce the **No-Divider Rule**: Use `surface-container-low` or `surface-container` background containers instead of solid borders.
- [ ] Maintain `pt-safe` and `pb-safe` on headers and bottom floating navigation bars.
- [ ] Include Match Score Badges with green (`#006D30` / `#95F8A7`) or coral accents on all experience discovery items.
- [ ] Ensure all touch targets meet or exceed 48x48dp.
