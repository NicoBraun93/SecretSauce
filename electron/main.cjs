const { app, BrowserWindow, ipcMain, dialog } = require("electron");
const path = require("path");
const fs = require("fs");
const os = require("os");
const { execFile } = require("child_process");

function createWindow() {
  const win = new BrowserWindow({
    width: 1100,
    height: 740,
    titleBarStyle: "hiddenInset",
    backgroundColor: "#0b0d12",
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  if (app.isPackaged) {
    win.loadFile(path.join(__dirname, "..", "dist", "index.html"));
  } else {
    win.loadURL("http://localhost:5173").catch(() => {
      win.loadFile(path.join(__dirname, "..", "dist", "index.html"));
    });
  }
}

app.whenReady().then(createWindow);
app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

// ---------- Shell profile ----------
function shellProfilePath() {
  const home = os.homedir();
  for (const f of [".zshrc", ".bash_profile", ".bashrc", ".profile"]) {
    const p = path.join(home, f);
    if (fs.existsSync(p)) return p;
  }
  return path.join(home, ".zshrc");
}

function parseExports(content) {
  const lines = content.split("\n");
  const result = [];
  lines.forEach((line, idx) => {
    const m = line.match(/^\s*export\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (m) {
      let val = m[2].trim();
      if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
        val = val.slice(1, -1);
      }
      result.push({ key: m[1], value: val, line: idx });
    }
  });
  return result;
}

ipcMain.handle("shell:path", () => shellProfilePath());

ipcMain.handle("shell:read", () => {
  const p = shellProfilePath();
  const content = fs.existsSync(p) ? fs.readFileSync(p, "utf8") : "";
  return { path: p, vars: parseExports(content) };
});

ipcMain.handle("shell:upsert", (_e, { key, value }) => {
  const p = shellProfilePath();
  let content = fs.existsSync(p) ? fs.readFileSync(p, "utf8") : "";
  const re = new RegExp(`^\\s*export\\s+${key}\\s*=.*$`, "m");
  const safe = /[\s"'$`\\]/.test(value) ? `"${value.replace(/(["\\$`])/g, "\\$1")}"` : value;
  const newLine = `export ${key}=${safe}`;
  if (re.test(content)) content = content.replace(re, newLine);
  else content = content + (content.endsWith("\n") || content === "" ? "" : "\n") + newLine + "\n";
  fs.writeFileSync(p, content, "utf8");
  return true;
});

ipcMain.handle("shell:delete", (_e, { key }) => {
  const p = shellProfilePath();
  if (!fs.existsSync(p)) return true;
  let content = fs.readFileSync(p, "utf8");
  const re = new RegExp(`^\\s*export\\s+${key}\\s*=.*\\n?`, "m");
  content = content.replace(re, "");
  fs.writeFileSync(p, content, "utf8");
  return true;
});

// ---------- .env files ----------
function parseEnv(content) {
  const out = [];
  content.split("\n").forEach((line) => {
    if (!line || line.trim().startsWith("#")) return;
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!m) return;
    let val = m[2];
    const hash = val.indexOf(" #");
    if (hash >= 0 && !val.startsWith('"') && !val.startsWith("'")) val = val.slice(0, hash);
    val = val.trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    out.push({ key: m[1], value: val });
  });
  return out;
}

function serializeEnv(vars) {
  return vars
    .map(({ key, value }) => {
      const safe = /[\s"'#]/.test(value) ? `"${value.replace(/(["\\])/g, "\\$1")}"` : value;
      return `${key}=${safe}`;
    })
    .join("\n") + "\n";
}

ipcMain.handle("env:pick", async () => {
  const r = await dialog.showOpenDialog({
    properties: ["openFile"],
    filters: [{ name: "Env files", extensions: ["env", ""] }, { name: "All", extensions: ["*"] }],
  });
  if (r.canceled || !r.filePaths[0]) return null;
  return r.filePaths[0];
});

ipcMain.handle("env:create", async () => {
  const r = await dialog.showSaveDialog({ defaultPath: ".env" });
  if (r.canceled || !r.filePath) return null;
  fs.writeFileSync(r.filePath, "", "utf8");
  return r.filePath;
});

ipcMain.handle("env:read", (_e, filePath) => {
  const content = fs.existsSync(filePath) ? fs.readFileSync(filePath, "utf8") : "";
  return parseEnv(content);
});

ipcMain.handle("env:write", (_e, { filePath, vars }) => {
  fs.writeFileSync(filePath, serializeEnv(vars), "utf8");
  return true;
});

// ---------- macOS Keychain ----------
function sec(args) {
  return new Promise((resolve, reject) => {
    execFile("/usr/bin/security", args, (err, stdout, stderr) => {
      if (err) return reject(new Error(stderr || err.message));
      resolve(stdout);
    });
  });
}

const KEYCHAIN_SERVICE_PREFIX = "SecretSauce:";

function readIndexSafely() {
  const newPath = path.join(os.homedir(), ".secret-sauce-keychain-index.json");
  const oldPath = path.join(os.homedir(), ".env-manager-keychain-index.json");

  // Migrate index if old one exists but new one doesn't
  if (fs.existsSync(oldPath) && !fs.existsSync(newPath)) {
    try {
      fs.copyFileSync(oldPath, newPath);
    } catch (e) {
      console.error("Failed to migrate keychain index:", e);
    }
  }

  const indexPath = fs.existsSync(newPath) ? newPath : oldPath;
  if (!fs.existsSync(indexPath)) return [];
  try {
    const data = fs.readFileSync(indexPath, "utf8").trim();
    if (!data) return [];
    const keys = JSON.parse(data);
    return Array.isArray(keys) ? keys : [];
  } catch {
    return [];
  }
}

ipcMain.handle("keychain:list", async () => {
  return readIndexSafely();
});

function saveIndex(keys) {
  const indexPath = path.join(os.homedir(), ".secret-sauce-keychain-index.json");
  fs.writeFileSync(indexPath, JSON.stringify([...new Set(keys)]), "utf8");
}

ipcMain.handle("keychain:get", async (_e, key) => {
  try {
    const out = await sec(["find-generic-password", "-s", KEYCHAIN_SERVICE_PREFIX + key, "-a", os.userInfo().username, "-w"]);
    return out.trim();
  } catch {
    // Fallback to old service prefix if new one isn't found
    try {
      const out = await sec(["find-generic-password", "-s", "EnvManager:" + key, "-a", os.userInfo().username, "-w"]);
      return out.trim();
    } catch {
      return null;
    }
  }
});

ipcMain.handle("keychain:set", async (_e, { key, value }) => {
  await sec([
    "add-generic-password",
    "-s", KEYCHAIN_SERVICE_PREFIX + key,
    "-a", os.userInfo().username,
    "-w", value,
    "-U",
  ]);
  const keys = readIndexSafely();
  keys.push(key);
  saveIndex(keys);
  return true;
});

ipcMain.handle("keychain:delete", async (_e, key) => {
  try {
    await sec(["delete-generic-password", "-s", KEYCHAIN_SERVICE_PREFIX + key, "-a", os.userInfo().username]);
  } catch {}
  try {
    await sec(["delete-generic-password", "-s", "EnvManager:" + key, "-a", os.userInfo().username]);
  } catch {}
  const keys = readIndexSafely();
  saveIndex(keys.filter((k) => k !== key));
  return true;
});

// ---------- Local System Env ----------
ipcMain.handle("env:system", () => {
  return Object.entries(process.env).map(([key, value]) => ({ key, value: value || "" }));
});

// ---------- Launchd Management ----------

function readPlist(filePath) {
  return new Promise((resolve, reject) => {
    execFile("/usr/bin/plutil", ["-convert", "json", "-o", "-", filePath], (err, stdout, stderr) => {
      if (err) return reject(new Error(stderr || err.message));
      try {
        resolve(JSON.parse(stdout));
      } catch (e) {
        reject(e);
      }
    });
  });
}

function writePlist(filePath, obj) {
  return new Promise((resolve, reject) => {
    const jsonStr = JSON.stringify(obj);
    const child = execFile("/usr/bin/plutil", ["-convert", "xml1", "-o", filePath, "-"], (err, stdout, stderr) => {
      if (err) return reject(new Error(stderr || err.message));
      resolve(true);
    });
    child.stdin.write(jsonStr);
    child.stdin.end();
  });
}

function getLaunchdStatuses() {
  return new Promise((resolve) => {
    execFile("/bin/launchctl", ["list"], (err, stdout) => {
      if (err) return resolve({});
      const statuses = {};
      stdout.split("\n").forEach((line) => {
        const parts = line.split("\t");
        if (parts.length >= 3) {
          const pid = parts[0] === "-" ? null : parseInt(parts[0], 10);
          const lastExitCode = parseInt(parts[1], 10);
          const label = parts[2].trim();
          statuses[label] = { loaded: true, pid, lastExitCode };
        }
      });
      resolve(statuses);
    });
  });
}

ipcMain.handle("launchd:list", async () => {
  const dir = path.join(os.homedir(), "Library", "LaunchAgents");
  if (!fs.existsSync(dir)) return [];
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".plist"));
  
  const statuses = await getLaunchdStatuses();
  const services = [];

  for (const f of files) {
    const filePath = path.join(dir, f);
    try {
      const obj = await readPlist(filePath);
      const label = obj.Label || f.replace(/\.plist$/, "");
      const envObj = obj.EnvironmentVariables || {};
      const vars = Object.entries(envObj).map(([key, value]) => ({ key, value: String(value) }));
      const program = obj.Program || (Array.isArray(obj.ProgramArguments) ? obj.ProgramArguments.join(" ") : "");
      
      const status = statuses[label] || { loaded: false };
      services.push({
        label,
        filePath,
        vars,
        program,
        loaded: status.loaded,
        pid: status.pid,
        lastExitCode: status.lastExitCode,
      });
    } catch (err) {
      console.error(`Failed to read launchd plist ${f}:`, err);
    }
  }

  return services;
});

