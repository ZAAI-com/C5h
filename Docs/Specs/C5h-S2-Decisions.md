# C5h Architecture Decisions

This document contains all architecture decisions for the C5h app.

---

## Decision 1: Desktop Framework

| Option | Tauri (Rust) | Electron | Swift/AppKit (Native) |
| --- | --- | --- | --- |
| **Bundle Size** | ~3-10 MB | ~150-200 MB | ~2-5 MB |
| **Memory Usage** | Low (~30 MB) | High (~150+ MB) | Lowest (~20 MB) |
| **Development Speed** | Medium | Fast | Slow |
| **Menu Bar Support** | Plugin available | Built-in Tray API | Native NSStatusItem |
| **Web UI** | WebView | Chromium | SwiftUI/AppKit only |
| **CLI Integration** | Rust Command | Node child_process | Process API |
| **Cross-platform** | Yes | Yes | macOS only |
| **Learning Curve** | Medium (Rust) | Low (JS/TS) | High (Swift) |

**Decision: Tauri**
- Lightweight and fast - important for a background app running 24/7
- Modern Rust backend is reliable for scheduled tasks
- WebView allows React/Vue UI without Chromium bloat
- Growing ecosystem with good menu bar support

---

## Decision 2: Frontend UI Framework

| Option | React | Vue 3 | Svelte |
| --- | --- | --- | --- |
| **Ecosystem** | Massive | Large | Growing |
| **Bundle Size** | ~40 KB | ~33 KB | ~2 KB |
| **Performance** | Good (Virtual DOM) | Good (Virtual DOM) | Excellent (No runtime) |
| **Component Libraries** | Extensive | Good | Limited |
| **Calendar Components** | Many options | Several | Few |
| **TypeScript Support** | Excellent | Excellent | Good |
| **Developer Pool** | Largest | Large | Small |

**Decision: React**
- Most calendar/charting libraries available (FullCalendar, React Big Calendar)
- Pairs well with Tauri (official examples)
- Easier to find help and resources
- shadcn/ui provides excellent pre-built components

---

## Decision 3: Calendar Component Library

| Option | FullCalendar | React Big Calendar | @schedule-x/react | ilamy Calendar | Shadcn Calendar | Custom (date-fns) |
| --- | --- | --- | --- | --- | --- | --- |
| **License** | MIT (Free) + Premium | MIT | MIT | Free | MIT | MIT |
| **Bundle Size** | ~150 KB | ~40 KB | ~30 KB | ~0 KB (zero deps) | ~5 KB | ~15 KB |
| **Week View** | Excellent | Good | Good | Excellent | Month only | Build yourself |
| **Time Slots** | Hourly/custom | Hourly | 15min slots | Yes | No | Build yourself |
| **Drag & Drop** | Built-in | Built-in | Built-in | Built-in | No | Build yourself |
| **Customization** | High (CSS + API) | High (components) | Medium | Full (headless) | Full control | Full control |
| **TypeScript** | Excellent | Good | Good | Excellent | Excellent | Excellent |
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

5. **Shadcn Calendar** (`shadcn/ui calendar`)
   - https://ui.shadcn.com/docs/components/calendar
   - Beautiful month picker, integrates with shadcn ecosystem
   - Uses react-day-picker under the hood
   - No week/time view - would need custom extension
   - Best for date selection, not event display

6. **Custom Build** (date-fns + CSS Grid)
   - https://date-fns.org/
   - Full control over design and behavior
   - Smallest bundle size
   - More development effort
   - Best when you need something very specific

**Decision: Custom build (date-fns + CSS Grid)**

The shipped implementation lives in `src-react/components/CalendarView.tsx` as a hand-rolled
24×7 grid driven by `date-fns`. We chose this over ilamy Calendar (the original pick) for
three reasons that only became clear during integration:

- The view is read-mostly: window blocks render from DB, the only interactive surface is
  click-to-schedule. A full event-management calendar library is overhead we don't use.
- The tray-driven popover and the calendar share styling primitives (account colors,
  active-window highlighting) — owning the grid keeps these in one place.
- Bundle weight stays minimal in a menu-bar app that runs 24/7.

ilamy remains a reasonable choice if we later add drag-to-resize, recurring events, or a
month/year view; revisit then.

---

## Decision 4: Data Storage

