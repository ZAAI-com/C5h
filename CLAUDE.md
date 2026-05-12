# C5h Development Runbook

## App Build And Launch

C5h is a macOS Xcode app. Use `C5h.xcworkspace` with the `C5h` scheme.

From the repository root, run:

```bash
./.conductor/main
./.conductor/run
```

`./.conductor/main` verifies the Xcode toolchain and warms the Debug build cache.
`./.conductor/run` opens the workspace in Xcode. In Xcode, select the `C5h`
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
prompts, runs `claude -p ...` or `codex chat -p ...`, and records command logs
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

- `C5h/` — main app sources (`App/`, `UI/`, resources)
- `Packages/` — three Swift packages: `C5hCore`, `C5hStore`, `C5hHelper`
- `.conductor/` — build/run scripts (`main`, `run`)
- `Toolkit/`, `Resources/` — build tooling and app assets
- `Conductor.json` — Conductor workspace config

## Architecture

- **Entry point**: `C5h/App/C5hApp.swift` (SwiftUI `@main`, main `WindowGroup` + `Settings` scene).
- **Bootstrapping**: `C5h/App/AppEnvironment.swift` — `@Observable @MainActor` env that opens the database, builds repositories, and wires `ProviderRegistry`, `CommandRunner`, and `SchedulerTicker`.
- **Navigation**: `C5h/UI/Root/MainWindowView.swift` uses `NavigationSplitView(.balanced)` with an `AppTab` enum (dashboard, today, tomorrow, calendar, logs, providers, settings); sidebar pinned to `.all` visibility.
- **State**: SwiftUI Observation (`@Observable`), `@MainActor` ViewModels, constructor-injected dependencies. No Combine, no global singletons.
- **Persistence**: GRDB (SQLite) wrapped by `C5hStore.Database` over `DatabasePool`; foreign keys on; versioned migrations in `Packages/C5hStore/Sources/C5hStore/Migrations`.
- **Concurrency**: `async/await` + `@MainActor`; models are `Sendable` value types.

## Packages

- **C5hCore** (`Packages/C5hCore`) — domain models, services, provider adapters. Has tests.
  - Models: `Provider`, `ScheduledPrompt`, `PlannedWindow`, `ActualWindow`, `CommandRun`, `PromptTemplate`, `UsageSnapshot`
  - Services: `SchedulerService`, `DateTimeService`, `CommandRunner`, `CLIPathResolver`
  - Providers: `ProviderAdapter` protocol with `ClaudeProviderAdapter`, `CodexProviderAdapter`
  - Errors: `C5hError` (`LocalizedError`)
- **C5hStore** (`Packages/C5hStore`) — GRDB persistence layer. Has tests.
  - `Database`, `Migrator`, `*Record` types, `*Repository` protocols + `GRDB*Repository` implementations
- **C5hHelper** (`Packages/C5hHelper`) — executable background helper (see Debug helper section above).

## Domain Model (Quick Reference)

- **Provider** — registered AI CLI (Claude, Codex) with path, brand color, enabled flag.
- **PlannedWindow** — user-scheduled time block; status: `draft → scheduled → triggered | missed | cancelled`.
- **ActualWindow** — recorded execution window; `source: c5hTriggered | detectedFromUsage | manual`; `confidence: exact | estimated`; links to `CommandRun` and `UsageSnapshot`.
- **ScheduledPrompt** — prompt to run at a specific time; status: `scheduled → due → running → succeeded | failed | missed | cancelled`.
- **CommandRun** — single CLI invocation (args, stdout/stderr paths, exit code, tool version).
- **PromptTemplate** — reusable prompt text (provider-specific or generic).
- **UsageSnapshot** — point-in-time API usage metrics (tokens, cost).
- **Scheduler flow**: `SchedulerTicker` polls `SchedulerService` → finds due `ScheduledPrompt`s → dispatches via `ProviderAdapter` → `CommandRunner` records `CommandRun` + `ActualWindow`.

## Testing

- Framework: **Swift Testing** (`@Suite`, `@Test`, `#expect`), not XCTest.
- Test targets: `C5hCoreTests`, `C5hStoreTests` under each package's `Tests/` folder.
- Run via Xcode test action on the `C5h` scheme, or:

```bash
swift test --package-path Packages/C5hCore
swift test --package-path Packages/C5hStore
```

- Debug-only fixture loaders (`LogsFixtureLoader`, `CalendarFixtureLoader`) are guarded by `#if DEBUG`.

## Conventions

- No SwiftLint / SwiftFormat config currently — match surrounding style.
- No CI workflows (`.github/` is absent).
- Custom errors flow through `C5hError`; avoid bare `throw NSError`.
- DB-touching code goes through repository protocols, not raw GRDB calls in views.
