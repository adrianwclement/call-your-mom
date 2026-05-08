# Call Your Mom

A SwiftUI iOS app that gamifies calling people you care about (Tamagotchi + call logging + mini-game).

## Dependencies

No third-party libraries need to be installed for this project. The app uses Apple system frameworks that ship with Xcode/iOS SDK:

- SwiftUI / UIKit
- Foundation / Combine
- Contacts / ContactsUI
- UserNotifications
- AVFoundation
- CallKit

Required local tools:

- macOS with Xcode installed.
- An iOS Simulator or an iPhone/iOS device.
- An Apple Developer account or personal development team configured in Xcode for device builds.

There is no `Package.swift`, `Podfile`, or `Cartfile`; dependency managers such as Swift Package Manager, CocoaPods, and Carthage are not required.

## Quick Start

1. Open project:
```bash
open call-your-mom/call-your-mom.xcodeproj
```
2. In Xcode, select scheme `call-your-mom`.
3. Pick a simulator/device.
4. If building on a physical device, choose your signing team and a unique bundle identifier in **Signing & Capabilities**.
5. Run with `Cmd+R`.

## Where To Look First

- App entry: `call-your-mom/call-your-mom/call_your_momApp.swift`
- Main tabs: `call-your-mom/call-your-mom/MainTabView.swift`
- Most app logic/UI: `call-your-mom/call-your-mom/DashboardView.swift`

If you need to change behavior, start in `DashboardView.swift`.

## Project Map

- `call-your-mom/call-your-mom/`
  - Main app source.
- `call-your-mom/call-your-mom/Assets.xcassets/`
  - Images, icons, sprite assets.
- `call-your-mom/call-your-mom/.atlas/`
  - Sprite atlas manifests/registry.
- `call-your-mom/call-your-mom/SFX/`
  - Sound effect files (bundle these in Xcode target).

## Common Tasks

### Add / swap sound effects

Put files in:
- `call-your-mom/call-your-mom/SFX/`

Default names used by code:
- `sfx_level_up` (level-up)
- `sfx_flappy_flap` (flappy flap)

Then in Xcode ensure each file is included in target `call-your-mom` (`Target Membership` or `Copy Bundle Resources`).

### Add a new sprite

1. Add art to `Assets.xcassets`.
2. Add/edit atlas manifest in `.atlas/`.
3. Register it in `.atlas/registry.json`.

### Modify garden / movement / physics

- File: `call-your-mom/call-your-mom/DashboardView.swift`
- Search for: `PixelGardenPlaygroundView`.

### Modify level system

- File: `call-your-mom/call-your-mom/DashboardView.swift`
- Search for: `SpriteLevel`, `LevelCalculator`, `LevelPersistence`.

## Build From Terminal (optional)

```bash
xcodebuild -project call-your-mom/call-your-mom.xcodeproj -scheme call-your-mom -configuration Debug build
```

## Notes

- No backend required.
- Most state is local (`UserDefaults` + local persistence helpers).
- If behavior seems off, check `DashboardView.swift` first before digging elsewhere.
