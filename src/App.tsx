import { useState } from "react";
import ShellTab from "./tabs/ShellTab";
import EnvTab from "./tabs/EnvTab";
import KeychainTab from "./tabs/KeychainTab";
import LocalEnvTab from "./tabs/LocalEnvTab";
import LaunchdTab from "./tabs/LaunchdTab";

type Tab = "localEnv" | "shell" | "env" | "keychain" | "launchd";

export default function App() {
  const [tab, setTab] = useState<Tab>("localEnv");

  return (
    <div className="app">
      <div className="titlebar">SecretSauce</div>
      <div className="tabs">
        <div className={`tab ${tab === "localEnv" ? "active" : ""}`} onClick={() => setTab("localEnv")}>
          Local Env
        </div>
        <div className={`tab ${tab === "shell" ? "active" : ""}`} onClick={() => setTab("shell")}>
          Shell Profile
        </div>
        <div className={`tab ${tab === "env" ? "active" : ""}`} onClick={() => setTab("env")}>
          .env Files
        </div>
        <div className={`tab ${tab === "keychain" ? "active" : ""}`} onClick={() => setTab("keychain")}>
          Keychain Secrets
        </div>
        <div className={`tab ${tab === "launchd" ? "active" : ""}`} onClick={() => setTab("launchd")}>
          Launchd Services
        </div>
      </div>
      <div className="content">
        {tab === "localEnv" && <LocalEnvTab />}
        {tab === "shell" && <ShellTab />}
        {tab === "env" && <EnvTab />}
        {tab === "keychain" && <KeychainTab />}
        {tab === "launchd" && <LaunchdTab />}
      </div>
    </div>
  );
}
