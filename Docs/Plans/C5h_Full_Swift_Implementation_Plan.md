# C5h Full Swift macOS App — Detailed Implementation Plan

**Product:** C5h  
**Target:** macOS desktop app  
**Architecture decision:** Full Swift first, no Rust backend for v1  
**Primary stack:** SwiftUI, Swift Concurrency, Foundation `Process`, SQLite via GRDB, later Swift LaunchAgent helper via `SMAppService`  
**Primary goal:** Run and schedule CLI commands for Claude Code and OpenAI Codex, collect usage/window data, and visualize planned vs actual 5-hour coding windows.

---

## 1. Product Summary

C5h is a macOS utility for planning, triggering, tracking, and reviewing 5-hour AI coding windows across provider CLIs.

Initial supported providers:

- Claude Code CLI
- OpenAI Codex CLI

C5h has two main jobs:

1. **Planning:** Let the user schedule 5-hour provider windows on a calendar.
2. **Execution + tracking:** Run provider CLI prompts, log all command activity, collect usage signals, and show actual coding windows next to planned windows.

The app should feel like a native Mac productivity utility, not a browser app wrapped in a desktop shell.

---

## 2. Core Architecture Decision

### Chosen v1 architecture

```txt
SwiftUI macOS app
+ Swift backend services
+ Foundation Process-based CLI runner
+ SQLite event store via GRDB
+ custom SwiftUI calendar UI
+ later: Swift LaunchAgent helper registered with SMAppService
```

### Explicitly out of scope for v1

```txt
Rust backend
Tauri shell
Electron shell
Cloud backend
Multi-user sync
Mobile app
Web app
```

### Why full Swift first

Full Swift gives the fastest path to a polished native MVP:

- One language.
- Native macOS UI.
- Simple Xcode project.
- Direct integration with menus, settings, notifications, file pickers, and login items.
- CLI integration is fully possible with Foundation `Process`.
- Background scheduling can be added later with a Swift helper.

Rust can be reconsidered later only if Swift subprocess handling becomes a real limitation.

---

## 3. High-Level App Architecture

```txt
C5h.app
├─ SwiftUI App Layer
│  ├─ Navigation
│  ├─ Calendar UI
│  ├─ Dashboard
│  ├─ Logs
│  ├─ Providers
│  ├─ Settings
│  └─ Detail inspectors
│
├─ Application Services
│  ├─ ProviderService
│  ├─ SchedulerService
│  ├─ CommandRunService
│  ├─ UsageService
│  ├─ CalendarWindowService
│  ├─ NotificationService
│  └─ SettingsService
│
├─ Provider Adapters
│  ├─ ClaudeProviderAdapter
│  └─ CodexProviderAdapter
│
├─ Infrastructure
│  ├─ CommandRunner
│  ├─ FileLogWriter
│  ├─ EnvironmentResolver
│  ├─ CLIPathResolver
│  ├─ DateTimeService
│  └─ AppPaths
│
├─ Persistence
│  ├─ GRDB database
│  ├─ migrations
│  ├─ repositories
│  └─ observed queries
│
└─ Later: C5hHelper.app
   ├─ LaunchAgent worker
   ├─ scheduled prompt loop
   ├─ provider CLI execution
   └─ shared DB writer
```

---

## 4. Repository / Project Layout

Recommended repo structure:

```txt
c5h/
├─ C5h.xcodeproj
├─ C5h/
│  ├─ App/
│  │  ├─ C5hApp.swift
│  │  ├─ AppDelegate.swift
│  │  ├─ AppEnvironment.swift
│  │  └─ AppCommands.swift
│  │
│  ├─ UI/
│  │  ├─ Root/
│  │  │  ├─ MainWindowView.swift
│  │  │  ├─ NavbarView.swift
│  │  │  └─ AppTab.swift
│  │  │
│  │  ├─ Dashboard/
│  │  │  ├─ DashboardView.swift
│  │  │  ├─ ActiveWindowCard.swift
│  │  │  ├─ NextScheduleCard.swift
│  │  │  └─ UsageSummaryCard.swift
│  │  │
│  │  ├─ Calendar/
│  │  │  ├─ DayCalendarView.swift
│  │  │  ├─ WeekCalendarView.swift
│  │  │  ├─ TimeRulerView.swift
│  │  │  ├─ ProviderColumnView.swift
│  │  │  ├─ PlannedWindowBlockView.swift
│  │  │  ├─ ActualWindowBlockView.swift
│  │  │  ├─ NowLineView.swift
│  │  │  ├─ CalendarDragOverlay.swift
│  │  │  └─ WindowInspectorView.swift
│  │  │
│  │  ├─ Logs/
│  │  │  ├─ LogsView.swift
│  │  │  ├─ CommandRunTable.swift
│  │  │  ├─ CommandRunDetailView.swift
│  │  │  ├─ OutputLogView.swift
│  │  │  └─ LogFiltersView.swift
│  │  │
│  │  ├─ Providers/
│  │  │  ├─ ProvidersView.swift
│  │  │  ├─ ProviderCardView.swift
│  │  │  ├─ ProviderStatusBadge.swift
│  │  │  └─ ProviderTestPanel.swift
│  │  │
│  │  ├─ Settings/
│  │  │  ├─ SettingsView.swift
│  │  │  ├─ GeneralSettingsView.swift
│  │  │  ├─ SchedulerSettingsView.swift
│  │  │  ├─ LogsSettingsView.swift
│  │  │  └─ AdvancedSettingsView.swift
│  │  │
│  │  └─ DesignSystem/
│  │     ├─ C5hColors.swift
│  │     ├─ C5hSpacing.swift
│  │     ├─ C5hTypography.swift
│  │     └─ Components/
│  │
│  ├─ Core/
│  │  ├─ Models/
│  │  ├─ Services/
│  │  ├─ Providers/
│  │  ├─ Scheduling/
│  │  ├─ Commands/
│  │  ├─ Usage/
│  │  └─ Errors/
│  │
│  ├─ Store/
│  │  ├─ Database/
│  │  ├─ Migrations/
│  │  ├─ Repositories/
│  │  └─ Queries/
│  │
│  ├─ Infrastructure/
│  │  ├─ Process/
│  │  ├─ Files/
│  │  ├─ Paths/
│  │  ├─ Notifications/
│  │  └─ System/
│  │
│  └─ Resources/
│     ├─ Assets.xcassets
│     └─ PreviewData/
│
├─ C5hHelper/                         # Add in later milestone
│  ├─ C5hHelperApp.swift
│  ├─ HelperMain.swift
│  └─ SchedulerWorker.swift
│
├─ Packages/                          # Optional later extraction
│  ├─ C5hCore/
│  ├─ C5hStore/
│  └─ C5hCalendarUI/
│
└─ docs/
   ├─ architecture.md
   ├─ database.md
   ├─ provider-integrations.md
   └─ release-checklist.md
```

