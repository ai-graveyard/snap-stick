# SnapStick

SnapStick (拍立贴) is a native SwiftUI iOS app for turning camera shots into playful die-cut stickers.

Take a photo, let the on-device Vision foreground-mask API lift the subject, wrap it in a white sticker border, watch the print develop over a few seconds (or shake the phone to develop it instantly, like flicking a Polaroid), and drop it into a gyroscope-driven physics sandbox where stickers slide and collide as the phone tilts. The app stores history locally on device; the whole flow needs no backend, account, or API key. Optionally, you can plug your own Volcengine Ark (Doubao) API key into Settings and switch on AI 卡通贴纸 (only enabled after a passed connectivity test): each shot is then first turned into a fridge-magnet-style cartoon card by the seedream image model — the same prompt as the web app — before the on-device cutout lifts the subject from it, and any failure falls back to the fully local pipeline.

## Features

- On-device subject extraction with Vision foreground masks
- On-device subject classification into 10 lifestyle categories, with manual override and history filtering
- White die-cut sticker border rendered locally
- Optional AI cartoon sticker mode (AI 卡通贴纸, bring-your-own Doubao key): seedream turns the shot into a fridge-magnet-style cartoon card before the local cutout, falling back to the fully local pipeline on any failure
- Expanded square viewfinder (大取景): tap the camera lens for a full-screen framing view (~8× the visible preview area)
- Hardware-aware camera zoom: 0.5×–3× presets plus pinch-to-zoom, on both the camera body and the expanded viewfinder; front/back camera flip
- Rotate a shot by 90° / 180° / 270° after capture, from the print card or the sticker detail sheet
- Shake-to-develop reveal (still phone ≈5s; shake to finish in ≈1s)
- Gyroscope-driven sticker physics sandbox
- Local photo history and calendar browsing, plus a sticker detail sheet
- Recycle bin with 30-day restore for deleted stickers
- Switchable paper styles for framed sharing
- Chinese and English UI with live language switching
- Light, dark, and system appearance modes

## Build

Compile-check without signing:

```bash
xcodebuild -project SnapStick.xcodeproj -scheme SnapStick \
  -destination 'generic/platform=iOS' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

Run the app on a physical iOS device for camera and CoreMotion behavior. The repository's agent instructions intentionally avoid Simulator launch/testing.

## Project Notes

Development guidance for AI coding agents lives in [AGENTS.md](AGENTS.md). It covers architecture, build constraints, localization, design rules, and the current product direction.
