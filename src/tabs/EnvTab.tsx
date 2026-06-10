import { useState } from "react";
import { VarTable, type Var } from "./VarTable";

export default function EnvTab() {
  const [filePath, setFilePath] = useState<string | null>(null);
  const [vars, setVars] = useState<Var[]>([]);

  const load = async (p: string) => {
    const v = await window.api.env.read(p);
    setVars(v);
  };

  const open = async () => {
    const p = await window.api.env.pick();
    if (p) { setFilePath(p); load(p); }
  };
  const create = async () => {
    const p = await window.api.env.create();
    if (p) { setFilePath(p); setVars([]); }
  };

  const persist = async (next: Var[]) => {
    if (!filePath) return;
    await window.api.env.write(filePath, next);
    setVars(next);
  };

  return (
    <>
      <div className="toolbar">
        <button onClick={open}>Open .env file…</button>
        <button onClick={create}>New .env file…</button>
        {filePath && <><span className="subtle">File</span><span className="path-pill">{filePath}</span></>}
      </div>
      {!filePath ? (
        <div className="empty">Open or create a .env file to manage its variables.</div>
      ) : (
        <VarTable
          vars={vars}
          onUpsert={(k, v) => {
            const next = vars.some((x) => x.key === k)
              ? vars.map((x) => (x.key === k ? { key: k, value: v } : x))
              : [...vars, { key: k, value: v }];
            return persist(next);
          }}
          onDelete={(k) => persist(vars.filter((x) => x.key !== k))}
        />
      )}
    </>
  );
}
