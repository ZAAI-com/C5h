# Codex `wham/usage` Direct-HTTPS Fallback

This document describes the **fallback** path for fetching Codex 5h + weekly limit data, in case the primary path (`codex app-server` JSON-RPC `account/rateLimits/read`) becomes unavailable. **Do not implement unless the primary path breaks.**

## Why a fallback exists

The Codex CLI is the upstream contract C5h depends on. If a future `codex` release:
- removes the `app-server` subcommand, **or**
- removes the `account/rateLimits/read` RPC method, **or**
- changes its CLI binary location in a way our resolver can't recover from,

then C5h's Codex usage card breaks. The endpoint that the CLI itself calls (`chatgpt.com/backend-api/wham/usage`) is undocumented but appears stable — CodexBar uses it as its primary path, and the Codex CLI calls it on a ~60s poll (`openai/codex` issue #10869).

## Approach

C5h reads the OAuth tokens the user already granted to the Codex CLI and calls the same backend endpoint directly. No re-implementation of the ChatGPT login flow is required.

### Auth source

File: `~/.codex/auth.json` (or `$CODEX_HOME/auth.json`).

Shape:
```json
{
  "tokens": {
    "access_token":  "...",
    "refresh_token": "...",
    "id_token":      "...",
    "account_id":    "..."
  },
  "last_refresh": "2026-04-15T12:00:00Z"
}
```

Reading `~/.codex/auth.json` does **not** trigger a TCC dialog (it's in the user's own home directory, not a protected app sandbox container).

### Token refresh

Tokens rotate every 8 days. When `last_refresh` is older than 8 days, POST to:

```
https://auth.openai.com/oauth/token

Content-Type: application/x-www-form-urlencoded

client_id=app_EMoamEEZ73f0CkXaXp7hrann
&grant_type=refresh_token
&refresh_token=<refresh_token>
&scope=openid profile email
```

Write the returned `access_token` / `refresh_token` / `id_token` / new `last_refresh` back to `~/.codex/auth.json` atomically (write to `auth.json.tmp` then rename). **Locking concern**: if both the Codex CLI and C5h race on this file, the CLI wins on conflict — we should re-read on `409`-shaped responses and retry once.

### Usage endpoint

```
GET https://chatgpt.com/backend-api/wham/usage

Headers:
  Authorization: Bearer <access_token>
  ChatGPT-Account-Id: <account_id>     (when present in auth.json)
  Accept: application/json
  User-Agent: C5h/<version>
```

Configurable base URL: `~/.codex/config.toml` may set `chatgpt_base_url`. If the configured base does not include `/backend-api`, fall back to `/api/codex/usage` (CodexBar's behavior).

### Response shape

```json
{
  "plan_type": "pro",
  "rate_limit": {
    "primary_window": {
      "used_percent": 15.0,
      "reset_at": 1735401600,
      "limit_window_seconds": 18000
    },
    "secondary_window": {
      "used_percent": 5.0,
      "reset_at": 1735920000,
      "limit_window_seconds": 604800
    }
  },
  "credits": {
    "has_credits": true,
    "unlimited": false,
    "balance": 150.0
  }
}
```

`primary_window.limit_window_seconds = 18000` is the 5h window. `secondary_window.limit_window_seconds = 604800` is the weekly window. This is the same data shape `codex app-server` returns (the RPC bridge wraps this endpoint).

## Implementation sketch

Three new files (~200 LOC), mirroring CodexBar's structure:

| File | Role |
|---|---|
| `Packages/C5hCore/Sources/C5hCore/Providers/CodexOAuthCredentials.swift` | Read/write `~/.codex/auth.json` atomically. Decode `tokens.*`, `last_refresh`. |
| `Packages/C5hCore/Sources/C5hCore/Providers/CodexOAuthTokenRefresher.swift` | POST to `auth.openai.com/oauth/token`, write back to `auth.json`. |
| `Packages/C5hCore/Sources/C5hCore/Providers/CodexWhamUsageClient.swift` | GET `wham/usage` with Bearer auth, decode response. Returns same `CodexUsageStatus` shape as the app-server path. |

Then update `CodexProviderAdapter.runUsageCommand()` to try `CodexAppServerClient` first; on failure (specifically: `cliNotFound`, RPC method not found, RPC version mismatch), fall back to `CodexWhamUsageClient`.

## When **not** to use this fallback

- If `codex` CLI is on `$PATH` and `codex app-server` works, prefer the RPC. Less code we own; the CLI absorbs upstream changes.
- If the user logged in to Codex via API key (not ChatGPT OAuth), `auth.json` won't contain refresh tokens — fail loudly rather than silently.

## References

- CodexBar (MIT) — `Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift`
- [`openai/codex#10869`](https://github.com/openai/codex/issues/10869) — confirms the CLI's own `wham/usage` poller
- [`openai/codex#15281`](https://github.com/openai/codex/issues/15281) — open request to surface this in a CLI subcommand
- [OpenAI Codex auth docs](https://developers.openai.com/codex/auth) — OAuth flow overview