### Initial recommendation

Start as one app target with clear folders. Extract Swift packages only when the boundaries stabilize.

Suggested future packages:

```txt
C5hCore       pure models and services
C5hStore      GRDB database and repositories
C5hCalendarUI reusable calendar views
C5hProviders  Claude and Codex adapters
```

---

## 5. Main UI Structure

### Required navbar

```txt
┌────────────────────────────────────────────────────────────────────┐
│ C5h Logo       Dashboard Today Tomorrow Calendar Logs Providers ⚙ │
└────────────────────────────────────────────────────────────────────┘
```

Navbar requirements:

- Logo left.
- Center tabbar.
- Tab icons and labels.
- Active tab indicator.
- Optional right status area later: helper running, provider status, next scheduled job.

### App tabs

```swift
enum AppTab: String, CaseIterable, Identifiable {
    case dashboard
    case today
    case tomorrow
    case calendar
    case logs
    case providers
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .calendar: "Calendar"
        case .logs: "Logs"
        case .providers: "Providers"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "chart.xyaxis.line"
        case .today: "calendar.day.timeline.left"
        case .tomorrow: "calendar.badge.clock"
        case .calendar: "calendar"
        case .logs: "terminal"
        case .providers: "shippingbox"
        case .settings: "gearshape"
        }
    }
}
```

### Root view sketch

```swift
struct MainWindowView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        VStack(spacing: 0) {
            NavbarView(selectedTab: $selectedTab)
            Divider()
            content
        }
        .frame(minWidth: 1100, minHeight: 720)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .today:
            DayCalendarScreen(date: .now)
        case .tomorrow:
            DayCalendarScreen(date: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        case .calendar:
            WeekCalendarScreen()
        case .logs:
            LogsView()
        case .providers:
            ProvidersView()
        case .settings:
            SettingsView()
        }
    }
}
```

---

## 6. Calendar UI Plan

### Calendar goal

The calendar is the primary C5h workspace.

Today view must show:

- One vertical day from midnight to midnight.
- One provider column per provider.
- Planned 5-hour blocks as narrow calendar blocks.
- Actual 5-hour windows as wider calendar blocks.
- Claude in Claude-orange.
- Codex in OpenAI-blue.
- Current time indicator.
- Clickable blocks with details.
- Later: drag to create scheduled 5-hour prompt.

### Day layout

```txt
00:00 ┌──────────── Claude ────────────┬──────────── Codex ────────────┐
01:00 │                                 │                              │
02:00 │  planned narrow block           │                              │
03:00 │  █                              │  actual wide block           │
04:00 │  █      actual wide block       │  █████████████               │
05:00 │  █      █████████████           │  █████████████               │
...   │                                 │                              │
24:00 └─────────────────────────────────┴──────────────────────────────┘
```

### Component tree

```txt
DayCalendarScreen
├─ DayCalendarToolbar
│  ├─ date picker
│  ├─ previous / next day
│  ├─ create planned window
│  └─ start provider now
│
└─ DayCalendarView
   ├─ TimeRulerView
   ├─ ProviderColumnView[Claude]
   │  ├─ PlannedWindowLayer
   │  ├─ ActualWindowLayer
   │  ├─ NowLineSegment
   │  └─ DragSelectionOverlay
   │
   ├─ ProviderColumnView[Codex]
   │  ├─ PlannedWindowLayer
   │  ├─ ActualWindowLayer
   │  ├─ NowLineSegment
   │  └─ DragSelectionOverlay
   │
   └─ WindowInspectorPopover / Sheet
```

### Layout constants

```swift
struct CalendarLayoutConfig {
    var pixelsPerMinute: CGFloat = 0.85
    var timeRulerWidth: CGFloat = 72
    var providerMinWidth: CGFloat = 280
    var plannedBlockWidthRatio: CGFloat = 0.42
    var actualBlockWidthRatio: CGFloat = 0.84
    var blockCornerRadius: CGFloat = 10
    var hourLineOpacity: Double = 0.18
}
```

### Positioning logic

```swift
func minutesSinceStartOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
    let start = calendar.startOfDay(for: date)
    return calendar.dateComponents([.minute], from: start, to: date).minute ?? 0
}

func yOffset(for date: Date, pixelsPerMinute: CGFloat) -> CGFloat {
    CGFloat(minutesSinceStartOfDay(date)) * pixelsPerMinute
}

func blockHeight(from start: Date, to end: Date, pixelsPerMinute: CGFloat) -> CGFloat {
    let minutes = Calendar.current.dateComponents([.minute], from: start, to: end).minute ?? 0
    return max(CGFloat(minutes) * pixelsPerMinute, 24)
}
```

### Planned vs actual visual treatment

```txt
Planned window:
- narrower
- leading aligned
- translucent fill
- provider-colored border
- title: planned prompt/template
- status pill: draft/scheduled/triggered/missed

Actual window:
- wider
- trailing aligned or centered
- stronger fill
- provider color
- title: actual provider run
- linked command-run status
```

### Recommended colors

```swift
enum ProviderBrandColor {
    static let claude = Color(red: 0.85, green: 0.43, blue: 0.25)
    static let codex = Color(red: 0.15, green: 0.39, blue: 0.92)
}
```

### Week view

Week view can reuse most calendar components.

Initial week view options:

1. **7-day x provider grid:** best overview, but dense.
2. **Provider swimlanes across week:** closer to resource timeline.
3. **Compact blocks per day:** easiest MVP.

Recommended MVP:

