<p align="center">
  <img src="native/Resources/icon.png" alt="SecretSauce icon" width="160" height="160">
</p>

<h1 align="center">SecretSauce 🥫</h1>

<p align="center">
  A premium, lightweight, <strong>native</strong> macOS app to view and manage environment variables, secrets, <code>.env</code> files, and Launchd agents in one unified dashboard.
</p>

---

## 🛡️ Background & Philosophy (The AI-Age Local Secret Model)

In the modern developer workflow, building with AI assistants (especially cloud-hosted models) is standard practice. However, this poses a serious security risk: **unintended exposure of private API credentials**. Sharing environment logs or committing raw keys can accidentally leak secrets to external cloud servers or git histories.

**SecretSauce** was created to address this:

- **Fast GUI Over Terminal Hacks:** Avoid typing plain-text passwords into your terminal history. View, search, and manage credentials inside a private native wrapper.
- **Local macOS Keychain Storage:** Keep high-value API keys (OpenAI, Anthropic, Stripe, AWS, etc.) encrypted inside the macOS Keychain rather than plain text `.env` files.
- **Safe Development Isolation:** Keeps your keys isolated locally on your computer. When you debug code with cloud AIs, your secrets remain entirely hidden and inaccessible to them.

---

## 🚀 Download Pre-Compiled Releases

You do not need to build the app from source! You can download the latest pre-compiled version directly from the GitHub releases:

1. Go to the [Releases](../../releases) tab on your GitHub repository.
2. Download `SecretSauce-mac-universal.zip` — a single universal build that runs natively on both Apple Silicon and Intel Macs.
3. Unzip the file and move `SecretSauce.app` into your `/Applications` directory.

> [!NOTE]
> **macOS Gatekeeper Note:** Because this application is self-signed/unsigned, macOS might block its first launch. To run it:
> - Right-click the app in Finder and choose **Open**, OR
> - Run the following command in Terminal to clear the quarantine attribute:
>   ```bash
>   xattr -cr /Applications/SecretSauce.app
>   ```

### Automatic Updates

You only need to do the manual download **once**. SecretSauce ships with [Sparkle](https://sparkle-project.org): it checks the GitHub releases feed for newer versions and can download and install them in place. Trigger a check any time from the app menu — **SecretSauce → Check for Updates…** — and the app also checks periodically in the background.

Updates are verified by a cryptographic (EdDSA) signature rather than an Apple Developer ID, and Sparkle clears the quarantine flag on the versions it installs, so auto-updates launch cleanly without the Gatekeeper step above.

---

## ✨ Features

- **Shell Profiles Manager:** Intuitively read, insert, update, or remove export statements in your shell profiles (`~/.zshrc`, `~/.bash_profile`, `~/.bashrc`, `~/.profile`). Comments and custom formatting are preserved in-place.
- **`.env` File Editor:** Easily create or open any local `.env` configuration file to edit key-value pairs inside a clean interface.
- **macOS Keychain Integration:** Safely view, add, or delete secure generic passwords stored in the macOS Keychain under the `SecretSauce:<key>` namespace. Uses a local filesystem index (`~/.secret-sauce-keychain-index.json`) for quick listing. Automatically migrates old data from `EnvManager` namespace.
- **Launchd Management:** Manage macOS Launchd agents and their environment variables with two controls: an **Autostart** switch that actually sticks (it writes launchd's override database, so a disabled agent stays disabled across reboots — unlike a plain unload, which lasts only until the next login), and an **Activate / Deactivate** button for right now. Every agent reports what it costs: memory (RSS), CPU, process count, and uptime, summed over its whole process tree. Hover the ⓘ for the full explanation of which `launchctl` command runs and how long the effect lasts.
- **Local System Environment:** Inspect the active session's environment variables, and persist any of them to your shell profile with one click.
- **Network Monitor:** A read-only, Little-Snitch-style view of your machine's open connections: which app talks to which remote IP, host, port, and state — plus a world map with your own location and animated arcs to every endpoint. Hover a dot for details, click it to filter the table. Country/city lookup runs when you open the tab or press Refresh, and is the only thing in the app that sends data off-device.
- **Memory Overview:** A live RAM dashboard — memory pressure (with a composition breakdown of wired/active/compressed/cached/free and a swap warning), the memory footprint of your own launch agents with an inline **Stop** to reclaim it, and the biggest system-wide consumers clustered per app with **Show** and **Quit** actions. Snapshot-based (no polling), refreshed on open and on demand.

---

## 🛠️ Build and Development

SecretSauce is a native SwiftUI app (macOS 13+) built with Swift Package Manager. It lives in `native/` and ships as a ~7 MB universal `.app` (a ~2 MB app plus the embedded Sparkle auto-update framework).

### Prerequisites

- macOS 13 or newer
- Xcode Command Line Tools — install with `xcode-select --install`

No Node and no Xcode IDE are required. The only third-party dependency is [Sparkle](https://github.com/sparkle-project/Sparkle) (auto-update), pulled in automatically by Swift Package Manager.

### Run in Development Mode

```bash
cd native && swift run
```

### Package a Standalone `.app`

This builds the Apple Silicon and Intel slices, merges them into a universal binary, and assembles an ad-hoc-signed `release/SecretSauce.app`:

```bash
npm run package      # alias for: bash native/package-app.sh
```

The compiled bundle is written to the `release/` directory.

---

## 🔒 Security & Architecture

- **Keychain Operations:** Accesses the macOS Keychain through the native `/usr/bin/security` command-line utility, so existing keychain access controls remain valid.
- **Launchd Management:** Reads and writes agent plists with `PropertyListSerialization` and controls services via `/bin/launchctl` (`load`/`unload`/`start`/`stop` for the running session; `enable`/`disable` plus `bootstrap`/`bootout` in the `gui/<uid>` domain for autostart, which needs no root). Persistent state is read back from `launchctl print-disabled`, and per-agent resource figures come from a single `/bin/ps` snapshot aggregated over each job's process tree.
- **Network Monitor:** Samples open connections via `/usr/sbin/lsof` and resolves hostnames with `/usr/bin/host` — all local. Geo lookups go to ip-api.com when the Network Monitor tab is opened or refreshed — the app's **only** off-device traffic (HTTP-only free tier; the app bundle carries a scoped ATS exception for that single domain). It observes only — blocking traffic would require an Apple-entitled Network Extension.
- **No Web Layer:** As a native AppKit/SwiftUI app, there is no embedded browser, renderer process, or IPC bridge — system-level actions run directly in a single process.
