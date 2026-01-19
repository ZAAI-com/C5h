# C5h Plan

## The Problem

The 5-hour usage window in Claude Code gets consumed quickly, often running out during peak productivity hours.

## The Solution

C5h solves two key issues:

1. **Visualize usage** — See your 5h and weekly limits at a glance
2. **Optimize timing** — Start new windows strategically (e.g., while you sleep)

## App Features

- **Calendar week view** — Each 5h window displayed as a calendar entry
- **Scheduler** — Automatically trigger a new window at a scheduled time
- **Menu bar widget** — Quick access to remaining time and stats
- **Multi-account support** — Track Claude Code, Codex, Gemini, and additional accounts

---

## Supported AI Tools

| Company | Tool | Model(s) | Window Duration | Limit | Window Start | CLI |
| --- | --- | --- | --- | --- | --- | --- |
| Anthropic | Claude Code | Sonnet, Opus | 5 hours | ~11 windows/week | Full hour | `claude` |
| OpenAI | Codex | GPT-5.2 Codex | 5 hours | ~99% weekly | Any minute | `codex` |
| Google | Gemini CLI | 2.5 Flash, 2.5 Pro, 3 Flash, 3 Pro | 24 hours | Daily quota per model | N/A | `gemini` |
| Anthropic | Claude Code (2nd) | Sonnet, Opus | 5 hours | ~11 windows/week | Full hour | Custom |

