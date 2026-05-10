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
