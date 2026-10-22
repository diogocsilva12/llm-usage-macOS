# Limitbar

A native macOS menu bar app for **Codex, Antigravity / Argon, Claude, GitHub Copilot, Z.ai / GLM, and Synthetic**. The interface follows the compact blue reference: translucent navy panel, slim usage bars, reset times, and small provider summaries in the menu bar. Quota columns show each service's actual five-hour, weekly, monthly, or hourly period.

Limitbar shows real usage after connecting your existing sign-ins. It does not ship with simulated account data.

## Run on your Mac

Requires **macOS 13 Ventura or later** and **Swift 5.9 or later** (Xcode 15+ or compatible Command Line Tools). No third-party Swift packages are required.

```bash
# If you don't already have Apple's developer tools:
xcode-select --install

# From this repository, once the tools are installed:
./scripts/build-app.sh
open dist
```

Move **Limitbar.app** from `dist` into **Applications**, then open it. The first launch opens Connections. Choose a service in the searchable provider catalog, click **Add**, and follow its setup instructions. Click the menu bar item to see limits. The build script also creates `dist/Limitbar-macOS.zip` for the architecture of the Mac running the build.

This is a local, ad-hoc-signed build, not a notarized release. To develop without packaging, run `swift run Limitbar` or open `Package.swift` in Xcode. Launch at login requires the packaged app.

## Update an installed copy

Quit Limitbar from its menu first. In your existing repository folder, run:

```bash
git pull --ff-only origin main
./scripts/build-app.sh
open dist
```

Drag the new **Limitbar.app** into **Applications**, choose **Replace**, and reopen it from Applications. Your connection settings and sign-ins are retained. Version 1.1.0 adds the provider catalog and four new quota integrations. Previously enabled Codex and Antigravity connections are carried into the catalog automatically. The version is shown in Connections.

## Connect your accounts

Connections lists six supported providers. Select one to read its sign-in requirements and add it to your panel. **Enable usage tracking** starts its requests; turning it off pauses them. **Remove Provider** removes it from the panel and deletes any credential stored by Limitbar for that provider. It leaves credentials owned by Codex, Claude Code, and Antigravity untouched.

| Provider | Sign-in | Quotas |
| --- | --- | --- |
| Codex | Existing Codex ChatGPT session | Five hours, weekly, reset credits |
| Antigravity / Argon | Signed-in `agy` CLI | Argon, shared Gemini, separate Claude/GPT allowances |
| Claude | Existing Claude Code OAuth session | Five hours, weekly, model-specific weekly limits |
| GitHub Copilot | GitHub account token | Monthly premium requests, chat, completions when metered |
| Z.ai / GLM | Global personal Coding Plan API key | Plan windows and MCP allowance |
| Synthetic | Synthetic API key | Rolling five hours, weekly tokens, hourly search |

Only added providers appear in the panel. Enabled providers appear in the menu bar. Missing quotas remain unknown, and unlimited allowances are labeled rather than rendered as a fake zero-percent bar.

### Codex

1. Sign in to the Codex app or run `codex login` using your **ChatGPT account**.
2. Enable **Codex** in Connections. The default account folder is `~/.codex` (or `CODEX_HOME` when available to the process). Choose a different folder if your installation uses one.
3. If macOS prompts for Keychain access, allow Limitbar to read the Codex session.

The app reads the existing `auth.json` token, or the `Codex Auth` Keychain entry for that folder, and makes read-only requests to `https://chatgpt.com/backend-api/wham/usage` and `/wham/rate-limit-reset-credits`. It respects the top-level `cli_auth_credentials_store` setting for `file`, `keyring`, and `auto`. API-key-only logins cannot report ChatGPT subscription allowances. Expired sessions must be renewed in Codex; Limitbar does not rotate tokens or modify your auth files.

Below Codex's bars, the app shows the number of available resets and the next expiration in your Mac's time zone. The count comes from the account's reported `available_count`; inventory details identify full resets and their earliest available expiration. Redeemed and expired entries do not determine that date. If details are unavailable, the count from `/usage` remains visible with “Expiration not reported.” Missing reset data is labeled “Reset availability not reported,” rather than being treated as zero. A known expiry that passes between refreshes is marked for refresh. Reset credits are displayed read-only.

### Antigravity / Argon

Install the **Antigravity CLI 1.1.11+**, then sign in once:

```bash
brew install --cask antigravity-cli
agy
```

Enable **Antigravity / Argon** in Connections. Limitbar discovers `agy` in Homebrew and common installation locations; **Choose CLI…** supports other paths. It runs the structured usage command in a private temporary directory:

```bash
agy -p /usage --output-format json
```

