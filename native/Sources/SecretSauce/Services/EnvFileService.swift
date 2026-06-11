import Foundation

/// Parses and serializes .env files: `#` lines are skipped, a ` #` suffix on
/// unquoted values is stripped, and values containing whitespace, quotes, or
/// `#` are double-quoted on write.
enum EnvFileService {
    static func read(filePath: String) -> [EnvVar] {
        let content = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? ""
        return parse(content)
    }

    static func parse(_ content: String) -> [EnvVar] {
        let regex = try! NSRegularExpression(
            pattern: #"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$"#
        )
        var out: [EnvVar] = []
        for line in content.components(separatedBy: "\n") {
            if line.isEmpty || line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            let range = NSRange(line.startIndex..., in: line)
            guard let m = regex.firstMatch(in: line, range: range),
                  let keyRange = Range(m.range(at: 1), in: line),
                  let valRange = Range(m.range(at: 2), in: line)
            else { continue }
            var val = String(line[valRange])
            if !val.hasPrefix("\"") && !val.hasPrefix("'"),
               let hashRange = val.range(of: " #") {
                val = String(val[..<hashRange.lowerBound])
            }
            val = val.trimmingCharacters(in: .whitespaces)
            if val.count >= 2,
               (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                val = String(val.dropFirst().dropLast())
            }
            out.append(EnvVar(key: String(line[keyRange]), value: val))
        }
        return out
    }

    static func write(filePath: String, vars: [EnvVar]) throws {
        try serialize(vars).write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    static func serialize(_ vars: [EnvVar]) -> String {
        vars.map { v in
            let needsQuoting = v.value.rangeOfCharacter(from: CharacterSet(charactersIn: " \t\n\"'#")) != nil
            if needsQuoting {
                var safe = v.value.replacingOccurrences(of: "\\", with: "\\\\")
                safe = safe.replacingOccurrences(of: "\"", with: "\\\"")
                return "\(v.key)=\"\(safe)\""
            }
            return "\(v.key)=\(v.value)"
        }
        .joined(separator: "\n") + "\n"
    }
}
