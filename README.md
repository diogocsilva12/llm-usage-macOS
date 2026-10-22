# Limitbar

A native macOS menu bar app for **Codex and Antigravity / Argon usage**. The interface follows the compact blue reference: translucent navy panel, aligned five-hour and weekly columns, slim usage bars, reset times, and small provider summaries in the menu bar.

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

Move **Limitbar.app** from `dist` into **Applications**, then open it. The first launch opens Connections. Enable the providers you use; click the menu bar item to see limits. The build script also creates `dist/Limitbar-macOS.zip` for the architecture of the Mac running the build.

This is a local, ad-hoc-signed build, not a notarized release. To develop without packaging, run `swift run Limitbar` or open `Package.swift` in Xcode. Launch at login requires the packaged app.

## Connect your accounts

### Codex

1. Sign in to the Codex app or run `codex login` using your **ChatGPT account**.
2. Enable **Codex** in Connections. The default account folder is `~/.codex` (or `CODEX_HOME` when available to the process). Choose a different folder if your installation uses one.
3. If macOS prompts for Keychain access, allow Limitbar to read the Codex session.

The app reads the existing `auth.json` token, or the `Codex Auth` Keychain entry for that folder, and makes a read-only request to `https://chatgpt.com/backend-api/wham/usage`. It respects the top-level `cli_auth_credentials_store` setting for `file`, `keyring`, and `auto`. API-key-only logins cannot report ChatGPT subscription allowances. Expired sessions must be renewed in Codex; Limitbar does not rotate tokens or modify your auth files.

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

This is a usage report, not a model prompt. The desktop app does not have to remain open. Separate groups returned by the provider—such as **Gemini 4 Argon**, the shared Gemini pool, and Claude/GPT models—remain separate. Argon's quota is prioritized in the menu bar when present. Accounts without a five-hour allowance show “not reported” in that column.

If authentication expires, open `agy` and sign in again. Refreshes do not intentionally launch a browser login. The app does not scrape browser cookies, inspect conversations, or copy provider credentials.

## Controls

- **Refresh Now / ⌘R:** update connected accounts. Automatic refresh runs every five minutes and after wake.
- **Pin:** keep the panel open while using other apps. Click the menu bar item again to dismiss it.
- **Open at Login:** register the packaged app with macOS Login Items.
- **Connections / ⌘,:** connect, disconnect, or change local installation paths.
- **Quit / ⌘Q:** stop the app and its active probes.

All percentages mean **used**, not remaining. Reset times use your Mac's time zone. Unknown values stay blank; a failed refresh shows an actionable error instead of a made-up percentage. No usage history, auth tokens, or command diagnostics are saved by Limitbar. Preferences contain only connection toggles and installation paths.

## Development and validation

```bash
swift test
./scripts/build-app.sh  # macOS only
```

`LimitbarCore` contains the parsers, read-only Codex client, and bounded CLI runner. Its 26 tests cover separate Argon quotas, weekly-only plans, missing/disabled quotas, reset parsing, authentication failures, redirect blocking, timeouts, cancellation, and bounded subprocess output. Fixtures are synthetic and contain no account credentials.

The native app uses SwiftUI, AppKit, Security, CryptoKit, and ServiceManagement. A macOS GitHub Actions workflow runs the tests, compiles and signs the app, and uploads the ZIP on pushes to `main` and pull requests. The workflow must run before treating the macOS build as verified.

Linux can build and test `LimitbarCore`; it cannot compile or run the macOS interface. The current implementation has been tested on Linux with Swift 6.2.1. Native rendering, Keychain access, launch at login, and live account responses still require validation on a signed-in Mac.

Provider interfaces can change. A rejected or unrecognized response produces an error, never fabricated quota. Codex windows other than five hours or seven days are currently not displayed.

Protocol references: [OpenAI Codex](https://github.com/openai/codex), [Antigravity](https://antigravity.google/), and [CodexBar's Antigravity integration notes](https://github.com/steipete/CodexBar/blob/main/docs/antigravity.md). This project is independent of those products.
