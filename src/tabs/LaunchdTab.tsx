import { useEffect, useState } from "react";
import { VarTable } from "./VarTable";

type Service = {
  label: string;
  filePath: string;
  vars: { key: string; value: string }[];
  program: string;
  loaded: boolean;
  pid: number | null;
  lastExitCode?: number;
};

export default function LaunchdTab() {
  const [services, setServices] = useState<Service[]>([]);
  const [selectedLabel, setSelectedLabel] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true);
    try {
      const list = await window.api.launchd.list();
      setServices(list);
      if (list.length > 0 && !selectedLabel) {
        setSelectedLabel(list[0].label);
      }
    } catch (err) {
      console.error("Failed to load launchd services:", err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  const selected = services.find((s) => s.label === selectedLabel) || null;

  const handleControl = async (action: "load" | "unload" | "start" | "stop") => {
    if (!selected) return;
    try {
      await window.api.launchd.control(action, selected.filePath, selected.label);
      // Wait a moment for launchd to refresh then reload
      setTimeout(load, 500);
    } catch (err: any) {
      alert(`launchctl ${action} failed: ${err.message || err}`);
    }
  };

  const handleUpsert = async (key: string, value: string) => {
    if (!selected) return;
    await window.api.launchd.upsert(selected.filePath, key, value);
    await load();
  };

  const handleDelete = async (key: string) => {
    if (!selected) return;
    await window.api.launchd.delete(selected.filePath, key);
    await load();
  };

  return (
    <div className="launchd-layout">
      {/* Sidebar List */}
      <div className="launchd-sidebar">
        <div className="launchd-sidebar-header">
          <h3>Launch Agents</h3>
          <button onClick={load} className="ghost">Refresh</button>
        </div>
        {loading && services.length === 0 ? (
          <div className="empty">Loading...</div>
        ) : services.length === 0 ? (
          <div className="empty">No launch agents found in <code>~/Library/LaunchAgents</code>.</div>
        ) : (
          <div className="launchd-list">
            {services.map((s) => {
              const isSelected = s.label === selectedLabel;
              const isRunning = s.loaded && s.pid !== null;
              return (
                <div
                  key={s.label}
                  className={`launchd-item ${isSelected ? "active" : ""}`}
                  onClick={() => setSelectedLabel(s.label)}
                >
                  <span className={`status-dot ${isRunning ? "running" : s.loaded ? "loaded" : "unloaded"}`}></span>
                  <div className="launchd-item-details">
                    <span className="label-text">{s.label}</span>
                    <span className="filename-text">{s.filePath.split("/").pop()}</span>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Main Details Panel */}
      <div className="launchd-details">
        {selected ? (
          <div className="launchd-details-content">
            <div className="launchd-details-header">
              <h2>{selected.label}</h2>
              <span className="path-pill">{selected.filePath}</span>
            </div>

            {/* Program details */}
            {selected.program && (
              <div className="launchd-program-section">
                <span className="section-title">Exec command</span>
                <code>{selected.program}</code>
              </div>
            )}

            {/* Status grid */}
            <div className="launchd-status-grid">
              <div className="status-card">
                <span className="card-label">State</span>
                <span className={`card-value ${selected.loaded ? "green-text" : "gray-text"}`}>
                  {selected.loaded ? "Loaded" : "Unloaded"}
                </span>
              </div>
              <div className="status-card">
                <span className="card-label">Process (PID)</span>
                <span className={`card-value ${selected.pid ? "green-text" : "gray-text"}`}>
                  {selected.pid ? selected.pid : "Not Running"}
                </span>
              </div>
              {selected.loaded && selected.lastExitCode !== undefined && (
                <div className="status-card">
                  <span className="card-label">Last Exit Code</span>
                  <span className="card-value">{selected.lastExitCode}</span>
                </div>
              )}
            </div>

            {/* Controls */}
            <div className="launchd-controls">
              {!selected.loaded ? (
                <button className="primary" onClick={() => handleControl("load")}>
                  Load Agent Plist
                </button>
              ) : (
                <>
                  <button className="danger" onClick={() => handleControl("unload")}>
                    Unload Agent Plist
                  </button>
                  {selected.pid ? (
                    <button onClick={() => handleControl("stop")}>Stop Service</button>
                  ) : (
                    <button className="primary" onClick={() => handleControl("start")}>
                      Start Service
                    </button>
                  )}
                </>
              )}
            </div>

            {/* Environment Variables Table */}
            <div className="launchd-env-section">
              <div className="section-header">
                <h3>Environment Variables</h3>
                <span className="subtle">Defined under the <code>EnvironmentVariables</code> key.</span>
              </div>
              <VarTable
                vars={selected.vars}
                onUpsert={handleUpsert}
                onDelete={handleDelete}
              />
            </div>
          </div>
        ) : (
          <div className="empty">Select a launch agent from the list to view and manage its configuration.</div>
        )}
      </div>
    </div>
  );
}
