import { useEffect, useState } from "react";
import { VarTable, type Var } from "./VarTable";

export default function KeychainTab() {
  const [keys, setKeys] = useState<string[]>([]);

  const load = async () => setKeys(await window.api.keychain.list());
  useEffect(() => { load(); }, []);

  const vars: Var[] = keys.map((k) => ({ key: k, value: "" }));

  return (
    <>
      <div className="toolbar">
        <span className="subtle">Secrets are stored in the macOS Keychain under service <code>SecretSauce:&lt;key&gt;</code>.</span>
      </div>
      <VarTable
        vars={vars}
        secret
        onReveal={(k) => window.api.keychain.get(k)}
        onUpsert={async (k, v) => { await window.api.keychain.set(k, v); load(); }}
        onDelete={async (k) => { await window.api.keychain.delete(k); load(); }}
      />
    </>
  );
}
