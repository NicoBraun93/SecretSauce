import { useEffect, useState } from "react";
import { VarTable, type Var } from "./VarTable";

export default function LocalEnvTab() {
  const [vars, setVars] = useState<Var[]>([]);
  const [shellVars, setShellVars] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true);
    try {
      const systemVars = await window.api.env.system();
      systemVars.sort((a, b) => a.key.localeCompare(b.key));
      setVars(systemVars);

      const shellProfile = await window.api.shell.read();
      setShellVars(shellProfile.vars.map((v) => v.key));
    } catch (err) {
      console.error("Failed to load environment variables:", err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
  }, []);

  return (
    <>
      <div className="toolbar">
        <span className="subtle">
          Viewing active session environment variables (<code>process.env</code>). Save any variable to make it persistent in your Shell Profile.
        </span>
        <span style={{ flex: 1 }} />
        <button onClick={load} className="ghost">Refresh</button>
      </div>
      {loading ? (
        <div className="empty">Loading environment variables...</div>
      ) : (
        <VarTable
          vars={vars}
          isSystemEnv={true}
          shellVars={shellVars}
          onUpsert={async (k, v) => {
            await window.api.shell.upsert(k, v);
            await load();
          }}
          onDelete={async (k) => {
            await window.api.shell.delete(k);
            await load();
          }}
        />
      )}
    </>
  );
}