| Option | SQLite | JSON File | IndexedDB (Browser) |
| --- | --- | --- | --- |
| **Query Capability** | Full SQL | Manual filtering | Limited queries |
| **Performance** | Excellent | Good for small data | Good |
| **Concurrent Access** | Safe | Race conditions | Safe |
| **Backup/Export** | Easy (.db file) | Easy (.json file) | Complex |
| **Schema Migrations** | Supported | Manual | Manual |
| **Tauri Integration** | tauri-plugin-sql | fs API | WebView native |

**Decision: SQLite**
- Reliable for tracking window history over weeks/months
- Easy to query "show all windows this week" or "average usage per day"
- Single file, easy to backup
- Industry standard for local-first apps

---

## Decision 5: Scheduler Approach

| Option | Node-cron (in-app) | macOS launchd | System cron |
| --- | --- | --- | --- |
| **Runs when app closed** | No | Yes | Yes |
| **Wakes from sleep** | No | Yes (StartCalendarInterval) | No |
| **Setup Complexity** | Low | Medium | Low |
| **User Permission** | None | None | None |
| **Precision** | Good | Excellent | Good |
| **Management** | In-app UI | Plist files | Crontab |

**Decision: macOS launchd**
- Can wake the Mac from sleep to trigger window start at 3 AM
- Runs independently of app state
- Native macOS solution, reliable
- App generates/manages the plist file for user

---

## Decision 6: Menu Bar Implementation

| Option | Tauri System Tray | Separate Swift Helper | Electron Tray |
| --- | --- | --- | --- |
| **Native Feel** | Good | Excellent | Good |
| **Dynamic Text** | Yes | Yes | Yes |
| **Popover Window** | Plugin | Native | BrowserWindow |
| **Complexity** | Low | High (2 apps) | Low |
| **IPC with Main App** | Built-in | Needs setup | Built-in |

**Decision: Tauri System Tray**
- Integrated with main app, simpler architecture
- `tauri-plugin-positioner` helps position popover windows
- Sufficient native feel for our needs
- Single codebase to maintain

---

## Decision 7: Distribution

| Option | Homebrew Cask | Mac App Store | Direct Download | GitHub Releases |
| --- | --- | --- | --- | --- |
| **Install UX** | `brew install --cask c5h` | App Store search | Download .dmg | Download .dmg |
| **Target Audience** | Developers | General public | Anyone | Developers |
| **Review Process** | Community PR | Apple review (days) | None | None |
| **Cost** | Free | $99/year | $99/year (signing) | Free |
| **Auto-updates** | `brew upgrade` | Built-in | DIY | DIY |
| **Sandboxing** | Optional | Required | Optional | Optional |
| **launchd Access** | Full | Restricted | Full | Full |
| **CLI Spawning** | Full | Limited | Full | Full |

**Decision: Homebrew Cask + GitHub Releases fallback**
- Homebrew is the standard for developer tools on macOS
- GitHub Releases provides fallback for non-Homebrew users
- Both support launchd and CLI spawning (required for C5h)
- Mac App Store sandboxing would break core functionality

**Why Sign + Notarize?**
- Without: macOS Gatekeeper blocks app with security warning
- With: App opens normally, no warnings, required for Homebrew Cask

**Release Pipeline (GitHub Actions):**

```
Build → Sign → Notarize → .dmg → GitHub Release → Homebrew PR
```

**Required:** $99/year Apple Developer Program (for Developer ID certificate)

---

## Final Tech Stack Summary

```
┌─────────────────────────────────────────┐
│           C5h App Architecture          │
├─────────────────────────────────────────┤
│  Frontend: React + TypeScript           │
│  UI Kit: shadcn/ui + Tailwind           │
│  Calendar: custom grid (date-fns)       │
│  Charts: Recharts                       │
├─────────────────────────────────────────┤
│  Framework: Tauri 2.0                   │
│  Backend: Rust                          │
│  Database: SQLite (tauri-plugin-sql)    │
│  Menu Bar: tauri-plugin-system-tray     │
├─────────────────────────────────────────┤
│  Scheduler: macOS launchd               │
│  CLI: Claude Code (spawned process)     │
├─────────────────────────────────────────┤
│  Distribution: Homebrew + GitHub        │
│  CI/CD: GitHub Actions                  │
└─────────────────────────────────────────┘
```
