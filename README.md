<div align="center">

# Blinded

### Adaptive screen brightness for macOS that follows your content — and learns from you.

Blinded watches what's on your screen and keeps its **perceived** brightness steady: it dims
for bright pages and brightens for dark editors, so your eyes aren't constantly readjusting.
Set the brightness yourself once and it **remembers what you wanted** — across your built-in
display *and* every external monitor.

**Apple Silicon · macOS 14+ · lives in the menu bar**

</div>

---

## ✨ Features

- **🌗 Content-aware** — bright, white-heavy windows dim the backlight; dark IDEs and terminals
  brighten it. The goal is constant *perceived* brightness and less eye strain.
- **🧠 Learns your preference** — whenever you adjust brightness yourself, Blinded records what
  you wanted for that kind of content and adapts its curve. The more you use it, the more it
  feels like yours.
- **🖥️ Built-in *and* external monitors** — controls your MacBook panel and external displays
  over DDC/CI, each adapted to its own content and with its own learned memory. Plug or unplug a
  monitor and it adjusts automatically.
- **⚡ Instant and quiet** — reacts the moment your content changes, and uses ~no CPU when the
  screen is still.
- **🪶 Out of the way** — a single menu-bar icon, no Dock clutter, no window to manage.
- **🔒 Private** — everything happens locally on your Mac; nothing is sent anywhere.

## Install

1. Download **`Blinded.dmg`** from the [latest release](../../releases/latest).
2. Open it and drag **Blinded** into **Applications**.
3. Launch Blinded — a sun icon appears in your menu bar.

> Releases are signed with a Developer ID and notarized by Apple, so they open without security
> warnings.

## Getting started

1. Click the menu-bar icon and turn on **Auto-brightness**.
2. Grant **Screen Recording** when macOS asks (System Settings → Privacy & Security → Screen
   Recording → enable **Blinded**), then relaunch the app. *Blinded reads your screen only to
   measure how bright the content is — never its contents.*
3. In **System Settings → Displays**, turn **off “Automatically adjust brightness”** so Blinded
   is the only thing controlling your backlight.

That's it — switch between a dark editor and a bright browser and watch the brightness follow.

## Teaching it your preference

Each display has a brightness **slider** in the menu. Whenever the brightness isn't quite right:

- **Built-in display:** just use your keyboard's brightness keys as usual.
- **External display:** drag its slider in the menu.

Blinded treats that as *“for this kind of content, I want this brightness”* and reshapes that
display's curve so similar content lands where you like it next time. Corrections are **local** —
tuning bright pages doesn't affect how dark ones behave. Each display remembers separately, and
its memory survives reconnects. A per-display reset button restores the default curve.

## How it works (in plain terms)

Blinded takes a tiny, low-resolution snapshot of each screen *only when its content changes*,
measures the average brightness, and maps that to a backlight level through a curve it keeps
refining from your corrections. Transitions ramp smoothly so there's no flicker, and a static
screen costs essentially nothing.

---

## Under the hood

- **Per-display engine** — each display gets its own capture stream, brightness curve, and
  control loop, created and torn down automatically on hotplug ([`DisplayCoordinator`](Blinded/DisplayCoordinator.swift),
  [`DisplayEngine`](Blinded/DisplayEngine.swift)).
- **Sensing** — an event-driven [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
  stream downscaled to ~64×40 px. It's push-based (frames arrive only on content change), so
  reactions are near-instant and an idle screen is ~0 CPU. Average perceptual luminance is
  computed per frame.
- **Learnable mapping** — an [`AdaptiveBrightnessModel`](Blinded/AdaptiveBrightnessModel.swift)
  of interpolated control points across the luminance range. It cold-starts from a fixed curve
  and is reshaped by corrections via a local, distance-weighted update that keeps the curve
  monotonic. Saved per display to `~/Library/Application Support/Blinded/curve-<id>.json`.
- **Actuation** — built-in panel through the private `DisplayServices` framework
  (`DisplayServicesSetBrightness`, resolved with `dlopen`/`dlsym`); external monitors through
  **DDC/CI** over I2C using the vendored [`Arm64DDC`](Blinded/Vendor/MonitorControl/Arm64DDC.swift)
  from MonitorControl. Because it uses private APIs it is **not sandboxed** and can't ship on the
  Mac App Store.
- **Smoothness** — a [`LuminanceStabilizer`](Blinded/LuminanceStabilizer.swift) ignores transient
  luminance during window/space-swipe animations, and brightness ramps fast for big switches,
  gently for small ones.

### Build from source

```sh
xcodebuild -project Blinded.xcodeproj -scheme Blinded -configuration Debug \
  -derivedDataPath build build
open build/Build/Products/Debug/Blinded.app
```

Or open `Blinded.xcodeproj` in Xcode and Run.

### Releasing (maintainer)

Pushing a `v*` tag triggers [`.github/workflows/release.yml`](.github/workflows/release.yml),
which builds, Developer-ID-signs, **notarizes**, packages `Blinded.dmg`, and publishes a GitHub
Release.

```sh
git tag v0.1.0
git push origin v0.1.0
```

One-time repo **secrets** (Settings → Secrets and variables → Actions):

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE` | base64 of your exported *Developer ID Application* `.p12`: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PWD` | the password you set when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | any string (temporary CI keychain) |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | your 10-char Team ID |
| `APPLE_APP_PASSWORD` | an app-specific password from appleid.apple.com (for notarytool) |

### Tuning

- [`BrightnessMapper.swift`](Blinded/BrightnessMapper.swift) — `minBrightness`, `maxBrightness`,
  `gamma` (the default curve).
- [`DisplayEngine.swift`](Blinded/DisplayEngine.swift) — `jumpThreshold`, `fastRampPerSecond`,
  `gentleRampPerSecond`, `overrideThreshold`, `overrideSettleTime` (reaction / learning).
- [`LuminanceStabilizer.swift`](Blinded/LuminanceStabilizer.swift) — `settleTime` (transient
  rejection; default `0` = off).

### Limitations

- `DisplayServicesSetBrightness` and the DDC `IOAVService*` symbols are private/undocumented.
  They work on current Apple Silicon Macs but are unsupported by Apple and could change.
- External control needs DDC/CI; some displays — or connections through certain USB-C
  hubs/docks — don't support it and won't appear as controllable.
- Capture reads rendered pixels, not emitted light, so there's no feedback loop between the
  backlight and the measurement.

## Credits & license

Blinded is released under the [MIT License](LICENSE). DDC/CI control on Apple Silicon
([`Arm64DDC.swift`](Blinded/Vendor/MonitorControl/Arm64DDC.swift)) is vendored from
[MonitorControl](https://github.com/MonitorControl/MonitorControl), also MIT.
