# C5h

**Schedule and run AI provider CLIs in planned and background windows.**

C5h is a native macOS app that tracks your Claude and Codex **5-hour usage
windows** in one place. See which windows are active on a day calendar, schedule
prompts to run inside planned or background windows, and watch your usage trends
over time, so you always know where you stand against your limits before you hit
them.

## Features

- **Track 5-hour windows**: Claude and Codex usage windows, side by side.
- **Day calendar**: see active and upcoming windows laid out on a timeline.
- **Connect your CLIs**: point C5h at your installed `claude` and `codex` CLIs.
- **Usage trends**: area and sparkline charts of usage over time.
- **Scheduled & background runs**: queue prompts to run automatically inside a
  window, even when you're away.

## Requirements

- macOS Tahoe (macOS 26) or later.
- The `claude` and `codex` CLIs installed and authenticated:

  ```bash
  claude --version
  codex --version
  ```

## Install

**Homebrew (recommended):**

```bash
brew install --cask zaai-com/tap/c5h
```

**Direct download:** download the latest `C5h-<version>.dmg` from
[GitHub Releases](https://github.com/ZAAI-com/C5h/releases), open it, and drag
**C5h.app** to your Applications folder. The app is signed and notarized.

## First run

1. Launch C5h. A short onboarding walks you through what the app tracks.
2. Open the **Providers** tab and use **Detect CLI** to find your `claude` and
   `codex` binaries. If a CLI lives outside the standard lookup paths, use
   **CLI path…** to point at it directly.
3. Your windows and usage start populating as the CLIs report activity.

## Where C5h stores data

The app keeps its database and logs under:

```text
~/Library/Application Support/C5h
```

Removing that folder resets the app to a clean state.

## Build from source

C5h is a Swift / SwiftUI Xcode app. With the latest Xcode installed:

```bash
xcodebuild -workspace C5h.xcworkspace -scheme C5h \
  -configuration Debug -destination 'platform=macOS' build
```

For the full development runbook (architecture, packages, the background helper,
and scheduled-run testing) see [`.claude/CLAUDE.md`](../.claude/CLAUDE.md).

## License

C5h is released under the [MIT License](../LICENSE).
