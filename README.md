# 🌺 Hibiscus

**Color by feel.**

Hibiscus is a free and open-source native iPhone camera and color-grading app built with SwiftUI, AVFoundation, Core Image, Vision, and Metal-backed previews.

Hibiscus keeps photography focused around two core experiences:

- **Camera** — capture photographs directly through distinct photographic Camera characters.
- **Grade** — import photographs, choose a designed color style, and shape the result through tactile Style and Accent controls.

The app intentionally avoids accounts, cloud sync, subscriptions, an internal photo library, social features, and professional editing panels.

## Camera

Camera opens directly into a live, character-processed viewfinder.

Ten Camera characters provide distinct image-making responses:

- **✨ Clear — Clean Modern** — clean, neutral color with restrained processing.
- **🎞️ Negative — Color Negative** — warm mids, gentle contrast, and soft highlight behavior.
- **💿 Digital — Early Digital / CCD** — crisp, cool compact-digital color and firmer contrast.
- **⚡️ Flash — Flash Compact** — punchy direct-flash energy and separated ambient shadows.
- **🖼️ Instant — Instant** — creamy warm whites, muted color, and gentle tone.
- **🎟️ Disposable — Disposable** — controlled daylight imperfection with clear central detail.
- **🌙 Night — Night Digital** — cool artificial-light color with deep, structured blacks.
- **🌸 Portrait — Portrait** — pleasant skin response and gentler highlight transitions.
- **🏙️ Street — Street** — dense urban tone, detailed blacks, and crisp structure.
- **🌓 Mono — Monochrome** — deliberate grayscale response and tonal separation.

For detailed Camera design notes and intended behavior, see [`docs/cameras.md`](docs/cameras.md).

Camera uses continuous system autofocus and supports exposure compensation, device-derived discrete lens choices, flash, timer, aspect ratio, grid, front/rear switching, and supported processed or RAW capture formats.

## Grade

Grade provides sixteen designed color styles. Each style is a starting color space rather than a fixed one-tap filter.

- **Pure** — clean, neutral color with subtle polish and balanced contrast.
- **Air** — bright, lightly cool, open color with soft contrast and an airy feel.
- **Glow** — warm, luminous color with creamy highlights and gentle tonal rolloff.
- **Soft** — restrained pastel color with lower contrast and softened tonal extremes.
- **Rich** — deeper blacks, fuller color, and a denser photographic character.
- **Chrome** — crisp color separation with stronger blues and reds and restrained greens.
- **Fade** — lifted blacks, muted color, and a lightly nostalgic low-contrast response.
- **Ember** — peach, amber, and burnt-orange warmth without overwhelming neutral tones.
- **Blush** — rose and peach color with a soft, people-friendly warmth.
- **Moss** — earthy olive and green character with restrained yellows.
- **Tide** — clean cyan and ocean-blue color with a cooler overall balance.
- **Dusk** — cooler violet-blue shadows paired with warmer light.
- **Cinema** — restrained cinematic separation with cooler shadows and warmer mids.
- **Neon** — energetic cyan and magenta color designed especially for colorful and night scenes.
- **Silver** — softer monochrome with smooth tonal separation and gentle contrast.
- **Ink** — stronger monochrome with deeper blacks and more graphic tonal separation.

After selecting a style, Hibiscus exposes two tactile two-dimensional grading surfaces:

### Style

The Style pad explores variations of the selected style while preserving its core character.

Horizontal movement adjusts the style's color character.

Vertical movement adjusts tonal openness and density.

The center represents the designed default.

### Accent

Accent analyzes the current photograph and suggests a visually meaningful color treatment based on the image.

The suggested color can also be customized manually.

Accent has its own two-dimensional control for exploring related color relationships and tonal placement across highlights and shadows.

Style and Accent share a contextual Strength control.

Press and hold the photo preview to compare the edited result with the original.

For detailed style design information, see [`docs/styles.md`](docs/styles.md).

## Batch editing

Grade supports temporary editing sessions of up to ten photographs. Each photograph preserves its own Style, pad positions, Strength values, and Accent state. A selected Style treatment can be explicitly applied across the batch without replacing each photograph's automatic Accent analysis.

## Export

Hibiscus can save or share:

- **Photo** — the edited photograph.
- **Polaroid** — an instant-photo-style card with optional metadata, drawing, and Hibiscus mark.
- **Palette** — the edited photograph with up to five representative color blocks.

Normal photo exports can preserve supported source metadata and location when enabled. Originals are never overwritten.

## Requirements

- Xcode 26.0 or later
- iOS 17.0 or later
- A physical iPhone is recommended for camera, flash, lens, and RAW validation

On iOS 26 or later, Hibiscus uses native Liquid Glass. On iOS 17 and iOS 18, the same controls use a translucent system-material fallback.

## Build

Open `Hibiscus.xcodeproj` in Xcode, select the `Hibiscus` scheme, choose an iPhone destination, and run the app.

For a command-line build without code signing:

```sh
xcodebuild \
  -project Hibiscus.xcodeproj \
  -scheme Hibiscus \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Camera and Photos permissions are requested when their corresponding features are used.

## License

Licensed under MPL-2.0.
