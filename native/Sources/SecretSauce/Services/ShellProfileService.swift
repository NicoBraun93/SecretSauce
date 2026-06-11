import Foundation

/// Edits `export KEY="value"` lines in the user's shell profile, preserving
/// surrounding comments and formatting in place.
enum ShellProfileService {
    static func profilePath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for name in [".zshrc", ".bash_profile", ".bashrc", ".profile"] {
            let p = "\(home)/\(name)"
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return "\(home)/.zshrc"
    }

    static func read() -> (path: String, vars: [EnvVar]) {
        let path = profilePath()
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return (path, parseExports(content))
    }

    static func parseExports(_ content: String) -> [EnvVar] {
        let regex = try! NSRegularExpression(
            pattern: #"^\s*export\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$"#
        )
        var result: [EnvVar] = []
        for line in content.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            guard let m = regex.firstMatch(in: line, range: range),
                  let keyRange = Range(m.range(at: 1), in: line),
                  let valRange = Range(m.range(at: 2), in: line)
            else { continue }
            var val = String(line[valRange]).trimmingCharacters(in: .whitespaces)
            if val.count >= 2,
               (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            result.append(EnvVar(key: String(line[keyRange]), value: val))
        }
        return result
    }

    static func upsert(key: String, value: String) throws {
        let path = profilePath()
        var content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""

        let needsQuoting = value.rangeOfCharacter(from: CharacterSet(charactersIn: " \t\n\"'$`\\")) != nil
        var safe = value
        if needsQuoting {
            // Escape backslashes first so the other escapes are not doubled.
            safe = safe.replacingOccurrences(of: "\\", with: "\\\\")
            safe = safe.replacingOccurrences(of: "\"", with: "\\\"")
            safe = safe.replacingOccurrences(of: "$", with: "\\$")
            safe = safe.replacingOccurrences(of: "`", with: "\\`")
            safe = "\"\(safe)\""
        }
        let newLine = "export \(key)=\(safe)"

        let regex = try NSRegularExpression(
            pattern: "^\\s*export\\s+\(NSRegularExpression.escapedPattern(for: key))\\s*=.*$",
            options: [.anchorsMatchLines]
        )
        let fullRange = NSRange(content.startIndex..., in: content)
        if let m = regex.firstMatch(in: content, range: fullRange),
           let r = Range(m.range, in: content) {
            content.replaceSubrange(r, with: newLine)
        } else {
            if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
            content += newLine + "\n"
        }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func delete(key: String) throws {
        let path = profilePath()
        guard FileManager.default.fileExists(atPath: path) else { return }
        var content = try String(contentsOfFile: path, encoding: .utf8)
        let regex = try NSRegularExpression(
            pattern: "^\\s*export\\s+\(NSRegularExpression.escapedPattern(for: key))\\s*=.*\\n?",
            options: [.anchorsMatchLines]
        )
        let fullRange = NSRange(content.startIndex..., in: content)
        if let m = regex.firstMatch(in: content, range: fullRange),
           let r = Range(m.range, in: content) {
            content.removeSubrange(r)
        }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
