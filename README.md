# C5h - AI Tool Usage Tracker

A macOS menu bar application to visualize and optimize AI coding tool usage windows (Claude Code, Codex, Gemini). Track rolling usage windows, display them in a calendar view, and schedule automatic window triggers via macOS launchd.

## Features

- **Real-Time Monitoring**: Detect CLI usage via local process monitoring plus periodic usage polling
- **Menu Bar Integration**: Status at a glance with percentage display and quick popover access
- **Calendar View**: Visual week-by-week timeline of usage windows
- **Statistics Dashboard**:
  - Selected-week totals and per-day breakdowns
  - Selected-week day-of-week and time-of-day distributions
  - Rolling 8-week duration trend
  - Account-specific breakdowns
- **Smart Scheduling**: Automatic window triggers via macOS launchd
- **Multi-Account Support**: Track multiple AI tools and accounts simultaneously
- **Notifications**: System notifications for window endings

## Tech Stack

- **Frontend**: React + TypeScript + Vite
- **Backend**: Rust + Tauri 2.0
- **Database**: SQLite with migrations
- **UI**: shadcn/ui + Tailwind CSS
- **Charts**: Recharts
- **State Management**: Zustand

## Project Structure

```
C5h/
├── src-react/           # React frontend
│   ├── components/      # UI components
│   ├── hooks/          # Custom React hooks
│   ├── store/          # Zustand state management
│   └── lib/            # API layer and utilities
├── src-tauri/          # Rust backend
│   └── src/
│       ├── commands/   # Tauri command handlers
│       ├── services/   # Business logic (monitor, parser)
│       ├── db.rs       # SQLite migrations
│       └── models.rs   # Data models
└── Docs/               # Specifications and planning
```

## Getting Started

### Prerequisites

- Node.js 18+ and Bun
- Rust 1.70+
- Xcode Command Line Tools (macOS)

### Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/c5h.git
cd c5h
```

2. Install dependencies:
```bash
bun install
```

3. Run in development mode:
```bash
bun tauri dev
```

### Building

```bash
bun tauri build
```

The built application will be in `src-tauri/target/release/bundle/`.

## Usage

### First Launch

1. The app will appear in your menu bar with a gray "—" icon
2. Click the icon to open the popover
3. Go to Settings to configure accounts

### Adding Accounts

1. Open Settings → Accounts
2. Click "Add Account"
3. Configure:
   - Name (e.g., "Claude Code")
   - Tool Type (claude, codex, gemini)
   - CLI Command
   - Scheduled trigger args (optional, used only when launchd runs the account)
   - Window duration (hours)
   - Color for visual distinction

### Monitoring Usage

The app automatically detects when you run configured CLI tools:
- Menu bar icon updates to show current usage percentage
- Windows appear in the calendar view
- Real-time progress bar in the popover

### Scheduling

1. Open **Scheduled Triggers** in Settings, or click a calendar time slot
2. Create a schedule using local date and local time
3. Install the schedule to launchd for the chosen account

## Architecture

### Frontend (React)

- **State Management**: Zustand store with async actions
- **Components**: Modular, reusable UI components
- **Hooks**: Custom hooks for data fetching and business logic
- **API Layer**: Type-safe Tauri IPC bridge

### Backend (Rust)

- **Commands**: Tauri command handlers for IPC
- **Services**:
  - Process monitor for real-time CLI detection
  - Output parser for usage data extraction
- **Database**: SQLite with schema migrations
- **Scheduler**: macOS launchd integration for triggers

### Real-Time Monitoring

The app uses a hybrid approach:
1. **Process Watcher**: Monitors running processes for CLI tools
2. **Usage Polling**: Refreshes live CLI usage while an active window exists
3. **Manual Windows**: Lets you start/end windows directly if monitoring is unavailable

## Development

### Running Tests

Frontend tests:
```bash
bun test           # watch mode
bun test:run       # single run (CI)
bun test:coverage  # with V8 coverage report
```

Backend tests:
```bash
cd src-tauri && cargo test
```

Backend coverage (requires `cargo install cargo-llvm-cov`):
```bash
cd src-tauri && cargo llvm-cov --open    # generates HTML report and opens it
cd src-tauri && cargo llvm-cov --summary-only
```

### E2E testing (manual, local-only)

End-to-end smoke tests use [`tauri-pilot`](https://github.com/mpiton/tauri-pilot), gated behind the `e2e` Cargo feature so the test socket is never linked into a shipped binary.

One-time setup:
```bash
rustup update stable                # tauri-pilot v0.5.0 requires rustc >= 1.95.0
cargo install tauri-pilot-cli
```

Run the app with the `e2e` feature in one terminal:
```bash
bun run tauri:e2e
```

In a second terminal, drive scenarios via the CLI:
```bash
tauri-pilot snapshot -i        # inspect accessibility tree, get @eN refs
bun run test:e2e               # run e2e/smoke.toml
```

Scenarios live in `e2e/*.toml`. The `tauri-plugin-pilot` dependency is `optional = true` and only compiled when `--features e2e` is passed; default `bun run tauri dev` and release builds remain unchanged.

### Code Structure

See detailed documentation:
- [Frontend Architecture](src-react/README.md)
- [Components](src-react/components/README.md)
- [Hooks](src-react/hooks/README.md)
- [Backend](src-tauri/README.md)
- [Commands](src-tauri/src/commands/README.md)

## Configuration

### Database

Location: `~/Library/Application Support/com.zaai.c5h/c5h.db`

### Scheduled Jobs

Plists stored in: `~/Library/LaunchAgents/com.zaai.c5h.trigger.{id}.plist`

### Settings

Configurable via the Settings UI:
- Notifications enabled/disabled
- Window ending soon notifications
- Monitoring poll interval

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details

## Acknowledgments

- Built with [Tauri](https://tauri.app/)
- UI components from [shadcn/ui](https://ui.shadcn.com/)
- Icons from [Lucide](https://lucide.dev/)
