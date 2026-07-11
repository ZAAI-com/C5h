# C5h Development Runbook

## App Build And Launch

C5h is a macOS Xcode app. Use `C5h.xcworkspace` with the `C5h` scheme.

From the repository root, run:

```bash
./Toolkit/Conductor/setup.sh
./Toolkit/Conductor/run.sh
```

`./Toolkit/Conductor/setup.sh` verifies the Xcode toolchain and warms the Debug build cache.
`./Toolkit/Conductor/run.sh` opens the workspace in Xcode. In Xcode, select the `C5h`
scheme and run the app.

For a command-line Debug build:

```bash
xcodebuild -workspace C5h.xcworkspace -scheme C5h -configuration Debug -destination 'platform=macOS' build
```

The app creates its database and logs under:

```text
~/Library/Application Support/C5h
```

## Provider Setup

Real provider runs require the provider CLIs to be installed and authenticated:

```bash
claude --version
codex --version
```

In the app, open **Providers**, use **Detect CLI**, and use **CLI path...** if a
CLI is installed somewhere outside the standard lookup paths.

## Scheduled And Background Runs In Debug

Debug builds cannot use the signed `SMAppService` LaunchAgent registration flow.
For scheduled/background runs while developing, build the helper package and run
it as a debug subprocess from the app:

```bash
swift build --package-path Packages/C5hHelper
```

Then start the app from Xcode and go to **Settings > Helper > Debug subprocess
runner > Start**. Use **Refresh** under **Heartbeat** to verify a recent last-seen
time and PID.

The Debug helper wakes every 30 seconds, writes a heartbeat, checks due scheduled
prompts, runs `claude -p ...` or `codex exec ...`, and records command logs
and actual windows in the app database.

Debug helper logs:

```bash
tail -f /tmp/c5hhelper.dev.out
tail -f /tmp/c5hhelper.dev.err
```

The **Settings > Helper > LaunchAgent > Register** flow is unsupported in Debug
builds. It is intended for signed Release builds that include the helper and
LaunchAgent plist in the app bundle.

## Repository Layout

- `C5h/`: main app sources
  - `App/`: entry point, `AppEnvironment`, `AppSettings`
  - `UI/`: all SwiftUI views (one subdirectory per tab/feature)
  - `Core/`: app-side services and adapters (providers, scheduler driver, helper, debug bundle)
  - Resources: assets, plists
- `Packages/`: three Swift packages: `C5hCore`, `C5hStore`, `C5hHelper`
- `Toolkit/`: build/release tooling: `Conductor/` (setup, run, dev-install scripts),
  `Release/` (release, appcast scripts),
  `Homebrew/` (cask template `cask.rb.tmpl` + `render-cask.sh`)
- `Resources/`: app assets
- `Docs/`: project documentation, including the public-facing `README.md`
- `.github/workflows/`: CI and release automation (see Conventions)
- `.conductor/settings.toml`: Conductor workspace config

## Architecture

- **Entry point**: `C5h/App/C5hApp.swift` (SwiftUI `@main`, main `WindowGroup` + `Settings` scene).
- **Bootstrapping**: `C5h/App/AppEnvironment.swift`, an `@Observable @MainActor` env that opens the database, builds repositories, wires `ProviderRegistry`, `CommandRunner`, `SchedulerTicker`, and `AppSchedulerDriver`, and seeds fixture data in Debug.
- **Navigation**: `C5h/UI/Root/MainWindowView.swift` uses `NavigationSplitView(.balanced)` with an `AppTab` enum; sidebar pinned to `.all` visibility. Tabs are grouped into named sections: **Overview** (dashboard, today, tomorrow), **Calendar** (calendar), **Activity** (logs), **App** (providers, settings). Each screen owns its own `principal` toolbar item; `MainWindowView` is toolbar-agnostic.
- **Charts**: `C5h/UI/Charts/` holds the usage-trend visualizations (`UsageAreaChartView`, `UsageSparklineView`) used by the dashboard/usage screens.
- **Onboarding**: `OnboardingView` is shown on first launch (keyed by `hasCompletedOnboarding` flag in `AppSettingsRepository`) before the main `NavigationSplitView`.
- **State**: SwiftUI Observation (`@Observable`), `@MainActor` ViewModels, constructor-injected dependencies. No Combine, no global singletons.
- **Persistence**: GRDB (SQLite) wrapped by `C5hStore.Database` over `DatabasePool`; foreign keys on; schema applied by the `Migrator` in `Packages/C5hStore/Sources/C5hStore/Migrations`. Pre-1.0.0, schema changes wipe the local DB rather than adding incremental migrations: edit the base schema and delete the on-disk database instead of writing a new migration.
- **Concurrency**: `async/await` + `@MainActor`; models are `Sendable` value types.
- **Process spawning**: All CLI invocations go through `DisclaimingSpawn` (in C5hCore), which uses `posix_spawn` + `responsibility_spawnattrs_setdisclaim` so macOS TCC attributes filesystem access to the child binary, not to C5h/C5hHelper.

