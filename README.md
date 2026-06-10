# EnvManager

Simple macOS GUI to view and manage environment variables and secrets across:

- Shell profile (`~/.zshrc`, `~/.bash_profile`, `~/.bashrc`, `~/.profile`)
- `.env` files (open any file or create a new one)
- macOS Keychain (generic passwords under the `EnvManager:<key>` service)

## Build it yourself

Requires Node.js 18+ and macOS.

```bash
cd electron-app
npm install
```

### Run in dev mode

```bash
npm run dev          # in one terminal: starts Vite on :5173
npx electron .       # in another terminal: launches the app
```

### Package a standalone `.app`

Apple Silicon (M1/M2/M3):

```bash
npm run package:mac-arm
```

Intel Macs:

```bash
npm run package:mac-x64
```

The built app is written to `release/EnvManager-darwin-<arch>/EnvManager.app`.
Double-click it to launch, or drag it into `/Applications`.

> The app is not code-signed. The first launch will be blocked by Gatekeeper —
> right-click → **Open**, or run `xattr -cr release/EnvManager-darwin-*/EnvManager.app`.

## Notes

- Keychain entries are stored under the service name `EnvManager:<key>` and
  indexed in `~/.env-manager-keychain-index.json` so the app can list them.
- Shell edits rewrite `export KEY="value"` lines in place; existing comments
  and ordering are preserved.
