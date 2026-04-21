# call-your-mom

`call-your-mom` is a SwiftUI iOS app with a Tamagotchi-style dashboard that encourages users to stay in touch by making calls.

## Project Structure

- `call-your-mom/call-your-mom.xcodeproj`: Xcode project
- `call-your-mom/call-your-mom/`: App source files
- `call-your-mom/call-your-mom/Assets.xcassets/`: App icons and Tamagotchi image assets

## Prerequisites

Before getting started, make sure you have:

- macOS with Xcode installed
- Xcode 26 or newer recommended
- An iPhone simulator runtime or a physical iPhone for testing

This project currently targets iOS `26.4` and uses SwiftUI with Swift `5.0`.

## Startup Instructions

### Working From VS Code

You can use VS Code as your main editor for this project. It works well for editing Swift files, browsing the project, and using the integrated terminal.

You will still need Xcode for iOS-specific tasks like:

- selecting a simulator or device
- building and running the app
- using full SwiftUI preview support
- managing signing for physical devices

From the project root, open the repo in VS Code with:

```bash
code .
```

### Open in Xcode

When you are ready to run the app, open the Xcode project:

```bash
open call-your-mom/call-your-mom.xcodeproj
```

### Run the App

1. Open the project in Xcode.
2. Select the `call-your-mom` scheme.
3. Choose an iPhone simulator or a connected device.
4. Press `Cmd+R` to build and run.

When the app launches, it opens into a tab-based interface with:

- `Tamagotchi` dashboard
- `Contacts`
- `History`
- `Account`

## Development Instructions

### Main Entry Point

The app starts in `call-your-mom/call_your_momApp.swift`, which loads `MainTabView`.

### Key Views

- `call-your-mom/MainTabView.swift`: Root tab navigation
- `call-your-mom/DashboardView.swift`: Main Tamagotchi dashboard UI and health decay behavior
- `call-your-mom/ContactsView.swift`: Contacts tab placeholder
- `call-your-mom/HistoryView.swift`: History tab placeholder
- `call-your-mom/AccountView.swift`: Account tab placeholder

### Typical Development Workflow

1. Open the repo in VS Code with `code .`.
2. Edit files in `call-your-mom/`.
3. Use the VS Code terminal for git, file search, and build commands.
4. Open Xcode when you want to run the app on a simulator or device.
5. Verify the dashboard behavior, especially:
   - health decay over time
   - Tamagotchi mood image changes
   - button interactions in the dashboard

### Terminal Build Option

If your local Xcode command line tools are set up correctly, you can also build from the terminal:

```bash
xcodebuild -project call-your-mom/call-your-mom.xcodeproj -scheme call-your-mom -configuration Debug build
```

## Current State

- No backend or external services are required for local development
- No package manager setup is required
- No automated test target is currently checked into the project

## Troubleshooting

### Xcode command line tools issues

If `xcodebuild` fails locally because Xcode components are not fully initialized, try:

```bash
xcodebuild -runFirstLaunch
```

You may also need to open Xcode once and allow it to finish installing required components.