```txt
WeekCalendarView
├─ week header: Mon Tue Wed Thu Fri Sat Sun
├─ provider rows: Claude, Codex
└─ compact planned/actual blocks
```

Do not overbuild week view before Today works well.

---

## 7. Domain Model

### ProviderID

```swift
enum ProviderID: String, Codable, Sendable, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "OpenAI Codex"
        }
    }
}
```

### Provider

```swift
struct Provider: Identifiable, Codable, Sendable {
    var id: ProviderID
    var displayName: String
    var cliPath: String?
    var isEnabled: Bool
    var brandColorHex: String
    var createdAt: Date
    var updatedAt: Date
}
```

### PlannedWindow

```swift
struct PlannedWindow: Identifiable, Codable, Sendable {
    var id: UUID
    var providerID: ProviderID
    var startAt: Date
    var endAt: Date
    var promptTemplateID: UUID?
    var projectPath: String?
    var status: PlannedWindowStatus
    var createdAt: Date
    var updatedAt: Date
}

enum PlannedWindowStatus: String, Codable, Sendable {
    case draft
    case scheduled
    case triggered
    case missed
    case cancelled
}
```

### ActualWindow

```swift
struct ActualWindow: Identifiable, Codable, Sendable {
    var id: UUID
    var providerID: ProviderID
    var startAt: Date
    var endAt: Date
    var source: ActualWindowSource
    var confidence: WindowConfidence
    var commandRunID: UUID?
    var usageStartSnapshotID: UUID?
    var usageEndSnapshotID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

enum ActualWindowSource: String, Codable, Sendable {
    case c5hTriggered
    case detectedFromUsage
    case manual
}

enum WindowConfidence: String, Codable, Sendable {
    case exact
    case estimated
}
```

### ScheduledPrompt

```swift
struct ScheduledPrompt: Identifiable, Codable, Sendable {
    var id: UUID
    var providerID: ProviderID
    var plannedWindowID: UUID?
    var prompt: String
    var projectPath: String?
    var runAt: Date
    var status: ScheduledPromptStatus
    var attempts: Int
    var lastError: String?
    var createdAt: Date
    var updatedAt: Date
}

enum ScheduledPromptStatus: String, Codable, Sendable {
    case scheduled
    case due
    case running
    case succeeded
    case failed
    case missed
    case cancelled
}
```

### CommandRun

```swift
struct CommandRun: Identifiable, Codable, Sendable {
    var id: UUID
    var providerID: ProviderID
    var runType: CommandRunType
    var command: String
    var argumentsJSON: String
    var workingDirectory: String?
    var startedAt: Date
    var endedAt: Date?
    var exitCode: Int32?
    var status: CommandRunStatus
    var stdoutPath: String?
    var stderrPath: String?
    var parsedEventsJSON: String?
    var errorMessage: String?
}

enum CommandRunType: String, Codable, Sendable {
    case detectStatus
    case authStatus
    case collectUsage
    case triggerPrompt
    case testCommand
}

enum CommandRunStatus: String, Codable, Sendable {
    case pending
    case running
    case succeeded
    case failed
    case timedOut
    case cancelled
}
```

### UsageSnapshot

```swift
struct UsageSnapshot: Identifiable, Codable, Sendable {
    var id: UUID
    var providerID: ProviderID
    var capturedAt: Date
    var rawJSON: String
    var normalizedJSON: String
}
```

### PromptTemplate

```swift
struct PromptTemplate: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var providerID: ProviderID?
    var body: String
    var createdAt: Date
    var updatedAt: Date
}
```

---

## 8. Persistence Plan

### Database choice

Use SQLite via GRDB.

Reasons:

- Better fit than SwiftData for logs and event history.
- Easy migrations.
- Explicit schema.
- Cross-process friendly later when adding helper.
- Easier to inspect and debug.
- Good support for observation and reactive UI updates.

### Database location

Use Application Support:

```txt
~/Library/Application Support/C5h/c5h.sqlite
~/Library/Application Support/C5h/logs/
```

### AppPaths

```swift
struct AppPaths {
    let appSupportDirectory: URL
    let databaseURL: URL
    let logsDirectory: URL

    static func live() throws -> AppPaths {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("C5h", isDirectory: true)

        let logs = base.appendingPathComponent("logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

        return AppPaths(
            appSupportDirectory: base,
            databaseURL: base.appendingPathComponent("c5h.sqlite"),
            logsDirectory: logs
        )
    }
}
```

### Database schema

```sql
create table providers (
  id text primary key,
  display_name text not null,
  cli_path text,
  enabled integer not null,
  brand_color text not null,
  created_at text not null,
  updated_at text not null
);

create table planned_windows (
  id text primary key,
  provider_id text not null references providers(id),
  start_at text not null,
  end_at text not null,
  prompt_template_id text,
  project_path text,
  status text not null,
  created_at text not null,
  updated_at text not null
);

create index idx_planned_windows_provider_start
on planned_windows(provider_id, start_at);

create table actual_windows (
  id text primary key,
  provider_id text not null references providers(id),
  start_at text not null,
  end_at text not null,
  source text not null,
  confidence text not null,
  command_run_id text,
  usage_start_snapshot_id text,
  usage_end_snapshot_id text,
  created_at text not null,
  updated_at text not null
);

create index idx_actual_windows_provider_start
on actual_windows(provider_id, start_at);

create table scheduled_prompts (
  id text primary key,
  provider_id text not null references providers(id),
  planned_window_id text references planned_windows(id),
  prompt text not null,
  project_path text,
  run_at text not null,
  status text not null,
  attempts integer not null default 0,
  last_error text,
  created_at text not null,
  updated_at text not null
);

create index idx_scheduled_prompts_status_run_at
on scheduled_prompts(status, run_at);

create table command_runs (
  id text primary key,
  provider_id text not null references providers(id),
  run_type text not null,
  command text not null,
  arguments_json text not null,
  cwd text,
  started_at text not null,
  ended_at text,
  exit_code integer,
  status text not null,
  stdout_path text,
  stderr_path text,
  parsed_events_json text,
  error text
);

create index idx_command_runs_provider_started
on command_runs(provider_id, started_at);

create index idx_command_runs_status_started
on command_runs(status, started_at);

create table usage_snapshots (
  id text primary key,
  provider_id text not null references providers(id),
  captured_at text not null,
  raw_json text not null,
  normalized_json text not null
);

create index idx_usage_snapshots_provider_captured
on usage_snapshots(provider_id, captured_at);

create table prompt_templates (
  id text primary key,
  name text not null,
  provider_id text references providers(id),
  body text not null,
  created_at text not null,
  updated_at text not null
);

create table app_settings (
  key text primary key,
  value_json text not null,
  updated_at text not null
);
```

