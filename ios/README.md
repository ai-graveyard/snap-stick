# SnapStick

SnapStick (拍立贴) is a native SwiftUI iOS app for turning camera shots into playful die-cut stickers.

Take a photo, let the on-device Vision foreground-mask API lift the subject, wrap it in a white sticker border, watch the print develop over a few seconds (or shake the phone to develop it instantly, like flicking a Polaroid), and drop it into a gyroscope-driven physics sandbox where stickers slide and collide as the phone tilts. The app stores history locally on device; the whole flow needs no backend, account, or API key. Optionally, you can plug your own Volcengine Ark (Doubao) API key into Settings — today it only powers a connectivity test, reserved for future cloud features.

## Features

- On-device subject extraction with Vision foreground masks
- On-device subject classification into 10 lifestyle categories, with manual override and history filtering
- White die-cut sticker border rendered locally
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
