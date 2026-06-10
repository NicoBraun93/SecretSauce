import { useState } from "react";

export type Var = { key: string; value: string };

export function VarTable({
  vars,
  onUpsert,
  onDelete,
  secret = false,
  onReveal,
  isSystemEnv = false,
  shellVars = [],
}: {
  vars: Var[];
  onUpsert: (key: string, value: string) => Promise<void> | void;
  onDelete: (key: string) => Promise<void> | void;
  secret?: boolean;
  onReveal?: (key: string) => Promise<string | null>;
  isSystemEnv?: boolean;
  shellVars?: string[];
}) {
  const [newKey, setNewKey] = useState("");
  const [newVal, setNewVal] = useState("");
  const [editing, setEditing] = useState<string | null>(null);
  const [editVal, setEditVal] = useState("");
  const [revealed, setRevealed] = useState<Record<string, string>>({});
  const [search, setSearch] = useState("");

  const add = async () => {
    if (!newKey.trim()) return;
    await onUpsert(newKey.trim(), newVal);
    setNewKey("");
    setNewVal("");
  };

  const startEdit = (v: Var) => {
    setEditing(v.key);
    setEditVal(secret ? (revealed[v.key] ?? "") : v.value);
  };

  const saveEdit = async () => {
    if (!editing) return;
    await onUpsert(editing, editVal);
    setEditing(null);
    setEditVal("");
  };

  const reveal = async (key: string) => {
    if (!onReveal) return;
    if (revealed[key] !== undefined) {
      const r = { ...revealed };
      delete r[key];
      setRevealed(r);
    } else {
      const v = await onReveal(key);
      if (v !== null) setRevealed({ ...revealed, [key]: v });
    }
  };

  const filteredVars = vars.filter(
    (v) =>
      v.key.toLowerCase().includes(search.toLowerCase()) ||
      v.value.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="table-container">
      <div className="table-header-toolbar">
        <input
          type="text"
          className="search-input"
          placeholder="Filter variables by key or value..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>

      <table>
        <thead>
          <tr>
            <th className="col-key">Key</th>
            <th className="col-val">Value</th>
            <th className="col-actions"></th>
          </tr>
        </thead>
        <tbody>
          <tr className="add-row">
            <td>
              <input
                placeholder="NEW_KEY"
                value={newKey}
                onChange={(e) => setNewKey(e.target.value)}
              />
            </td>
            <td>
              <input
                placeholder="value"
                value={newVal}
                onChange={(e) => setNewVal(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && add()}
              />
            </td>
            <td>
              <div className="row-actions">
                <button className="primary" onClick={add}>
                  Add
                </button>
              </div>
            </td>
          </tr>
          {filteredVars.length === 0 && (
            <tr>
              <td colSpan={3} className="empty">
                No variables found.
              </td>
            </tr>
          )}
          {filteredVars.map((v) => {
            const isEditing = editing === v.key;
            const shown = secret ? revealed[v.key] ?? "••••••••" : v.value;
            const isPersistent = isSystemEnv && shellVars.includes(v.key);

            return (
              <tr key={v.key}>
                <td className="key">
                  <div className="key-wrapper">
                    <span>{v.key}</span>
                    {isSystemEnv && (
                      <span className={`badge ${isPersistent ? "badge-persistent" : "badge-session"}`}>
                        {isPersistent ? "Persistent" : "Session Only"}
                      </span>
                    )}
                  </div>
                </td>
                <td className="value">
                  {isEditing ? (
                    <input
                      value={editVal}
                      onChange={(e) => setEditVal(e.target.value)}
                      autoFocus
                      onKeyDown={(e) => e.key === "Enter" && saveEdit()}
                    />
                  ) : (
                    shown
                  )}
                </td>
                <td>
                  <div className="row-actions">
                    {isEditing ? (
                      <>
                        <button className="primary" onClick={saveEdit}>
                          Save
                        </button>
                        <button className="ghost" onClick={() => setEditing(null)}>
                          Cancel
                        </button>
                      </>
                    ) : (
                      <>
                        {secret && (
                          <button className="ghost" onClick={() => reveal(v.key)}>
                            {revealed[v.key] !== undefined ? "Hide" : "Reveal"}
                          </button>
                        )}
                        {isSystemEnv && !isPersistent && (
                          <button className="primary" onClick={() => onUpsert(v.key, v.value)}>
                            Persist
                          </button>
                        )}
                        <button onClick={() => startEdit(v)}>Edit</button>
                        {(!isSystemEnv || isPersistent) && (
                          <button className="danger" onClick={() => onDelete(v.key)}>
                            {isSystemEnv ? "Unpersist" : "Delete"}
                          </button>
                        )}
                      </>
                    )}
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