### Seed data

On first launch, insert:

```txt
providers:
- claude, display name Claude Code, enabled true, orange
- codex, display name OpenAI Codex, enabled true, blue

prompt templates:
- Start 5h coding window
- Continue previous task
- Resume project context
```

### Repository interfaces

```swift
protocol PlannedWindowRepository {
    func fetchWindows(for dateInterval: DateInterval) async throws -> [PlannedWindow]
    func create(_ window: PlannedWindow) async throws
    func update(_ window: PlannedWindow) async throws
    func delete(id: UUID) async throws
}

protocol ActualWindowRepository {
    func fetchWindows(for dateInterval: DateInterval) async throws -> [ActualWindow]
    func create(_ window: ActualWindow) async throws
    func update(_ window: ActualWindow) async throws
}

protocol CommandRunRepository {
    func create(_ run: CommandRun) async throws
    func update(_ run: CommandRun) async throws
    func fetchRecent(limit: Int, filter: CommandRunFilter) async throws -> [CommandRun]
}

protocol ScheduledPromptRepository {
    func create(_ prompt: ScheduledPrompt) async throws
    func fetchDuePrompts(now: Date) async throws -> [ScheduledPrompt]
    func markRunning(id: UUID) async throws
    func markSucceeded(id: UUID) async throws
    func markFailed(id: UUID, error: String) async throws
}
```

---

## 9. Provider Integration Plan

### Provider abstraction

```swift
protocol ProviderAdapter: Sendable {
    var id: ProviderID { get }
    var displayName: String { get }

    func detectStatus() async throws -> ProviderStatus
    func collectUsage() async throws -> UsageSnapshot
    func triggerPrompt(_ input: TriggerPromptInput) async throws -> CommandRun
    func runTestCommand() async throws -> CommandRun
}
```

### ProviderStatus

```swift
struct ProviderStatus: Codable, Sendable {
    var providerID: ProviderID
    var isInstalled: Bool
    var cliPath: String?
    var version: String?
    var isAuthenticated: Bool?
    var lastCheckedAt: Date
    var errorMessage: String?
}
```

### TriggerPromptInput

```swift
struct TriggerPromptInput: Codable, Sendable {
    var prompt: String
    var projectPath: String?
    var mode: TriggerPromptMode
}

enum TriggerPromptMode: String, Codable, Sendable {
    case newSession
    case continueLast
    case resumeSession
}
```

### Claude adapter responsibilities

```txt
ClaudeProviderAdapter
├─ resolve CLI path
├─ detect installed state
├─ detect auth state
├─ run prompt command
├─ collect usage, if available
├─ parse stdout/stderr
└─ write CommandRun through service/repository
```

### Codex adapter responsibilities

```txt
CodexProviderAdapter
├─ resolve CLI path
├─ detect installed state
├─ detect auth state
├─ run prompt command
├─ collect usage, if available
├─ parse JSON/NDJSON output, if available
└─ write CommandRun through service/repository
```

### Provider registry

```swift
final class ProviderRegistry {
    private let adapters: [ProviderID: any ProviderAdapter]

    init(adapters: [any ProviderAdapter]) {
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.id, $0) })
    }

    func adapter(for id: ProviderID) throws -> any ProviderAdapter {
        guard let adapter = adapters[id] else {
            throw C5hError.providerNotConfigured(id.rawValue)
        }
        return adapter
    }
}
```

---

## 10. CLI Runner Plan

### Key rules

The CLI runner must be safe and boring.

Rules:

- Never build shell strings.
- Never call `/bin/sh -c` for provider commands.
- Always use executable URL + argument array.
- Always capture stdout and stderr.
- Always persist command start/end/status.
- Always support timeout.
- Always redact secrets in UI/logs.
- Always record working directory.

### CommandSpec

```swift
struct CommandSpec: Sendable {
    var providerID: ProviderID
    var runType: CommandRunType
    var executableURL: URL
    var arguments: [String]
    var workingDirectory: URL?
    var environment: [String: String]
    var timeoutSeconds: TimeInterval
}
```

### CommandRunner API

```swift
protocol CommandRunning: Sendable {
    func run(_ spec: CommandSpec) async throws -> CommandRun
}
```

### CommandRunner implementation shape

```swift
actor CommandRunner: CommandRunning {
    private let logWriter: FileLogWriting
    private let commandRunRepository: CommandRunRepository

    init(
        logWriter: FileLogWriting,
        commandRunRepository: CommandRunRepository
    ) {
        self.logWriter = logWriter
        self.commandRunRepository = commandRunRepository
    }

    func run(_ spec: CommandSpec) async throws -> CommandRun {
        let id = UUID()
        let startedAt = Date()

        var run = CommandRun(
            id: id,
            providerID: spec.providerID,
            runType: spec.runType,
            command: spec.executableURL.path,
            argumentsJSON: encodeArguments(spec.arguments),
            workingDirectory: spec.workingDirectory?.path,
            startedAt: startedAt,
            endedAt: nil,
            exitCode: nil,
            status: .running,
            stdoutPath: nil,
            stderrPath: nil,
            parsedEventsJSON: nil,
            errorMessage: nil
        )

        try await commandRunRepository.create(run)

        // Implementation detail:
        // - configure Process
        // - stream stdout/stderr to files
        // - race process termination against timeout
        // - update CommandRun row

        return run
    }
}
```

### Streaming stdout/stderr

Do not buffer large output in memory.

Preferred v1:

```txt
Process stdout pipe → async file append → logs/{commandRunID}.stdout.log
Process stderr pipe → async file append → logs/{commandRunID}.stderr.log
```

Recommended file layout:

```txt
~/Library/Application Support/C5h/logs/
├─ command-runs/
│  ├─ 2026-05/
│  │  ├─ <commandRunID>.stdout.log
│  │  └─ <commandRunID>.stderr.log
```