## Packages

- **C5hCore** (`Packages/C5hCore`): domain models, services, process primitives. Has tests.
  - Models: `Provider`, `ProviderID`, `ScheduledPrompt`, `PlannedWindow`, `ActualWindow`, `CommandRun`, `PromptTemplate`, `UsageSnapshot`
  - Services: `SchedulerService`, `PlannedWindowService`, `MissedPromptPolicy`, `DateTimeService`, `CommandRunner`, `CLIPathResolver`, `EnvironmentResolver`, `CalendarPositioning`, `LogRetentionSweeper`
  - Usage: `ClaudeUsageStatus`, `CodexUsageStatus`, `UsageNormalizer`, `UsageFetcher`
  - Validation: `PlannedWindowValidator`
  - Process: `DisclaimingSpawn` / `LaunchedProcess`, `CommandSpec`, `FileLogWriter`
  - Errors: `C5hError` (`LocalizedError`)
- **C5hStore** (`Packages/C5hStore`): GRDB persistence layer. Has tests.
  - `Database`, `Migrator`, `*Record` types, `*Repository` protocols + `GRDB*Repository` implementations
- **C5hHelper** (`Packages/C5hHelper`): executable background helper (see Debug helper section above).
- **C5h/Core/** (app target, not a package): app-side adapters and drivers:
  - `Providers/`: `ProviderAdapter` protocol implementations (`ClaudeProviderAdapter`, `CodexProviderAdapter`, `CLIBackedProviderAdapter`), `ProviderRegistry`
  - `Services/`: `AppSchedulerDriver`, `SchedulerTicker`
  - `Helper/`: `HelperDevModeRunner`, `HelperRegistrationService`
  - `DebugBundle/`: `DebugBundleExporter`
  - `Paths/`: `AppPaths`

## Domain Model (Quick Reference)

- **Provider**: registered AI CLI (Claude, Codex) with path, brand color, enabled flag.
- **ProviderID**: `String`-backed enum (`.claude`, `.codex`); provides `displayName` ("Claude", "Codex") and `executableName`.
- **PlannedWindow**: user-scheduled time block; status: `draft → scheduled → triggered | missed | cancelled`.
- **ActualWindow**: recorded execution window; `source: c5hTriggered | detectedFromUsage | manual`; `confidence: exact | estimated`; links to `CommandRun` and `UsageSnapshot`.
- **ScheduledPrompt**: prompt to run at a specific time; status: `scheduled → due → running → succeeded | failed | missed | cancelled`.
- **CommandRun**: single CLI invocation (args, stdout/stderr paths, exit code, tool version).
- **PromptTemplate**: reusable prompt text (provider-specific or generic).
- **UsageSnapshot**: point-in-time API usage metrics (tokens, cost).
- **Scheduler flow**: `SchedulerTicker` polls `AppSchedulerDriver` → `SchedulerService` finds due `ScheduledPrompt`s → dispatches via `ProviderAdapter` → `CommandRunner` records `CommandRun` + `ActualWindow`.

## Testing

- Framework: **Swift Testing** (`@Suite`, `@Test`, `#expect`), not XCTest.
- Test targets: `C5hCoreTests`, `C5hStoreTests` under each package's `Tests/` folder.
- Run via Xcode test action on the `C5h` scheme, or:

```bash
swift test --package-path Packages/C5hCore
swift test --package-path Packages/C5hStore
```

## Conventions

- No SwiftLint / SwiftFormat config currently: match surrounding style.
- CI/release lives in `.github/workflows/`, all `workflow_dispatch` (manual):
  `S1-Test-CI.yml` (build helper + run `C5hCore`/`C5hStore` tests + build app),
  `S2-Release-GitHub.yml` (build, sign, notarize, publish the DMG and the signed Sparkle appcast to Releases),
  `S3-Publish-Homebrew.yml` (render the cask and push to the `zaai-com/homebrew-tap`).
- Custom errors flow through `C5hError`; avoid bare `throw NSError`.
- DB-touching code goes through repository protocols, not raw GRDB calls in views.
- Provider display names are "Claude" and "Codex" (short form); avoid "Claude Code" or "OpenAI Codex".

## Sparkle Auto-Updates

C5h updates itself with Sparkle 2. The feed URL (`SUFeedURL` in `C5h/Info.plist`) is:

```text
https://github.com/ZAAI-com/C5h/releases/latest/download/appcast.xml
```

`Toolkit/Release/appcast.sh` generates and signs `build/appcast.xml` after
`Toolkit/Release/release.sh`; S2 uploads it alongside the DMG so the
`releases/latest/download/` URL always serves the newest release's feed.

### Feed failover (mirror feeds)

`C5h/Info.plist` lists mirror feeds in `C5hFallbackFeedURLs`, tried in order
after `SUFeedURL` when the current feed cannot be loaded (host unreachable,
DNS failure, 404, malformed or unsigned XML). `FeedFailoverController` in
`C5h/Core/Services/UpdaterService.swift` is the `SPUUpdaterDelegate` that drives
this: it restarts the check against the next mirror only when a feed never
loaded, so "you are up to date" and post-download errors do not trigger a
pointless re-check. The current feed is sticky (it stays on a mirror that works
until that mirror fails, then wraps back toward the primary) because resetting
to the primary after every success makes Sparkle fire an immediate re-check,
which becomes a tight loop during a sustained primary outage. Requirements for
a mirror:

- It must serve the same EdDSA-signed `appcast.xml` (same private key), so copy
  the S2 artifact verbatim; do not re-sign with a different key.
- Enclosure URLs in that appcast still point at the GitHub release download
  (from `--download-url-prefix`), so a mirror feed helps when the `latest`
  redirect is flaky or rate-limited, not when GitHub is fully down (the DMG
  download would still fail). To fully mirror the binary too, host the DMGs on
  the mirror and regenerate its appcast with that host's download prefix.

The current fallback is `https://zaai.com/c5h/appcast.xml`; until that host
serves the mirrored appcast, failover is a no-op (the primary GitHub feed is
used as before).

One-time key setup (done for this repo on 2026-07-11; regenerate only if the
private key is lost):

1. Download the pinned tools:
   `https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz`
   (SHA256 `ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9`).
2. Run `bin/generate_keys`: it prints the public key (goes into `C5h/Info.plist`
   as `SUPublicEDKey`) and stores the private key in the login Keychain.
3. Export the private key into the repo Actions secret, remove the export, and
   back the key up somewhere safe (losing it strands every shipped app):

   ```bash
   bin/generate_keys -x /tmp/sparkle-ed-key
   gh secret set SPARKLE_ED_PRIVATE_KEY --repo ZAAI-com/C5h < /tmp/sparkle-ed-key
   rm -P /tmp/sparkle-ed-key
   ```

Rules:

- Never sign with `codesign --deep` while Sparkle is embedded: it clobbers the
  signatures of Sparkle's nested `Autoupdate` and `Updater.app`. Deep
  verification (`codesign --verify --deep`) stays fine.
- The Sparkle tools pin lives in `Toolkit/Release/appcast.sh`
  (`SPARKLE_TOOLS_VERSION` + `SPARKLE_TOOLS_SHA256`); bump the version and the
  checksum together.
- Re-run S3 after any S2 re-run so the Homebrew cask stays in sync with the feed.
- Never delete release objects of shipped versions: a recreated release becomes
  `latest` and poisons the appcast feed.
