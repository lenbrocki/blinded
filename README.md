# Blinded

A macOS menu bar app that **automatically adjusts the built-in display brightness based on
on-screen content**. Dark content (IDEs, terminals) → screen gets brighter; bright content
(browsers, email with lots of white) → screen dims. The goal is steady *perceived* brightness
and less eye strain as you switch apps.

Works on the built-in panel **and external monitors**, each adapted to its own content and its
own learned curve. Menu-bar-only UI. Apple Silicon, macOS 14+.

## Install

1. Download `Blinded.dmg` from the [latest release](../../releases/latest).
2. Open it and drag **Blinded** to Applications, then launch it.
3. Grant **Screen Recording** when prompted (System Settings → Privacy & Security → Screen
   Recording), and relaunch.
4. In System Settings → Displays, turn **off "Automatically adjust brightness"** so Blinded is
   the sole controller.

Released builds are signed with a Developer ID and notarized, so they open without Gatekeeper
warnings.

## How it works

- **Per display:** one capture stream + adaptive engine + learned curve per display (built-in and
  every DDC-capable external), rebuilt automatically when you plug/unplug a monitor.

- **Sensing (event-driven):** a low-res ([ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit))
  stream of the main display (64×40 px). ScreenCaptureKit is push-based — it delivers a frame
  only when the screen content changes — so reactions are near-instant and a static screen costs
  ~0 CPU. Each frame's average perceptual luminance is computed.
- **Mapping (learnable):** an `AdaptiveBrightnessModel` — control points across the luminance
  range, linearly interpolated — turns luminance into a target backlight level. It cold-starts
  from the fixed `BrightnessMapper` curve and is reshaped over time by the user's corrections.
- **Actuation:** built-in panel via the private `DisplayServices.framework`
  (`DisplayServicesSetBrightness`, `dlopen`/`dlsym`); external monitors via **DDC/CI** over I2C
  using the vendored `Arm64DDC` from [MonitorControl](https://github.com/MonitorControl/MonitorControl)
  (MIT). This is why the app is **not sandboxed** and cannot ship on the Mac App Store.
- **External corrections:** macOS brightness keys don't drive DDC and DDC readback is unreliable,
  so each external display has an in-app **slider** — adjusting it both sets the brightness and
  teaches that display's curve.
- **Smoothing:** large luminance jumps ramp fast (~0.15 s); small changes ramp gently to avoid
  flicker. A short 60 Hz ramp timer runs only during a transition.

## Verifying behavior

- Open a full-screen **dark** window (terminal/IDE) → the menu's "Content luminance" drops and
  the backlight ramps **up** within a fraction of a second.
- Open a full-screen **white** window (browser/email) → luminance rises, backlight ramps
  **down**.
- Scrolling/video should not cause flicker; a fully static screen produces no adjustments.
- Toggle off → brightness stops changing and the app leaves manual changes alone.

## Learning from your corrections

The luminance→brightness curve adapts to you:

1. When content changes, the app sets brightness from the current curve.
2. If you then adjust brightness yourself (brightness keys, Control Center), the app stops
   driving, waits for your value to settle (~0.4 s), and treats it as: *"at this content
   luminance, I actually want this brightness."*
3. It nudges the curve's control points near that luminance toward your chosen value (a
   distance-weighted update), so future content with similar luminance lands closer to your
   preference. Corrections are local — adjusting brightness for white content doesn't change
   behavior for dark content.

Each display has its own learned curve saved to `~/Library/Application Support/Blinded/curve-<id>.json`
(keyed by a stable display UUID, so it survives reconnects). Each display row shows a "learned"
count and a reset button.

## Tuning

- `Blinded/BrightnessMapper.swift` — `minBrightness`, `maxBrightness`, `gamma` (the default curve).
- `Blinded/DisplayEngine.swift` — `jumpThreshold`, `fastRampPerSecond`, `gentleRampPerSecond`,
  `overrideThreshold`, `overrideSettleTime` (reaction / learning).
- `Blinded/LuminanceStabilizer.swift` — `settleTime` (transient rejection; also a menu control).

## Build from source

```sh
xcodebuild -project Blinded.xcodeproj -scheme Blinded -configuration Debug \
  -derivedDataPath build build
open build/Build/Products/Debug/Blinded.app
```

Or open `Blinded.xcodeproj` in Xcode and Run.

## Releasing (maintainer)

Tagging a `v*` version triggers [`.github/workflows/release.yml`](.github/workflows/release.yml),
which builds, Developer-ID-signs, **notarizes**, packages `Blinded.dmg`, and publishes a GitHub
Release.

```sh
git tag v0.1.0
git push origin v0.1.0
```

One-time repo **secrets** (Settings → Secrets and variables → Actions):

| Secret | What it is |
| --- | --- |
| `MACOS_CERTIFICATE` | base64 of your exported *Developer ID Application* `.p12` (cert + private key): `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PWD` | the password you set when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | any string (temporary CI keychain) |
| `APPLE_ID` | your Apple ID email |
| `APPLE_TEAM_ID` | your 10-char Team ID |
| `APPLE_APP_PASSWORD` | an app-specific password from appleid.apple.com (for notarytool) |

## Notes

- `DisplayServicesSetBrightness` and the DDC `IOAVService*` symbols are private/undocumented APIs.
  They work on current Apple Silicon Macs but are unsupported by Apple and could change.
- External brightness uses DDC/CI; monitors connected through some USB-C hubs/docks don't support
  it and won't appear as controllable.
- The capture reads rendered pixels, not emitted light, so there is no feedback loop between the
  backlight and the measured luminance.

## Credits

DDC/CI control on Apple Silicon (`Blinded/Vendor/MonitorControl/Arm64DDC.swift`) is vendored from
[MonitorControl](https://github.com/MonitorControl/MonitorControl) (MIT).