### CLI path resolution

Provider CLI can be in different locations:

```txt
/opt/homebrew/bin
/usr/local/bin
/usr/bin
custom path from settings
```

Implement:

```swift
protocol CLIPathResolving {
    func resolveCLI(named executableName: String, configuredPath: String?) async -> URL?
}
```

Resolution order:

1. User-configured path.
2. Known Homebrew Apple Silicon path: `/opt/homebrew/bin/<name>`.
3. Known Homebrew Intel path: `/usr/local/bin/<name>`.
4. `which <name>` using a safe controlled command.
5. Not installed.

### Environment resolution

GUI macOS apps often do not inherit the same PATH as Terminal.

Use explicit PATH:

```swift
let defaultCLIPath = [
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/usr/bin",
    "/bin",
    "/usr/sbin",
    "/sbin"
].joined(separator: ":")
```

Allow override in advanced settings.

---

## 11. Scheduling Plan

### MVP scheduling inside main app

For initial MVP, scheduling can run only while the app is open.

This is acceptable for development only.

```txt
Main app SchedulerService
├─ periodic tick every 30s
├─ reads due scheduled_prompts
├─ runs CLI command
└─ writes results
```

### Production scheduling with Swift helper

Add a helper target after manual triggering works.

```txt
C5h.app
  ├─ user creates schedule
  ├─ writes scheduled_prompts
  └─ registers helper

C5hHelper.app
  ├─ started by LaunchAgent
  ├─ opens same SQLite database
  ├─ runs scheduler loop
  ├─ executes provider commands
  └─ writes command_runs / actual_windows
```

### Scheduler state machine

```txt
scheduled → due → running → succeeded
                    ├─ failed
                    ├─ missed
                    └─ cancelled
```

### SchedulerService

```swift
actor SchedulerService {
    private let scheduledPromptRepository: ScheduledPromptRepository
    private let providerRegistry: ProviderRegistry
    private let actualWindowRepository: ActualWindowRepository

    func tick(now: Date = .now) async {
        do {
            let duePrompts = try await scheduledPromptRepository.fetchDuePrompts(now: now)

            for prompt in duePrompts {
                await run(prompt)
            }
        } catch {
            // Persist scheduler error somewhere visible in Settings / Logs.
        }
    }

    private func run(_ prompt: ScheduledPrompt) async {
        do {
            try await scheduledPromptRepository.markRunning(id: prompt.id)

            let adapter = try providerRegistry.adapter(for: prompt.providerID)
            let commandRun = try await adapter.triggerPrompt(
                TriggerPromptInput(
                    prompt: prompt.prompt,
                    projectPath: prompt.projectPath,
                    mode: .newSession
                )
            )

            let actualWindow = ActualWindow(
                id: UUID(),
                providerID: prompt.providerID,
                startAt: commandRun.startedAt,
                endAt: Calendar.current.date(byAdding: .hour, value: 5, to: commandRun.startedAt)!,
                source: .c5hTriggered,
                confidence: .exact,
                commandRunID: commandRun.id,
                usageStartSnapshotID: nil,
                usageEndSnapshotID: nil,
                createdAt: .now,
                updatedAt: .now
            )

            try await actualWindowRepository.create(actualWindow)
            try await scheduledPromptRepository.markSucceeded(id: prompt.id)
        } catch {
            try? await scheduledPromptRepository.markFailed(id: prompt.id, error: String(describing: error))
        }
    }
}
```

### Missed job handling

If a scheduled prompt is overdue:

```txt
within grace window, e.g. 15 min:
  run it

after grace window:
  mark as missed
  notify user
```

Settings:

```txt
Missed prompt grace period: 5 / 15 / 30 / 60 minutes
Default: 15 minutes
```

### Do not create one LaunchAgent per prompt

Use one helper worker.

```txt
launchd keeps helper alive
helper checks SQLite for due jobs
```

This is simpler, more reliable, and easier to debug.

---

## 12. Background Helper Plan

Add this after core MVP.

### Helper target

```txt
C5hHelper.app
├─ no visible UI
├─ imports shared core/store code
├─ opens C5h SQLite database
├─ runs scheduler loop
└─ exits or stays alive depending on launchd config
```

### Helper lifecycle

Settings UI:

```txt
[ ] Start C5h helper at login
[ ] Allow scheduled prompts while main app is closed
```

### Helper status model

```swift
struct HelperStatus: Codable, Sendable {
    var isRegistered: Bool
    var isRunning: Bool
    var lastHeartbeatAt: Date?
    var lastError: String?
}
```

### Heartbeat

Helper writes heartbeat to `app_settings` or a dedicated table:

```sql
create table helper_heartbeats (
  id text primary key,
  helper_version text not null,
  started_at text not null,
  last_seen_at text not null,
  pid integer
);
```

The main app reads heartbeat and shows status.

### Helper communication

For v1 helper, avoid IPC.

Use SQLite as shared state:

```txt
Main app writes:
- planned_windows
- scheduled_prompts
- settings

Helper writes:
- command_runs
- actual_windows
- usage_snapshots
- helper heartbeat
```

Later IPC can be added for live streaming, but it is not required for v1.

---

## 13. Dashboard Plan

Dashboard should answer:

```txt
What is happening now?
What is scheduled next?
Did the last CLI run succeed?
How much provider activity happened today?
```

Components:

```txt
DashboardView
├─ ActiveWindowsSection
│  ├─ Claude active window card
│  └─ Codex active window card
│
├─ NextScheduledPromptCard
├─ TodayUsageSummary
├─ RecentCommandRunsCard
└─ QuickActions
   ├─ Start Claude window now
   ├─ Start Codex window now
   └─ Open Logs
```

### Quick action behavior

Clicking “Start Claude window now”:

```txt
1. Open prompt sheet.
2. Choose project path.
3. Choose prompt template.
4. Click Run.
5. ProviderService.triggerPrompt.
6. Create actual window.
7. Navigate or update Today calendar.
```

---

## 14. Logs Page Plan

The Logs page is the audit trail for every provider CLI call.

### Requirements

Show all calls to provider CLIs:

- status,
- provider,
- usage,
- trigger prompts,
- stdout/stderr,
- duration,
- exit code,
- working directory,
- linked window.