ipcMain.handle("launchd:upsert", async (_e, { filePath, key, value }) => {
  const obj = await readPlist(filePath);
  if (!obj.EnvironmentVariables) obj.EnvironmentVariables = {};
  obj.EnvironmentVariables[key] = value;
  await writePlist(filePath, obj);
  return true;
});

ipcMain.handle("launchd:delete", async (_e, { filePath, key }) => {
  const obj = await readPlist(filePath);
  if (obj.EnvironmentVariables) {
    delete obj.EnvironmentVariables[key];
    if (Object.keys(obj.EnvironmentVariables).length === 0) {
      delete obj.EnvironmentVariables;
    }
    await writePlist(filePath, obj);
  }
  return true;
});

ipcMain.handle("launchd:control", async (_e, { action, filePath, label }) => {
  let cmd, args;
  if (action === "load") {
    cmd = "/bin/launchctl";
    args = ["load", filePath];
  } else if (action === "unload") {
    cmd = "/bin/launchctl";
    args = ["unload", filePath];
  } else if (action === "start") {
    cmd = "/bin/launchctl";
    args = ["start", label];
  } else if (action === "stop") {
    cmd = "/bin/launchctl";
    args = ["stop", label];
  } else {
    throw new Error("Invalid launchd action");
  }
  return new Promise((resolve, reject) => {
    execFile(cmd, args, (err, stdout, stderr) => {
      if (err) return reject(new Error(stderr || err.message));
      resolve(true);
    });
  });
});

