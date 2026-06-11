# Developer & Agent Instructions: SecretSauce Repository

Welcome! This guide is designed for developers and AI agents working on the **SecretSauce** codebase. It outlines the architecture, macOS integrations, development lifecycle, and CI/CD setup to ensure consistency and prevent errors.

---

## 📌 Technical Stack

- **App:** Native SwiftUI (macOS 13+), built with Swift Package Manager. Lives entirely in [native/](file:///Users/nico/Workspace/SecretSauce/native/).
- **Build requirements:** Only the Xcode **Command Line Tools** (`xcode-select --install`). No full Xcode, no Node, no Electron.
- **OS Integrations:** macOS Keychain and launchd are driven via the standard system binaries (`/usr/bin/security`, `/bin/launchctl`) through `Process`/`ProcessRunner`. Plists are read/written with `PropertyListSerialization`. Shell profiles and `.env` files are edited as plain text. There are no native C++ addons and no third-party dependencies.
- **Distribution:** A single universal (arm64 + x86_64) ad-hoc-signed `.app`, ~2 MB on disk.

> A small `package.json` is kept at the repo root **only** as the version source of truth for the release pipeline (see below). It is not an npm project — there are no JS dependencies.

---

## 🏗️ Project Architecture

```mermaid
graph TD
    Views[SwiftUI Views - native/Sources/SecretSauce/Views] -->|calls| Services[Service layer - native/Sources/SecretSauce/Services]
    Services -->|Read/Write File| SP[Shell Profiles & .env Files]
    Services -->|Process: security| KC[macOS Keychain]
    Services -->|PropertyListSerialization + launchctl| LD[Launchd Agents]
```

### Service layer: `native/Sources/SecretSauce/Services/`
Each file handles one system-level concern:

- **[ShellProfileService.swift](file:///Users/nico/Workspace/SecretSauce/native/Sources/SecretSauce/Services/ShellProfileService.swift):** Parses and replaces `export KEY="value"` lines in the user's shell profile (`~/.zshrc`, `~/.bash_profile`, `~/.bashrc`, `~/.profile`), preserving comments and formatting in place.
- **[EnvFileService.swift](file:///Users/nico/Workspace/SecretSauce/native/Sources/SecretSauce/Services/EnvFileService.swift):** Serializes/deserializes `.env` key-value pairs (skips `#` comments, strips trailing ` #` comments on unquoted values, quotes values containing whitespace/quotes/`#`).
- **[KeychainService.swift](file:///Users/nico/Workspace/SecretSauce/native/Sources/SecretSauce/Services/KeychainService.swift):** Adds/deletes/reads generic passwords via `/usr/bin/security` under the service prefix `SecretSauce:`.
  - **Index File Migration:** Copies the old `~/.env-manager-keychain-index.json` to `~/.secret-sauce-keychain-index.json` if the new file does not exist yet.
  - **Read Fallback:** If `SecretSauce:<key>` is not found, it falls back to reading `EnvManager:<key>` for compatibility with pre-existing keys.
  - **Cleanup:** On delete, it removes the entry from both namespaces to prevent orphan secrets.
  - **Why the CLI:** Going through `/usr/bin/security` (rather than the SecItem API) keeps existing keychain ACLs valid, so migrated secrets don't trigger new authorization prompts.
- **[LaunchdManager.swift](file:///Users/nico/Workspace/SecretSauce/native/Sources/SecretSauce/Services/LaunchdManager.swift):** Lists launch agents from `~/Library/LaunchAgents`, reads their runtime status from `launchctl list`, edits the `EnvironmentVariables` dict in their plists, and runs load/unload/start/stop.
- **[NetworkMonitorService.swift](file:///Users/nico/Workspace/SecretSauce/native/Sources/SecretSauce/Services/NetworkMonitorService.swift):** Read-only network visibility (the monitoring half of a Little-Snitch-style tool). Parses `lsof -nP -i -F pcPnT` into connection snapshots; reverse-DNS via `/usr/bin/host` (cached); geo lookup (country/city/lat/lon) via ip-api.com's batch endpoint — the **only** code path in the app that sends data off-device, triggered on Network-tab open and on the Refresh button. ip-api.com's free tier is HTTP-only, so `package-app.sh` embeds a scoped `NSAppTransportSecurity` exception for that single domain (plain `swift run` dev builds have no Info.plist, so geo lookups may be blocked by ATS there — test geo in the packaged app). Monitoring only by design: real-time blocking needs a `NEFilterDataProvider` system extension (paid Developer ID + Apple-granted NetworkExtension entitlement + notarization + full Xcode), deliberately out of scope for the ad-hoc CLT-only build.
- **[ProcessRunner.swift](file:///Users/nico/Workspace/SecretSauce/native/Sources/SecretSauce/Services/ProcessRunner.swift):** Thin wrapper around `Process` for invoking system binaries.

### UI: `native/Sources/SecretSauce/Views/`
- **[ContentView.swift](file:///Users/nico/Workspace/SecretSauce/native/Sources/SecretSauce/Views/ContentView.swift):** `NavigationSplitView` with a sidebar selecting the six sections.
- **Sections:** `LocalEnvView`, `ShellProfileView`, `EnvFilesView`, `KeychainView`, `LaunchdView`, `NetworkView`.
- **[VarTableView.swift](file:///Users/nico/Workspace/SecretSauce/native/Sources/SecretSauce/Views/VarTableView.swift):** Reusable key/value table (search, add, inline edit, delete, secret reveal, persist badges) shared by all tabs.
- **[NetworkView.swift](file:///Users/nico/Workspace/SecretSauce/native/Sources/SecretSauce/Views/NetworkView.swift):** Network Monitor tab. Snapshot + geo lookup on tab-open and on the Refresh button (no polling). Table columns size from available width (`ColWidths`) so the window can be squeezed without clipping. Click a map dot to filter the table to that location (filter chip next to search clears it); hover for an info card. The location filter applies to the table only — map pins always derive from the unfiltered (search + remote-only) set, or selecting one dot would hide the rest.
- **[ConnectionMapView.swift](file:///Users/nico/Workspace/SecretSauce/native/Sources/SecretSauce/Views/ConnectionMapView.swift):** `NSViewRepresentable` wrapping AppKit's `MKMapView` (SwiftUI's `Map` on macOS 13 can't draw overlays). Pulsing "This Mac" home pin, endpoint dots with halo/caption/count, animated dashed geodesic arcs (dash phase driven by a 20 fps `Timer`), hover via `NSTrackingArea`, click selection via `didSelect`/`didDeselect`. Annotation rebuilds mute selection callbacks and re-select the previously selected dot so a data refresh doesn't clear the user's table filter.

---

## 💻 Developer Commands

### Dev Mode
```bash
cd native && swift run
```

### Packaging the `.app`
Builds arm64 + x86_64 release slices, lipo-merges them into a universal binary, assembles `release/SecretSauce.app` with an `Info.plist`, and ad-hoc signs it:

```bash
npm run package        # alias for: bash native/package-app.sh
```

> Note: multi-arch `swift build --arch arm64 --arch x86_64` in a single invocation requires full Xcode (xcbuild), so the script builds each slice separately and merges with `lipo`. This keeps it working with only the Command Line Tools.

### App Icon
The icon is generated entirely in code — no design tools or binary source art to maintain. [native/Resources/make-icon.swift](file:///Users/nico/Workspace/SecretSauce/native/Resources/make-icon.swift) draws the brand motif with CoreGraphics: an electric-blue droplet (`#3b82f5`) with an empty keyhole cut-out, on a solid near-black tile (`#0d0f12`) with a subtle blue glow — colors and style follow the shared design system in `~/Workspace/Design_System/foundations` (dark-first, no gradients, glow as elevation cue). Regenerate with `bash native/make-icon.sh`, which writes `native/Resources/AppIcon.icns` (bundled by `package-app.sh`) and `native/Resources/icon.png` (used in the README). `package-app.sh` regenerates the `.icns` automatically if it is missing.

In-app colors use the same tokens via the adaptive `Color.ds*` definitions in [Theme.swift](file:///Users/nico/Workspace/SecretSauce/native/Sources/SecretSauce/Theme.swift); the UI follows the system light/dark appearance (no forced color scheme).

### Gatekeeper Workaround (Local builds)
Unsigned/ad-hoc-signed apps are blocked on first launch. Clear the Gatekeeper flags with:

```bash
xattr -cr release/SecretSauce.app
```

---

## 🚀 CI/CD Release Pipeline

We use a GitHub Actions workflow defined in [.github/workflows/release.yml](file:///Users/nico/Workspace/SecretSauce/.github/workflows/release.yml) to automatically release new versions.

### Versioning Logic
On every push to the `main` branch:
1. Reads `version` from `package.json`.
2. Checks if git tag `v<version>` exists.
3. If it **exists**, increments the patch version (e.g. `1.0.0` → `1.0.1`), updates `package.json` in the build runner workspace, tags the commit, and pushes the tag to GitHub.
4. If it **does not exist**, tags the current commit as `v<version>` and pushes it.
5. Builds the native universal app via `native/package-app.sh` (which stamps the determined version into the bundle's `Info.plist`).
6. Compresses `release/SecretSauce.app` into `SecretSauce-mac-universal.zip` using `ditto` (preserving symlinks, signature, and metadata) and uploads it to a GitHub Release.

### Workflow Configuration Notice
For the pipeline to succeed, make sure that **Workflow permissions** under your repository's **Settings → Actions → General** are set to **"Read and write permissions"** so the runner can push the generated git tags and publish the release.