### Logs table columns

```txt
Started At
Provider
Type
Status
Duration
Exit
Project
Prompt Preview
Usage Delta
```

### Detail pane

```txt
CommandRunDetailView
├─ Summary
│  ├─ provider
│  ├─ status
│  ├─ started / ended
│  ├─ duration
│  ├─ exit code
│  ├─ cwd
│  └─ command args, redacted
│
├─ Prompt
├─ stdout
├─ stderr
├─ parsed events
└─ linked planned/actual window
```

### Filtering

MVP filters:

```txt
Provider: All / Claude / Codex
Status: All / Running / Succeeded / Failed
Type: All / Trigger Prompt / Usage / Auth / Test
Date range: Today / Last 7 days / Custom
Search: prompt, cwd, error
```

---

## 15. Providers Page Plan

### Provider card

Each provider card shows:

```txt
Claude Code
├─ Enabled toggle
├─ Installed: yes/no
├─ CLI path
├─ Version
├─ Auth status
├─ Last checked
├─ Test command button
├─ Choose custom CLI path
├─ Default project path
└─ Default prompt template
```

Same for Codex.

### Provider actions

```txt
Detect CLI
Check auth
Run test command
Open logs filtered by provider
Choose CLI path
Reset provider settings
```

### Status states

```swift
enum ProviderHealthState {
    case unknown
    case ready
    case cliMissing
    case authMissing
    case error(String)
}
```

---

## 16. Settings Plan

### General

```txt
Default window length: 5h
Default calendar start: Today
Default project path
Confirm before running scheduled prompt: yes/no
```

### Scheduler

```txt
Enable helper
Start helper at login
Scheduler tick interval
Missed prompt grace period
Retry failed prompt count
Notify on success/failure
```

### Providers

```txt
Claude CLI path
Codex CLI path
PATH override
Default provider
```

### Logs

```txt
Log retention: 7 / 30 / 90 / forever
Max stdout/stderr file size
Export debug bundle
Open logs folder
```

### Advanced

```txt
Database location
Reset local database
Re-run migrations
Show helper heartbeat
Show app environment
```

---

## 17. Notifications Plan

Use notifications for:

```txt
Scheduled prompt started
Scheduled prompt succeeded
Scheduled prompt failed
Scheduled prompt missed
5h window ending soon
Provider CLI missing
Provider auth problem
```

Notification settings:

```txt
[ ] Notify when scheduled prompt starts
[ ] Notify when command succeeds
[ ] Notify when command fails
[ ] Notify 10 minutes before window ends
```

Notification payload should include:

```txt
Provider
Prompt/window title
Status
Click action: open C5h Logs or Today view
```

---

## 18. Error Handling Plan

### App error enum

```swift
enum C5hError: LocalizedError {
    case providerNotConfigured(String)
    case cliNotFound(String)
    case authMissing(ProviderID)
    case processLaunchFailed(String)
    case processTimedOut
    case databaseError(String)
    case invalidProjectPath(String)
    case schedulerError(String)

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured(let id):
            "Provider not configured: \(id)"
        case .cliNotFound(let name):
            "CLI not found: \(name)"
        case .authMissing(let provider):
            "Authentication missing for \(provider.displayName)"
        case .processLaunchFailed(let message):
            "Could not launch process: \(message)"
        case .processTimedOut:
            "Command timed out"
        case .databaseError(let message):
            "Database error: \(message)"
        case .invalidProjectPath(let path):
            "Invalid project path: \(path)"
        case .schedulerError(let message):
            "Scheduler error: \(message)"
        }
    }
}
```

### User-facing error rules

- Logs page shows full technical detail.
- Toast/banner shows short actionable message.
- Provider page shows setup guidance.
- Settings → Advanced shows debug info.

Examples:

```txt
CLI missing:
  “Claude Code CLI was not found. Choose a custom path or install it.”

Auth missing:
  “Codex CLI is installed, but C5h could not verify authentication.”

Prompt failed:
  “Claude prompt failed with exit code 1. Open logs.”
```

---

## 19. Security and Privacy Plan

### Principles

- Local-first.
- No cloud backend in v1.
- Do not upload prompts/logs.
- Do not store provider credentials.
- Do not shell-interpolate user input.
- Redact sensitive environment values in logs.

### Sensitive data handling

Potentially sensitive:

```txt
Prompts
Project paths
stdout/stderr logs
Provider CLI output
Environment variables
```

Rules:

```txt
- Store logs locally only.
- Provide log retention settings.
- Provide delete/export options.
- Redact env vars with names containing TOKEN, KEY, SECRET, PASSWORD.
- Do not log full environment by default.
```

### Command execution safety

Bad:

```swift
process.executableURL = URL(fileURLWithPath: "/bin/sh")
process.arguments = ["-c", "claude -p \(prompt)"]
```

Good:

```swift
process.executableURL = claudeURL
process.arguments = ["-p", prompt]
```

---

## 20. Testing Strategy

### Unit tests

```txt
Domain models
Date interval calculations
Calendar y-position calculations
Provider registry
CLI path resolver
Command argument construction
Scheduler state machine
Repository CRUD
Migration tests
```

### Integration tests

```txt
SQLite database setup
Repository queries
CommandRunner with fake CLI executable
stdout/stderr capture
timeout behavior
failed process behavior
scheduled prompt execution with fake provider
```

### UI tests

```txt
Navbar tab switching
Today view loads planned/actual windows
Create planned window flow
Manual trigger flow with fake provider
Logs filtering
Provider setup screen
Settings toggles
```

### Fake provider CLI

Create a small test executable/script for integration tests:

```txt
fake-provider-cli
├─ exits 0
├─ exits 1
├─ prints stdout
├─ prints stderr
├─ sleeps for timeout test
└─ emits JSON lines
```

### Preview data

Create realistic preview data:

```txt
Today:
- Claude planned 09:00–14:00
- Claude actual 09:07–14:07
- Codex planned 15:00–20:00
- failed Claude test command

Tomorrow:
- Codex scheduled 10:00–15:00

Week:
- several planned/actual windows
```

---

## 21. Milestone Plan

## Milestone 0 — Project foundation

Goal: app opens, compiles, and has a clean structure.

