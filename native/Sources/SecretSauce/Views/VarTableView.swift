import SwiftUI

/// Reusable key/value table with search, add row, inline editing, optional
/// secret reveal, and optional system-env persist/unpersist actions.
struct VarTableView: View {
    var vars: [EnvVar]
    var onUpsert: (String, String) async -> Void
    var onDelete: (String) async -> Void
    var secret: Bool = false
    var onReveal: ((String) async -> String?)? = nil
    var isSystemEnv: Bool = false
    var shellVars: Set<String> = []

    @State private var newKey = ""
    @State private var newValue = ""
    @State private var editingKey: String?
    @State private var editValue = ""
    @State private var revealed: [String: String] = [:]
    @State private var search = ""

    private var filteredVars: [EnvVar] {
        guard !search.isEmpty else { return vars }
        let q = search.lowercased()
        return vars.filter {
            $0.key.lowercased().contains(q) || $0.value.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter variables by key or value…", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding([.horizontal, .top], 12)

            addRow
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if filteredVars.isEmpty {
                Spacer()
                Text("No variables found.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filteredVars) { v in
                    row(for: v)
                        .listRowSeparator(.visible)
                }
                .listStyle(.plain)
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("NEW_KEY", text: $newKey)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: 260)
            TextField("value", text: $newValue)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { add() }
            Button("Add") { add() }
                .buttonStyle(.borderedProminent)
                .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        let value = newValue
        Task {
            await onUpsert(key, value)
            newKey = ""
            newValue = ""
        }
    }

    @ViewBuilder
    private func row(for v: EnvVar) -> some View {
        let isEditing = editingKey == v.key
        let isPersistent = isSystemEnv && shellVars.contains(v.key)

        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(v.key)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isSystemEnv {
                    Text(isPersistent ? "Persistent" : "Session Only")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (isPersistent ? Color.green : Color.orange).opacity(0.18),
                            in: Capsule()
                        )
                        .foregroundStyle(isPersistent ? Color.green : Color.orange)
                }
            }
            .frame(width: 280, alignment: .leading)

            if isEditing {
                TextField("value", text: $editValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { saveEdit() }
            } else {
                Text(secret ? (revealed[v.key] ?? "••••••••") : v.value)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            HStack(spacing: 6) {
                if isEditing {
                    Button("Save") { saveEdit() }.buttonStyle(.borderedProminent)
                    Button("Cancel") { editingKey = nil }.buttonStyle(.bordered)
                } else {
                    if secret {
                        Button(revealed[v.key] != nil ? "Hide" : "Reveal") {
                            toggleReveal(v.key)
                        }
                        .buttonStyle(.bordered)
                    }
                    if isSystemEnv && !isPersistent {
                        Button("Persist") {
                            Task { await onUpsert(v.key, v.value) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Edit") { startEdit(v) }.buttonStyle(.bordered)
                    if !isSystemEnv || isPersistent {
                        Button(isSystemEnv ? "Unpersist" : "Delete", role: .destructive) {
                            Task { await onDelete(v.key) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func startEdit(_ v: EnvVar) {
        editingKey = v.key
        editValue = secret ? (revealed[v.key] ?? "") : v.value
    }

    private func saveEdit() {
        guard let key = editingKey else { return }
        let value = editValue
        Task {
            await onUpsert(key, value)
            editingKey = nil
            editValue = ""
        }
    }

    private func toggleReveal(_ key: String) {
        if revealed[key] != nil {
            revealed.removeValue(forKey: key)
            return
        }
        guard let onReveal else { return }
        Task {
            if let value = await onReveal(key) {
                revealed[key] = value
            }
        }
    }
}
