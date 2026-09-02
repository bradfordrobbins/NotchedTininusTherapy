# Tininus Notch

A SwiftUI app for **notched tinnitus therapy** on iOS 26+ and macOS 26+. Find the frequency that matches your tinnitus, then listen to your own music or white noise with that band removed.

This is a personal self-help listening tool, not medical advice or treatment. Stop if listening is uncomfortable, and talk to a clinician about tinnitus care.

## What it does

1. **Find Frequency** — Play a sine tone from 200 Hz to 16 kHz. Use the coarse (log) slider first, then fine-tune by ±1 semitone or ±1 Hz. Save the match; the app notches around it.
2. **Therapy** — Choose **Music** or **White Noise**.
   - Music plays files from a folder you pick. DRM-protected tracks are skipped. Apple Music, Spotify, and YouTube streams cannot be notched.
   - White noise is generated in-app and run through the same filter.
   - The notch is an 8th-order Butterworth band-stop, ½ or 1 octave wide, shown on a live spectrum.
3. **Listening** — A month calendar of minutes spent in notched therapy (music or noise), not the finder tone.

Settings, the music-folder bookmark, and listening minutes are stored locally in UserDefaults.

## Requirements

- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- An iOS 26 or macOS 26 destination

## Build

```bash
brew install xcodegen
xcodegen generate
open TininusNotch.xcodeproj
```

Use the **TininusNotch-macOS** scheme for a native Mac build, or **TininusNotch-iOS** for iPhone, iPad, or My Mac (Designed for iPad).

After you add or remove source files, run `xcodegen generate` again. Do not strip the `entitlements.properties` block from `project.yml`; XcodeGen will overwrite `TininusNotch.entitlements` if that section is missing.

```bash
xcodebuild -scheme TininusNotch-macOS -destination 'platform=macOS' test
```

On macOS the sandbox may ask for microphone access once. The app uses the system audio engine for playback and does not record.

## License

[MIT](LICENSE) © 2026 Brad Robbins