Tasks:

- Create macOS SwiftUI app target.
- Add minimum supported macOS version.
- Add app icon placeholder.
- Add root window.
- Add navbar and tab switching.
- Add empty page placeholders.
- Add design system colors and spacing.
- Add basic app settings model.

Acceptance criteria:

- App launches.
- Navbar visible.
- All tabs switch.
- Window min size works.
- App builds cleanly.

---

## Milestone 1 — Database foundation

Goal: persistent local database is ready.

Tasks:

- Add GRDB dependency.
- Implement `AppPaths`.
- Create SQLite database at Application Support path.
- Enable WAL mode.
- Add migrations.
- Create tables:
  - providers,
  - planned_windows,
  - actual_windows,
  - scheduled_prompts,
  - command_runs,
  - usage_snapshots,
  - prompt_templates,
  - app_settings.
- Seed initial providers.
- Add repository protocols.
- Add repository implementations.
- Add migration tests.

Acceptance criteria:

- DB created on first launch.
- Providers seeded.
- Migrations run once.
- App can read/write planned windows.
- App can read/write command runs.

---

## Milestone 2 — Logs MVP

Goal: show command-run history before real commands exist.

Tasks:

- Build `LogsView`.
- Build `CommandRunTable`.
- Build `CommandRunDetailView`.
- Add filters.
- Add fake seed command runs for development.
- Add stdout/stderr file viewer.
- Add copy-to-clipboard actions.

Acceptance criteria:

- Logs table shows rows from DB.
- Selecting a row shows details.
- stdout/stderr viewer works with sample files.
- Filters work for provider/status/type.

---

## Milestone 3 — CLI runner MVP

Goal: run controlled local commands and persist logs.

Tasks:

- Implement `CommandSpec`.
- Implement `CommandRunner`.
- Implement stdout/stderr file writing.
- Implement exit code capture.
- Implement command timeout.
- Implement cancellation hook.
- Persist command run before and after execution.
- Add fake CLI integration tests.

Acceptance criteria:

- Running fake CLI creates command run.
- stdout/stderr files are saved.
- exit code is persisted.
- timeout marks command as timedOut.
- Logs page shows real command runs.

---

## Milestone 4 — Provider detection

Goal: detect Claude and Codex CLI status.

Tasks:

- Implement `CLIPathResolver`.
- Implement provider settings for CLI paths.
- Implement `ProviderRegistry`.
- Implement basic `ClaudeProviderAdapter.detectStatus()`.
- Implement basic `CodexProviderAdapter.detectStatus()`.
- Build Providers page cards.
- Add “Detect CLI” button.
- Add “Run test command” button.

Acceptance criteria:

- Providers page shows Claude/Codex status.
- User can set custom CLI path.
- Test command creates log entry.
- Missing CLI state is clear and actionable.

---

## Milestone 5 — Today calendar MVP

Goal: render planned and actual windows.

Tasks:

- Implement `DayCalendarScreen`.
- Implement `DayCalendarView`.
- Implement `TimeRulerView`.
- Implement `ProviderColumnView`.
- Implement `PlannedWindowBlockView`.
- Implement `ActualWindowBlockView`.
- Implement current time line.
- Load planned/actual windows from DB.
- Add preview/seed data.
- Add block detail popover.

Acceptance criteria:

- Today view shows 00:00–24:00.
- Claude and Codex columns are visible.
- Planned blocks are narrow.
- Actual blocks are wider.
- Colors are provider-specific.
- Clicking block opens details.

---

## Milestone 6 — Create planned windows

Goal: user can create/edit scheduled 5h windows.

Tasks:

- Add “Create planned window” action.
- Add planned window editor sheet.
- Fields:
  - provider,
  - start date/time,
  - duration,
  - prompt template,
  - prompt body,
  - project path.
- Save planned window.
- Optionally create scheduled prompt.
- Edit/delete planned window.
- Add conflict/overlap warning.

Acceptance criteria:

- User can create Claude/Codex planned window.
- Window appears on Today/Tomorrow calendar.
- User can edit/delete it.
- Scheduled prompt row is created when enabled.

---

## Milestone 7 — Manual trigger

Goal: user can start a 5h provider window now.

Tasks:

- Add “Start Claude now” action.
- Add “Start Codex now” action.
- Add prompt/project selection sheet.
- Call provider adapter `triggerPrompt`.
- Create command run.
- Create actual window.
- Show command in Logs.
- Show actual window in Today view.

Acceptance criteria:

- User can manually trigger provider CLI.
- Command run appears in Logs.
- Actual 5h window appears in Today.
- Failure is shown clearly.

---

## Milestone 8 — Scheduler inside main app

Goal: scheduled prompts run while the app is open.

Tasks:

- Implement `SchedulerService`.
- Add periodic app timer/task.
- Fetch due scheduled prompts.
- Mark as running/succeeded/failed/missed.
- Run provider adapter.
- Create actual windows.
- Add scheduler status UI.
- Add scheduler logs.

Acceptance criteria:

- Scheduled prompt runs when app is open.
- Status transitions are persisted.
- Missed prompts are marked.
- Actual windows are created from successful runs.

---

## Milestone 9 — Dashboard MVP

Goal: quick overview.

Tasks:

- Active windows cards.
- Next scheduled prompt card.
- Recent command runs.
- Provider health cards.
- Quick actions.

Acceptance criteria:

- Dashboard shows current/next state.
- User can start provider window from dashboard.
- User can jump to Logs/Today.

---

## Milestone 10 — Week calendar

Goal: weekly overview.

Tasks:

- Implement week date model.
- Build compact week grid.
- Reuse provider colors and block components.
- Show planned/actual states.
- Click block opens detail.
- Navigate previous/next week.

Acceptance criteria:

- Week view shows all planned/actual windows for the week.
- Blocks are clickable.
- Provider grouping is clear.

---

## Milestone 11 — Swift helper / LaunchAgent

Goal: scheduled prompts run even when the main app is closed.

Tasks:

- Add `C5hHelper` target.
- Move shared services into reusable modules if needed.
- Helper opens same database.
- Helper writes heartbeat.
- Helper runs scheduler loop.
- Main app can enable/disable helper.
- Add `SMAppService` registration.
- Add helper status UI.
- Add helper logs.

