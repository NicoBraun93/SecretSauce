const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("api", {
  shell: {
    path: () => ipcRenderer.invoke("shell:path"),
    read: () => ipcRenderer.invoke("shell:read"),
    upsert: (key, value) => ipcRenderer.invoke("shell:upsert", { key, value }),
    delete: (key) => ipcRenderer.invoke("shell:delete", { key }),
  },
  env: {
    pick: () => ipcRenderer.invoke("env:pick"),
    create: () => ipcRenderer.invoke("env:create"),
    read: (filePath) => ipcRenderer.invoke("env:read", filePath),
    write: (filePath, vars) => ipcRenderer.invoke("env:write", { filePath, vars }),
    system: () => ipcRenderer.invoke("env:system"),
  },
  keychain: {
    list: () => ipcRenderer.invoke("keychain:list"),
    get: (key) => ipcRenderer.invoke("keychain:get", key),
    set: (key, value) => ipcRenderer.invoke("keychain:set", { key, value }),
    delete: (key) => ipcRenderer.invoke("keychain:delete", key),
  },
  launchd: {
    list: () => ipcRenderer.invoke("launchd:list"),
    upsert: (filePath, key, value) => ipcRenderer.invoke("launchd:upsert", { filePath, key, value }),
    delete: (filePath, key) => ipcRenderer.invoke("launchd:delete", { filePath, key }),
    control: (action, filePath, label) => ipcRenderer.invoke("launchd:control", { action, filePath, label }),
  },
});
