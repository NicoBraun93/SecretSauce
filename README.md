# SecretSauce 🥫

A premium, lightweight macOS desktop utility to view and manage environment variables, secrets, `.env` files, and Launchd agents in one unified dashboard.

---

## 🛡️ Background & Philosophy (The AI-Age Local Secret Model)

In the modern developer workflow, building with AI assistants (especially cloud-hosted models) is standard practice. However, this poses a serious security risk: **unintended exposure of private API credentials**. Sharing environment logs or committing raw keys can accidentally leak secrets to external cloud servers or git histories.

**SecretSauce** was created to address this:

- **Fast GUI Over Terminal Hacks:** Avoid typing plain-text passwords into your terminal history. View, search, and manage credentials inside a private native wrapper.
- **Local macOS Keychain Storage:** Keep high-value API keys (OpenAI, Anthropic, Stripe, AWS, etc.) encrypted inside the macOS Keychain rather than plain text `.env` files.
- **Safe Development Isolation:** Keeps your keys isolated locally on your computer. When you debug code with cloud AIs, your secrets remain entirely hidden and inaccessible to them.

---

## 🚀 Download Pre-Compiled Releases

You do not need to build the app from source! You can download the latest version pre-compiled for your Mac architecture directly from the GitHub releases:

1. Go to the [Releases](../../releases) tab on your GitHub repository.
2. Download the ZIP package corresponding to your Mac:
   - **Apple Silicon (M1/M2/M3/M4/etc.):** Download `SecretSauce-mac-arm64.zip`
   - **Intel Macs:** Download `SecretSauce-mac-x64.zip`
3. Unzip the file and move `SecretSauce.app` into your `/Applications` directory.

> [!NOTE]
> **macOS Gatekeeper Note:** Because this application is self-signed/unsigned, macOS might block its first launch. To run it:
> - Right-click the app in Finder and choose **Open**, OR
> - Run the following command in Terminal to clear the quarantine attribute:
>   ```bash
>   xattr -cr /Applications/SecretSauce.app
>   ```

---

## ✨ Features

- **Shell Profiles Manager:** Intuitively read, insert, update, or remove export statements in your shell profiles (`~/.zshrc`, `~/.bash_profile`, `~/.bashrc`, `~/.profile`). Comments and custom formatting are preserved in-place.
- **`.env` File Editor:** Easily create or open any local `.env` configuration file to edit key-value pairs inside a clean interface.
- **macOS Keychain Integration:** Safely view, add, or delete secure generic passwords stored in the macOS Keychain under the `SecretSauce:<key>` namespace. Uses a local filesystem index (`~/.secret-sauce-keychain-index.json`) for quick listing. Automatically migrates old data from `EnvManager` namespace.
- **Launchd Management:** View, load, unload, start, and stop macOS Launchd agents, allowing you to manage plist-based background services and environment variables on the fly.
- **Local System Environment:** Inspect active environment variables (`process.env`) currently accessible to applications.

---

## 🛠️ Build and Development

### Prerequisites

- macOS
- Node.js (v18 or newer)
- npm (v9 or newer)

### 1. Installation

Clone this repository and install the dependencies from the root directory:

```bash
git clone <your-repository-url>
cd SecretSauce
npm install
```

### 2. Run in Development Mode

Run the following command in one terminal to spin up the Vite development server:

```bash
npm run dev
```

In another terminal, launch the Electron application wrapper:

```bash
npx electron .
```

### 3. Package Standalone `.app`

To package a standalone `.app` bundle:

- **Apple Silicon (ARM64):**
  ```bash
  npm run package:mac-arm
  ```
- **Intel (x64):**
  ```bash
  npm run package:mac-x64
  ```

The compiled binaries will be outputted to the `release/` directory.

---

## 🔒 Security & Architecture

- **Keychain Operations:** Accesses macOS Keychain using the native `/usr/bin/security` command-line utility. This avoids unsafe node module packaging issues.
- **Configuration Editing:** Uses native `/usr/bin/plutil` and `/bin/launchctl` to interface securely with user Plist agents.
- **IPC Sandboxing:** Employs IPC (Inter-Process Communication) and preload script bridging (`electron/preload.cjs`) to separate frontend web views from system-level privilege actions.