Acceptance criteria:

- Helper can be registered from Settings.
- Helper runs scheduled prompts while main app is closed.
- Main app shows helper heartbeat.
- User can disable helper.

---

## Milestone 12 — Usage snapshots and inference

Goal: collect provider usage and infer actual windows.

Tasks:

- Add provider-specific usage collection where possible.
- Normalize usage snapshots.
- Store raw and normalized usage.
- Link usage snapshots to actual windows.
- Add usage summary to Dashboard.
- Add usage delta to Logs.
- Infer actual windows from usage when not triggered by C5h.

Acceptance criteria:

- Usage snapshots are stored.
- Dashboard shows per-provider usage summary.
- Actual windows can be manually/automatically linked to usage snapshots.

---

## Milestone 13 — Polish and release prep

Goal: make it shippable.

Tasks:

- App icon.
- Empty states.
- Error states.
- Loading states.
- Keyboard shortcuts.
- Menu commands.
- Export debug bundle.
- Log retention cleanup.
- Settings cleanup.
- Notarization/signing setup.
- Crash/log diagnostics.

Acceptance criteria:

- App feels stable.
- User can recover from missing provider setup.
- Logs/debug bundle help diagnose failures.
- Release build can be signed and packaged.

---

## 22. Development Order Recommendation

Build in this exact order:

```txt
1. App shell
2. Database
3. Logs page with fake data
4. Command runner with fake CLI
5. Provider detection
6. Today calendar with fake data
7. Create planned windows
8. Manual provider trigger
9. Scheduler while app is open
10. Dashboard
11. Week calendar
12. Swift helper / LaunchAgent
13. Usage snapshots
14. Polish/release
```

Reasoning:

- Logs before CLI makes command debugging visible.
- Fake CLI before real provider integration makes tests reliable.
- Manual trigger before scheduling reduces complexity.
- In-app scheduler before helper validates business logic.
- Helper last avoids premature macOS lifecycle complexity.

---

## 23. Important Implementation Notes

### Planned and actual windows must remain separate

Do not combine them into one generic event table too early.

```txt
planned_windows = user intent
actual_windows  = observed/triggered reality
```

This distinction is central to the product.

### Command runs are the audit log

Every provider CLI call must create a `command_runs` row, including:

```txt
detect status
auth status
usage collection
manual prompt trigger
scheduled prompt trigger
test command
```

### The calendar should not run commands

Bad dependency:

```txt
CalendarView → Process
```

Good dependency:

```txt
CalendarView → ViewModel → ProviderService → ProviderAdapter → CommandRunner
```

### Keep provider command construction isolated

Only provider adapters should know provider-specific CLI arguments.

```txt
ClaudeProviderAdapter builds Claude commands.
CodexProviderAdapter builds Codex commands.
CommandRunner only runs a CommandSpec.
```

### Avoid helper too early

The helper is important, but it should not be milestone 1.

First validate:

- DB,
- CLI runner,
- logs,
- provider detection,
- manual trigger,
- calendar.

Then add helper.

---

## 24. First Vertical Slice

The first truly valuable slice is:

```txt
Open C5h
→ Providers tab detects Claude/Codex
→ Start Claude now
→ CommandRunner runs CLI
→ command_runs row created
→ stdout/stderr saved
→ Logs page shows command
→ Today page shows actual 5h Claude window
```

Build this before scheduling.

This proves the core product loop.

---

## 25. Risks and Mitigations

### Risk: GUI app cannot find CLI installed in shell PATH

Mitigation:

- Explicit PATH fallback.
- CLI path resolver.
- Custom CLI path setting.
- Provider setup screen.

### Risk: provider CLI output changes

Mitigation:

- Store raw stdout/stderr.
- Store parsed events separately.
- Keep parsers tolerant.
- Show raw logs in UI.

### Risk: scheduled prompt runs twice

Mitigation:

- DB transaction when claiming due prompt.
- Status transition `scheduled → running` must be atomic.
- Add `attempts` counter.

### Risk: app closed during scheduled prompt

Mitigation:

- v1 in-app scheduler clearly marked as “requires app open.”
- production helper added later.

### Risk: long CLI output consumes memory

Mitigation:

- Stream stdout/stderr to files.
- Do not buffer full output in memory.
- Add max file size later.

### Risk: logs contain sensitive data

Mitigation:

- Local-only storage.
- Redaction.
- Retention settings.
- Delete/export tools.

---

## 26. Definition of Done for v1

C5h v1 is done when:

```txt
- App launches as a native macOS SwiftUI app.
- Navbar has all required tabs.
- Providers page detects Claude and Codex CLIs.
- User can configure CLI paths.
- User can manually trigger Claude/Codex prompt.
- All CLI calls are logged.
- stdout/stderr are viewable.
- Today view shows provider columns.
- Planned windows are narrow blocks.
- Actual windows are wider blocks.
- User can create/edit/delete planned windows.
- Scheduler can run due prompts while app is open.
- Logs and Dashboard make failures understandable.
- Data persists across restarts.
```

C5h v1.1 is done when:

```txt
- Swift helper runs scheduled prompts while main app is closed.
- Helper can be enabled/disabled from Settings.
- Helper heartbeat is visible.
- Missed scheduled prompts are detected.
```

---

## 27. Future Extensions

Potential future work:

```txt
- Apple Calendar integration via EventKit.
- Menu bar mini controller.
- Global shortcut: Start provider window.
- Prompt template library.
- Project-specific schedules.
- Usage budget warnings.
- Provider session linking.
- Export timeline as Markdown/CSV.
- Debug bundle generator.
- Native charts for usage over time.
- Optional Rust command engine if Swift runner becomes limiting.
```

---

## 28. Final Recommendation

Start with:

```txt
Full SwiftUI macOS app
+ GRDB database
+ Foundation Process CLI runner
+ custom SwiftUI provider calendar
```

Build the first vertical slice before background scheduling:

```txt
Provider detection
→ manual prompt trigger
→ logs
→ actual window on Today calendar
```

Then add:

```txt
planned windows
→ in-app scheduler
→ Swift LaunchAgent helper
```

This keeps the implementation simple while preserving the long-term architecture C5h needs.
