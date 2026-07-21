import Foundation

/// Reads launch agents from ~/Library/LaunchAgents, their runtime status from
/// `launchctl list`, and edits the EnvironmentVariables dict in their plists.
enum LaunchdManager {
    private static var agentsDir: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/Library/LaunchAgents"
    }

    static func list() -> [LaunchdService] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: agentsDir) else { return [] }
        let statuses = launchctlStatuses()
        let rssByPid = residentMemoryByPid()

        var services: [LaunchdService] = []
        for f in files.sorted() where f.hasSuffix(".plist") {
            let filePath = "\(agentsDir)/\(f)"
            guard let obj = try? readPlist(filePath) else { continue }

            let label = (obj["Label"] as? String) ?? String(f.dropLast(".plist".count))
            let envObj = (obj["EnvironmentVariables"] as? [String: Any]) ?? [:]
            let vars = envObj
                .map { EnvVar(key: $0.key, value: String(describing: $0.value)) }
                .sorted { $0.key < $1.key }

            let program: String
            if let p = obj["Program"] as? String {
                program = p
            } else if let args = obj["ProgramArguments"] as? [Any] {
                program = args.map { String(describing: $0) }.joined(separator: " ")
            } else {
                program = ""
            }

            let status = statuses[label]
            services.append(LaunchdService(
                label: label,
                filePath: filePath,
                vars: vars,
                program: program,
                loaded: status != nil,
                pid: status?.pid,
                lastExitCode: status?.lastExitCode,
                memoryBytes: status?.pid.flatMap { rssByPid[$0] }
            ))
        }
        return services
    }

    private static func launchctlStatuses() -> [String: (pid: Int?, lastExitCode: Int?)] {
        guard let out = try? ProcessRunner.run("/bin/launchctl", ["list"]) else { return [:] }
        var statuses: [String: (pid: Int?, lastExitCode: Int?)] = [:]
        for line in out.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }
            let pid = parts[0] == "-" ? nil : Int(parts[0])
            let exitCode = Int(parts[1])
            let label = parts[2].trimmingCharacters(in: .whitespaces)
            statuses[label] = (pid, exitCode)
        }
        return statuses
    }

    /// Maps pid -> resident set size in bytes via a single `ps` call.
    private static func residentMemoryByPid() -> [Int: UInt64] {
        guard let out = try? ProcessRunner.run("/bin/ps", ["-A", "-o", "pid=,rss="]) else { return [:] }
        var map: [Int: UInt64] = [:]
        for line in out.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]), let rssKB = UInt64(parts[1]) else { continue }
            map[pid] = rssKB * 1024
        }
        return map
    }

    private static func readPlist(_ filePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = obj as? [String: Any] else {
            throw ProcessError.failed(command: "plist", stderr: "\(filePath) is not a dictionary plist")
        }
        return dict
    }

    private static func writePlist(_ filePath: String, _ obj: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: obj, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: filePath))
    }

    static func upsertVar(filePath: String, key: String, value: String) throws {
        var obj = try readPlist(filePath)
        var env = (obj["EnvironmentVariables"] as? [String: Any]) ?? [:]
        env[key] = value
        obj["EnvironmentVariables"] = env
        try writePlist(filePath, obj)
    }

    static func deleteVar(filePath: String, key: String) throws {
        var obj = try readPlist(filePath)
        guard var env = obj["EnvironmentVariables"] as? [String: Any] else { return }
        env.removeValue(forKey: key)
        if env.isEmpty {
            obj.removeValue(forKey: "EnvironmentVariables")
        } else {
            obj["EnvironmentVariables"] = env
        }
        try writePlist(filePath, obj)
    }

    enum Action: String {
        case load, unload, start, stop
    }

    static func control(action: Action, filePath: String, label: String) throws {
        switch action {
        case .load: try ProcessRunner.run("/bin/launchctl", ["load", filePath])
        case .unload: try ProcessRunner.run("/bin/launchctl", ["unload", filePath])
        case .start: try ProcessRunner.run("/bin/launchctl", ["start", label])
        case .stop: try ProcessRunner.run("/bin/launchctl", ["stop", label])
        }
    }
}