Each account can have its own:
- Scheduled trigger time
- Color in calendar view
- Independent window tracking
- Multiple schedules (as long as windows don't overlap)

---

## Window Detection & Triggering

### How to Detect Active Windows

**Claude Code:**
Run `/usage` inside Claude Code to see:
```
  Current session
  █████████████████████████████████████▌             75% used
  Resets 1:59am (Europe/Berlin)

  Current week (all models)
  ██████████████████████▌                            45% used
  Resets Jan 22 at 10:59am (Europe/Berlin)

  Current week (Sonnet only)
                                                     0% used
```
- Shows current session (5h window) percentage used and reset time
- Shows weekly limit for all models and Sonnet-only
- Reset times shown in local timezone

**Codex (OpenAI):**
Run `/status` inside Codex to see:
```
│  5h limit:       [████████████████████] 100% left (resets 06:44)          │
│  Weekly limit:   [████████████████████] 99% left (resets 19:51 on 24 Jan) │
```
- Shows 5h window remaining percentage and reset time
- Shows weekly limit percentage and reset date/time
- Model info: gpt-5.2-codex (reasoning xhigh, summaries auto)

**Gemini CLI:**
The usage is displayed when running `gemini` - shows a table with:
- Model name (gemini-2.5-flash, gemini-2.5-pro, etc.)
- Number of requests made
- Usage percentage remaining (e.g., 99.9%)
- Reset time (24 hours from first use)

### How to Trigger a New Window
Send a simple prompt to start the 5h window:
```bash
claude -p "1+1"
```

### Window Timing Rules
- **Claude Code:** Windows always start on the full hour (e.g., 3:00 AM, 4:00 AM)
- **Codex:** Windows start on any minute (e.g., 3:15 AM, 3:16 AM) - more flexible than Claude
- **Gemini:** No windows - uses rolling 24-hour daily limit per model
- **Overlapping windows:**
  - ✅ OK across different LLM tools (Claude + Codex + Gemini can overlap)
  - ❌ Not OK for the same account (can't have two Claude windows at once)

### Usage Model Comparison

| Tool | Limit Type | Reset Behavior | Scheduling Need |
| --- | --- | --- | --- |
| Claude Code | 5h rolling window | Window expires 5h after start | High - optimize window starts |
| Codex | 5h window + weekly cap | 5h window resets, weekly resets on fixed day | High - similar to Claude |
| Gemini | Daily quota per model | Resets 24h after first use | Low - just track usage |

---

## Scheduling UI Features

**Schedule Type:** One-time schedules only (not recurring)

Users can create a one-time schedule by:
- **Click** on a time slot in the calendar to create a schedule at that time

Multiple schedules per account are allowed, as long as the resulting windows don't overlap.

---

## Window Detection

**Detection Method:** Poll CLI every 15 minutes

The app periodically runs the CLI detection commands to check for active windows:
- Claude Code: Opens `claude` and runs `/usage`
- Codex: Opens `codex` and runs `/status`
- Gemini: Opens `gemini` to see usage table

**Poll Interval:** 15 minutes (configurable in settings)

---

## Menu Bar Widget

**Icon Display:** Shows percentage used (e.g., "75%")

**Menu Bar Popover includes:**
- Current window status and time remaining
- **Quick Start Window button** - one-click to trigger a new window
- Mini calendar showing today's windows
- Link to open main app

---

## Notifications

C5h sends the following notifications:

| Notification | When | Content |
| --- | --- | --- |
| Window ending soon | 30 min and 15 min before | "Your Claude Code window expires in 30 minutes" |
| Scheduled trigger success | After scheduled trigger runs | "New Claude Code window started successfully" |
| Scheduled trigger failed | If trigger fails | "Failed to start Claude Code window - check CLI" |
| Weekly summary | Sunday evening | "This week: 8 windows used, avg 4.2h each" |

---

## Architecture Decisions

### Decision 1: Desktop Framework

| Option | Tauri (Rust) | Electron | Swift/AppKit (Native) |
| --- | --- | --- | --- |
| **Bundle Size** | ~3-10 MB | ~150-200 MB | ~2-5 MB |
| **Memory Usage** | Low (~30 MB) | High (~150+ MB) | Lowest (~20 MB) |
| **Development Speed** | Medium | Fast | Slow |
| **Menu Bar Support** | ✅ Plugin available | ✅ Built-in Tray API | ✅ Native NSStatusItem |
| **Web UI** | ✅ WebView | ✅ Chromium | ❌ SwiftUI/AppKit only |
| **CLI Integration** | ✅ Rust Command | ✅ Node child_process | ✅ Process API |
| **Cross-platform** | ✅ Yes | ✅ Yes | ❌ macOS only |
| **Learning Curve** | Medium (Rust) | Low (JS/TS) | High (Swift) |

**🏆 Recommendation: Tauri**
- Lightweight and fast - important for a background app running 24/7
- Modern Rust backend is reliable for scheduled tasks
- WebView allows React/Vue UI without Chromium bloat
- Growing ecosystem with good menu bar support

---

### Decision 2: Frontend UI Framework

| Option | React | Vue 3 | Svelte |
| --- | --- | --- | --- |
| **Ecosystem** | Massive | Large | Growing |
| **Bundle Size** | ~40 KB | ~33 KB | ~2 KB |
| **Performance** | Good (Virtual DOM) | Good (Virtual DOM) | Excellent (No runtime) |
| **Component Libraries** | Extensive | Good | Limited |
| **Calendar Components** | Many options | Several | Few |
| **TypeScript Support** | Excellent | Excellent | Good |
| **Developer Pool** | Largest | Large | Small |

**🏆 Recommendation: React**
- Most calendar/charting libraries available (FullCalendar, React Big Calendar)
- Pairs well with Tauri (official examples)
- Easier to find help and resources
- shadcn/ui provides CLI-automated component setup

---

### Decision 2b: Calendar Component Library

| Option | FullCalendar | React Big Calendar | @schedule-x/react | ilamy Calendar | Shadcn Calendar | Custom (date-fns) |
| --- | --- | --- | --- | --- | --- | --- |
| **License** | MIT (Free) + Premium | MIT | MIT | Free | MIT | MIT |
| **Bundle Size** | ~150 KB | ~40 KB | ~30 KB | ~0 KB (zero deps) | ~5 KB | ~15 KB |
| **Week View** | ✅ Excellent | ✅ Good | ✅ Good | ✅ Excellent | ❌ Month only | 🔧 Build yourself |
| **Time Slots** | ✅ Hourly/custom | ✅ Hourly | ✅ 15min slots | ✅ Yes | ❌ No | 🔧 Build yourself |
| **Drag & Drop** | ✅ Built-in | ✅ Built-in | ✅ Built-in | ✅ Built-in | ❌ No | 🔧 Build yourself |
| **Customization** | High (CSS + API) | High (components) | Medium | Full (headless) | Full control | Full control |
| **TypeScript** | ✅ Excellent | ✅ Good | ✅ Good | ✅ Excellent | ✅ Excellent | ✅ Excellent |
| **Documentation** | Excellent | Good | Good | Good | Basic | N/A |
| **Active Maintenance** | Very active | Active | Active | Active | Active | N/A |

**Detailed Options:**

1. **FullCalendar** (`@fullcalendar/react`)
  - https://fullcalendar.io/
  - Most feature-complete calendar library
  - Premium plugins for timeline, resource scheduling (paid)
  - Excellent for complex time-based visualizations
  - Overkill for simple use cases

2. **React Big Calendar** (`react-big-calendar`)
  - https://jquense.github.io/react-big-calendar/
  - Google Calendar-like interface out of the box
  - Good balance of features and simplicity
  - Customizable event rendering
  - Works well with date-fns or moment.js

3. **Schedule-X** (`@schedule-x/react`)
  - https://schedule-x.dev/
  - Modern, lightweight alternative
  - Beautiful default styling
  - Plugin architecture
  - Newer but growing community

4. **ilamy Calendar** (`ilamy`)
  - https://ilamy.dev/
  - Zero dependencies core - extremely lightweight
  - Full headless UI architecture for complete styling control
  - Built with Tailwind CSS + shadcn/ui design system
  - Multiple views: month, week, day, year, resource
  - RRULE support for recurring events
  - Timezone and i18n support
  - Dark mode and responsive design built-in
  - Performance optimized for large datasets
  - Works with Next.js, Astro, and React
  - Newer library but modern architecture

4. **Shadcn Calendar** (`shadcn/ui calendar`)
  - https://ui.shadcn.com/docs/components/calendar
  - Beautiful month picker, integrates with shadcn ecosystem
  - Uses react-day-picker under the hood
  - No week/time view - would need custom extension
  - Best for date selection, not event display

5. **Custom Build** (date-fns + CSS Grid)
  - https://date-fns.org/
  - Full control over design and behavior
  - Smallest bundle size
  - More development effort
  - Best when you need something very specific

**🏆 Recommendation: ilamy Calendar**
- Native shadcn/ui + Tailwind integration matches our UI stack perfectly
- Zero dependencies - ideal for lightweight menu bar app
- Headless architecture gives full control over 5h window styling
- Excellent TypeScript support
- Built-in dark mode and responsive design
- Modern architecture aligned with current React patterns

---

### Decision 3: Data Storage

| Option | SQLite | JSON File | IndexedDB (Browser) |
| --- | --- | --- | --- |
| **Query Capability** | Full SQL | Manual filtering | Limited queries |
| **Performance** | Excellent | Good for small data | Good |
| **Concurrent Access** | ✅ Safe | ❌ Race conditions | ✅ Safe |
| **Backup/Export** | Easy (.db file) | Easy (.json file) | Complex |
| **Schema Migrations** | Supported | Manual | Manual |
| **Tauri Integration** | ✅ tauri-plugin-sql | ✅ fs API | ✅ WebView native |

**🏆 Recommendation: SQLite**
- Reliable for tracking window history over weeks/months
- Easy to query "show all windows this week" or "average usage per day"
- Single file, easy to backup
- Industry standard for local-first apps

---

### Decision 4: Scheduler Approach

| Option | Node-cron (in-app) | macOS launchd | System cron |
| --- | --- | --- | --- |
| **Runs when app closed** | ❌ No | ✅ Yes | ✅ Yes |
| **Wakes from sleep** | ❌ No | ✅ Yes (StartCalendarInterval) | ❌ No |
| **Setup Complexity** | Low | Medium | Low |
| **User Permission** | None | None | None |
| **Precision** | Good | Excellent | Good |
| **Management** | In-app UI | Plist files | Crontab |

**🏆 Recommendation: macOS launchd**
- Can wake the Mac from sleep to trigger window start at 3 AM
- Runs independently of app state
- Native macOS solution, reliable
- App generates/manages the plist file for user

---

### Decision 5: Menu Bar Implementation


| Option | Homebrew Cask | Mac App Store | Direct Download | GitHub Releases |
| --- | --- | --- | --- | --- |
| **Install UX** | `brew install --cask c5h` | App Store search | Download .dmg | Download .dmg |
| **Target Audience** | Developers | General public | Anyone | Developers |
| **Review Process** | Community PR | Apple review (days) | None | None |
| **Cost** | Free | $99/year | $99/year (signing) | Free |
| **Auto-updates** | `brew upgrade` | Built-in | DIY | DIY |
| **Sandboxing** | Optional | Required | Optional | Optional |
| **launchd Access** | ✅ Full | ❌ Restricted | ✅ Full | ✅ Full |
| **CLI Spawning** | ✅ Full | ❌ Limited | ✅ Full | ✅ Full |


**🏆 Recommendation: Homebrew Cask + GitHub Releases fallback**
- Homebrew is the standard for developer tools on macOS
- GitHub Releases provides fallback for non-Homebrew users
- Both support launchd and CLI spawning (required for C5h)
- Mac App Store sandboxing would break core functionality

---

### Decision 6: Distribution

**Why Sign + Notarize?**
- Without: macOS Gatekeeper blocks app with security warning
- With: App opens normally, no warnings, required for Homebrew Cask

**Release Pipeline (GitHub Actions):**

```
Build → Sign → Notarize → .dmg → GitHub Release → Homebrew PR
```

**GitHub Actions Workflow:**

```yaml
# .github/workflows/release.yml
- uses: tauri-apps/tauri-action@v0
  env:
    APPLE_CERTIFICATE: ${{ secrets.APPLE_CERTIFICATE }}
    APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
    APPLE_SIGNING_IDENTITY: "Developer ID Application: Name (TEAMID)"
    APPLE_ID: ${{ secrets.APPLE_ID }}
    APPLE_PASSWORD: ${{ secrets.APPLE_PASSWORD }}
    APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
  with:
    tagName: v__VERSION__
    releaseName: "C5h v__VERSION__"
```

**Homebrew Cask Formula:**

```ruby
cask "c5h" do
  version "1.0.0"
  sha256 "abc123..."

  url "https://github.com/user/c5h/releases/download/v#{version}/C5h_#{version}_aarch64.dmg"
  name "C5h"
  desc "Claude Code 5h window optimizer"
  homepage "https://github.com/user/c5h"

  app "C5h.app"

  zap trash: [
    "~/Library/Application Support/dev.c5h.app",
    "~/Library/LaunchAgents/dev.c5h.scheduler.plist",
  ]
end
```

**Required:** $99/year Apple Developer Program (for Developer ID certificate)

---

## Recommended Tech Stack Summary

```
┌─────────────────────────────────────────┐
│           C5h App Architecture          │
├─────────────────────────────────────────┤
│  Frontend: React + TypeScript           │
│  UI Kit: shadcn/ui + Tailwind           │
│  Calendar: ilamy Calendar               │
│  Charts: Recharts                       │
├─────────────────────────────────────────┤
│  Framework: Tauri 2.0                   │
│  Backend: Rust                          │
│  Database: SQLite (tauri-plugin-sql)    │
│  Menu Bar: tauri-plugin-system-tray     │
├─────────────────────────────────────────┤
│  Scheduler: macOS launchd               │
│  CLI: Claude Code, Codex, Gemini        │
└─────────────────────────────────────────┘
```

---

## Default Account Colors

| Account | Default Color | Hex |
| --- | --- | --- |
| Claude Code | Indigo | `#6366f1` |
| Gemini | Google Blue | `#4285f4` |
| Codex | OpenAI Green | `#10a37f` |
| Custom Account | User choice | - |

---

## Key File Locations

| File | Path | Purpose |
| --- | --- | --- |
| SQLite Database | `~/Library/Application Support/com.zaai.c5h/c5h.db` | Stores accounts, windows, settings |
| Scheduler Plist | `~/Library/LaunchAgents/com.zaai.c5h.scheduler.plist` | macOS launchd job for scheduled triggers |
| App Preferences | `~/Library/Preferences/com.zaai.c5h.plist` | macOS app preferences |
| App Bundle | `/Applications/C5h.app` | Installed application |

---

## Bundle Identifier

- **Identifier:** `com.zaai.c5h` (lowercase per Apple convention)
- **Product Name:** `C5h` (display name with capital C)

---

## Feature Summary

| Feature | Included | Notes |
| --- | --- | --- |
| Multi-account support | ✅ | Claude, Codex, Gemini, custom |
| Calendar week view | ✅ | Shows all windows with account colors |
| Menu bar widget | ✅ | Shows % used, quick start button |
| One-time scheduling | ✅ | Click calendar to schedule |
| Recurring schedules | ❌ | Not included (one-time only) |
| CLI polling detection | ✅ | Every 15 minutes |
| Notifications | ✅ | Ending soon, trigger status, weekly summary |
| Data export | ❌ | Not included |
| Launch at login | ✅ | Via macOS launchd |
| Dark mode | ✅ | System, light, dark |

---

## Additional Considerations

### Error Handling for CLI Detection

| Scenario | Behavior |
| --- | --- |
| CLI not installed | Show warning in account settings, disable polling for that account |
| Non-standard CLI path | Allow custom command path in account settings |
| CLI requires authentication | Show notification prompting user to authenticate manually |
| CLI timeout (>30s) | Abort and retry next polling interval, log error |
| Unexpected output format | Parse what's possible, log unparseable output for debugging |

### First-Run Experience

1. **Welcome screen** — Brief explanation of what C5h does
2. **Add first account** — Guided flow to add Claude Code or other CLI
3. **CLI verification** — Test that the CLI command works
4. **Optional: Schedule setup** — Prompt to create first scheduled trigger
5. **Menu bar intro** — Point to menu bar icon location

### Data Retention

| Data Type | Retention | Configurable |
| --- | --- | --- |
| Window history | 90 days | Yes (Settings) |
| Schedule logs | 30 days | No |
| App logs | 7 days | No |
| Account settings | Forever | N/A |

**Clear data option:** Settings → Data → "Clear history older than X days"

### Timezone Handling

- All times stored in UTC internally
- Display times converted to user's local timezone
- If timezone changes (travel), past events stay accurate, future schedules adjust
- Schedule times are stored as "local time intent" (e.g., "3:00 AM wherever I am")

### Conflict Resolution

| Scenario | Behavior |
| --- | --- |
| Manual window start during pending schedule | Cancel pending schedule, track manual window |
| Unexpected window detected | Add to calendar, mark as "detected" (not scheduled) |
| Schedule fires but window already active | Skip trigger, log "window already active" |
| Multiple schedules at same time | Execute first, skip others with warning |

### Offline Behavior

- App works fully offline (all data local)
- CLI tools may require internet for actual LLM calls
- If CLI fails due to network, notification: "Scheduled trigger failed - check internet connection"
- Polling continues regardless of network state

### App Updates

| Method | Behavior |
| --- | --- |
| Homebrew | `brew upgrade c5h` (manual or `brew autoupdate`) |
| GitHub Releases | Check for new version on app launch (weekly) |
| Notification | "C5h v1.2.0 available - run `brew upgrade c5h`" |
| Auto-update | ❌ Not included (rely on Homebrew/manual) |

### Accessibility

- Full keyboard navigation (Tab, Enter, Escape)
- VoiceOver support for all UI elements
- High contrast mode respects system setting
- Reduce motion respects system preference
- Menu bar accessible via keyboard shortcut

### Logging & Debugging

| Log | Location | Purpose |
| --- | --- | --- |
| App logs | `~/Library/Logs/com.zaai.c5h/app.log` | General app events |
| CLI output | `~/Library/Logs/com.zaai.c5h/cli.log` | Raw CLI detection output |
| Scheduler logs | `~/Library/Logs/com.zaai.c5h/scheduler.log` | Trigger execution logs |

**Debug mode:** Settings → Advanced → "Enable debug logging" (verbose output)

### Menu Bar Icon States

| State | Icon | Text |
| --- | --- | --- |
| No active window | Gray circle | "—" |
| Window active | Colored circle (account color) | "75%" |
| Window ending soon (<30 min) | Pulsing/orange | "⚠️ 12%" |
| Error/CLI unavailable | Red circle | "!" |
| Multiple windows (diff accounts) | Split circle | "C:45% X:80%" |

### Multiple Claude Code Profiles

For users with multiple Claude Code accounts (work/personal):

- Each profile is a separate "account" in C5h
- Configure custom CLI command per account: `claude --profile work`
- Each profile has independent window tracking and scheduling
- Different colors to distinguish in calendar view

### CLI Version Compatibility

| CLI | Minimum Version | Notes |
| --- | --- | --- |
| Claude Code | 1.0.0+ | `/usage` command required |
| Codex | 1.0.0+ | `/status` command required |
| Gemini | 1.0.0+ | Usage table on startup |

**Version detection:** On first account setup, check CLI version
**Breaking changes:** If output format changes, app shows "Update C5h for new CLI format"

### Privacy & Security

- **No data sent externally** — All data stored locally in SQLite
- **No analytics/telemetry** — Zero network calls from C5h itself
- **CLI commands** — Only runs user-configured CLI commands
- **No credentials stored** — CLI handles its own authentication
- **Open source** — Full transparency on what the app does

### Battery & Performance

| Activity | Frequency | Impact |
| --- | --- | --- |
| CLI polling | Every 15 min | Minimal (~1s CPU spike) |
| Menu bar update | On poll completion | Negligible |
| Background idle | Continuous | <5 MB RAM |
| Wake from sleep | On schedule only | Brief wake, then sleep |

**Power-saving mode:** If battery <20%, reduce polling to every 30 min

### Migration to New Mac

**Option 1: Manual**
1. Copy `~/Library/Application Support/com.zaai.c5h/` to new Mac
2. Install C5h on new Mac
3. Done — all history and settings preserved

**Option 2: Time Machine**
- App data automatically included in Time Machine backups

**Option 3: Export/Import (future)**
- Settings → Export → `c5h-backup.json`
- New Mac → Settings → Import

### Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘ + Shift + 5` | Open/focus C5h window (global) |
| `⌘ + N` | Quick start new window |
| `⌘ + ,` | Open settings |
| `⌘ + T` | Toggle between calendar views |
| `Escape` | Close popover/modal |
| `⌘ + Q` | Quit app (menu bar stays if enabled) |

**Customizable:** Settings → Keyboard → Edit shortcuts
