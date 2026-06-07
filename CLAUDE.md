# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

VibePulse is a native macOS menu-bar utility (SwiftUI `MenuBarExtra`, `LSUIElement` — no Dock icon). It shows a glass popover with: keep-awake / lid-sleep controls, live system metrics, public IP + country, appearance and launch-at-login toggles, and Claude Code / Codex usage cards. UI strings are Chinese (`zh_CN`). Minimum target is macOS 15; on macOS 26+ it uses native Liquid Glass (`glassEffect`) and falls back to `.thinMaterial` below that.

## Build & run

```bash
./build-app.sh          # swift build -c release + assemble dist/VibePulse.app + ad-hoc codesign
open dist/VibePulse.app
```

For fast iteration use `swift build` (debug). Note `swift run` launches the raw executable, but the app loads brand icons from `Bundle.main.resourceURL` (see `BrandIcon` in `ContentView.swift`), so those icons only resolve when run from the assembled `.app` bundle — prefer `build-app.sh` when touching anything visual. `Package.swift` uses swift-tools 6.0 but pins `.swiftLanguageMode(.v5)`. There is no test suite and no linter configured.

## Architecture

Single source of truth is **`AppModel`** (`AppModel.swift`), a `@MainActor ObservableObject` injected via `.environmentObject`. It owns every reader/controller, holds all `@Published` UI state, and drives a repeating 8-second `refreshTimer` that re-reads local metrics and logs. `ContentView` is pure presentation — one card per concern, no business logic. Each data source is an isolated reader class that `AppModel` calls; readers never touch UI state directly.

The readers, and the non-obvious things each does:

- **`SystemMetricsReader`** — CPU and memory via Mach `host_statistics`/`host_statistics64` (CPU is a delta against the previous sample, so the first read is 0); battery by shelling out to `pmset -g batt` and regexing the percentage.

- **`UsageMetricsReader`** — reads token usage by parsing **local JSONL session logs**, not any API: Claude from `~/.claude/projects`, Codex from `~/.codex/sessions`. It walks files modified within the current month, attributes each entry to its own timestamp's today/week/month bucket (Claude rows are deduped by `message.id`+`requestId`; Codex bills per-turn deltas of the cumulative `total_token_usage`), and estimates a dollar cost using **hard-coded per-million-token prices** in `codexPrice(for:)` / `claudePrice(for:)` — update these when model pricing changes (Claude Opus is priced for 4.5+ at $5/$25; Codex prices are unverified). Cost is an "equivalent API value" estimate, never the real subscription charge (shown as `≈$`). It also has a *fallback* limits reader (`readClaudeLimits` / `readCodexLimits`) that scrapes the latest `rate_limits` object out of the same logs.

- **`ClaudeAccountReader`** — locates the `claude` binary across several install paths *including Claude Desktop's bundled copy* (`claudeExecutable`), runs `claude --version` and `claude auth status` (parsed as JSON). For live limits it reads the OAuth access token from the macOS Keychain (`security find-generic-password -s "Claude Code-credentials"`) and calls Anthropic's `api/oauth/usage` endpoint. The token is read transiently and never stored.

- **`CodexAccountReader`** — runs `codex login status`; for live limits it drives `codex app-server --stdio` over JSON-RPC (handcrafted `initialize`/`initialized`/`account/rateLimits/read` sequence piped through `zsh`).

- **`IPLocationReader`** — `https://ipwho.is/`, cached 30 min; the refresh button forces a re-fetch.

- **`LidSleepController`** — the only privileged piece. First toggle prompts for admin via `osascript ... with administrator privileges` to install a restricted helper at `/usr/local/libexec/awakebar-lid-sleep` plus a `sudoers` entry; afterward it toggles `pmset -a disablesleep` through that helper with no further prompts. This setting is **system-level and persists after the app quits** — keep that in mind when reasoning about its lifecycle.

### Live-vs-log limits precedence

`AppModel` keeps `hasLiveClaudeLimits` / `hasLiveCodexLimits` flags. Once a reader returns live limits from the official endpoint, the 8s timer's log-derived `readClaudeLimits()` / `readCodexLimits()` calls are **skipped** so they can't overwrite live data (see `refresh()`). Account/limit refreshes run as detached async tasks; only the local metrics read happens synchronously on the timer.

### Keep-awake

The awake toggle spawns and terminates a child `/usr/bin/caffeinate -d -i` process (`updateAwakeProcess`); the duration picker arms a one-shot timer that flips `isAwake` back off. This is independent of the lid-sleep helper above.
