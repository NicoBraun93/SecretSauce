import { useEffect, useState } from "react";
import { VarTable, type Var } from "./VarTable";

export default function ShellTab() {
  const [path, setPath] = useState("");
  const [vars, setVars] = useState<Var[]>([]);

  const load = async () => {
    const r = await window.api.shell.read();
    setPath(r.path);
    setVars(r.vars.map(({ key, value }) => ({ key, value })));
  };

  useEffect(() => { load(); }, []);

  return (
    <>
      <div className="toolbar">
        <span className="subtle">Editing</span>
        <span className="path-pill">{path || "…"}</span>
        <span style={{ flex: 1 }} />
        <span className="subtle">Restart your terminal or run <code>source {path.split("/").pop()}</code> to apply.</span>
      </div>
      <VarTable
        vars={vars}
        onUpsert={async (k, v) => { await window.api.shell.upsert(k, v); load(); }}
        onDelete={async (k) => { await window.api.shell.delete(k); load(); }}
      />
    </>
  );
}