This is a usage report, not a model prompt. The desktop app does not have to remain open. **Gemini 4 Argon** and the shared Gemini pool appear in the Gemini section. **Claude/GPT models** appear in their own section with a Claude logo, labeled Google Antigravity to show where those allowances come from. Argon's quota is prioritized in the menu bar when present. Accounts without a five-hour allowance show “not reported” in that column.

If authentication expires, open `agy` and sign in again. Refreshes do not intentionally launch a browser login. The app does not scrape browser cookies, inspect conversations, or copy provider credentials.

### Claude

Add **Claude** and enable tracking after signing in to Claude Code using your Claude subscription. macOS may ask you to allow Limitbar to read the `Claude Code-credentials` Keychain item. The default `~/.claude/.credentials.json` file is supported as a fallback when the Keychain item is absent. Claude's OAuth endpoint is `https://api.anthropic.com/api/oauth/usage`; Anthropic API keys do not expose Pro/Max subscription limits. Renew expired sessions in Claude Code.

Claude's subscription is separate from the **Claude & GPT** section under Antigravity; the latter remains labeled **Google Antigravity**.

### GitHub Copilot

Add **GitHub Copilot**, enter a GitHub account token that can read your Copilot quota, and click **Save & Connect**. To copy a token from an existing GitHub CLI sign-in on your Mac, run `gh auth token | pbcopy` and paste into the secure field. Fine-grained repository tokens may not expose this account endpoint; a failed token produces a connection error.

Limitbar reads `https://api.github.com/copilot_internal/user` using the GitHub token directly. Monthly premium, chat, and completions allowances are labeled with their actual period. Unlimited and token-billed seats have notes when a quota denominator is unavailable. No included allowance is inferred from the plan name.

### Z.ai / GLM

Add **Z.ai / GLM**, enter a personal **global Z.ai Coding Plan API key**, and click **Save & Connect**. The reader uses `https://api.z.ai/api/monitor/usage/quota/limit`. Five-hour or other reported plan periods are displayed separately from the monthly MCP allowance. BigModel China and team credentials require different routes and are not supported by this global integration.

### Synthetic

Add **Synthetic**, enter its API key, and click **Save & Connect**. The reader uses `https://api.synthetic.new/v2/quotas` and handles the reported `rollingFiveHourLimit`, `weeklyTokenLimit`, and `search.hourly` lanes, including responses nested under `data`. It displays only measured percentages or percentages derived from a reported usage/limit pair.

## Controls

- **Refresh Now / ⌘R:** update connected accounts. Automatic refresh runs every five minutes and after wake.
- **Pin:** keep the panel open while using other apps. Click the menu bar item again to dismiss it.
- **Open at Login:** register the packaged app with macOS Login Items.
- **Connections / ⌘,:** search the provider catalog, add/remove services, connect accounts, or change local installation paths.
- **Quit / ⌘Q:** stop the app and its active probes.

All percentages mean **used**, not remaining. Reset times use your Mac's time zone. Unknown values stay blank; a failed refresh shows an actionable error instead of a made-up percentage. Manual GitHub tokens and API keys are stored only in macOS Keychain. Existing CLI sign-ins are read without copying them into Limitbar's credential store. Preferences contain provider selections, tracking toggles, and installation paths. Usage history and raw command diagnostics are not saved.

## Development and validation

```bash
swift test
./scripts/build-app.sh  # macOS only
```

`LimitbarCore` contains the provider catalog, quota parsers, read-only API clients, and bounded CLI runner. Its tests cover all six provider formats, catalog migration, monthly/hourly period labels, unlimited accounts, missing/disabled quotas, reset-credit counts and expiration, optional inventory failures, authentication headers, redirect blocking, timeouts, cancellation, and bounded subprocess output. Fixtures are synthetic and contain no account credentials.

The native app uses SwiftUI, AppKit, Security, CryptoKit, and ServiceManagement. A macOS GitHub Actions workflow runs the tests, compiles and signs the app, and uploads the ZIP on pushes to `main` and pull requests. The workflow must run before treating the macOS build as verified.

Linux can build and test `LimitbarCore`; it cannot compile or run the macOS interface. The current implementation has been tested on Linux with Swift 6.2.1 and mocked API responses. Native rendering, Keychain access, launch at login, and live account responses still require validation on a signed-in Mac.

Provider interfaces can change. A rejected or unrecognized response produces an error, never fabricated quota. Codex windows other than five hours or seven days are currently not displayed.

Protocol references: [OpenAI Codex](https://github.com/openai/codex), [Antigravity](https://antigravity.google/), [Synthetic's quota API](https://dev.synthetic.new/docs/synthetic/quotas), and [CodexBar's provider integration notes](https://github.com/steipete/CodexBar/tree/main/docs). This project is independent of those products.

The provider vector marks are distributed with CodexBar; their source and MIT license are included in `Sources/Limitbar/Resources/ProviderLogos-LICENSE.txt` and in the packaged app's resource bundle. Product names and logos belong to their respective owners.
