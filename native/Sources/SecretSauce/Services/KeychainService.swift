import Foundation

/// Stores secrets as generic passwords via /usr/bin/security under service
/// `SecretSauce:<key>` (with read/delete fallback to the legacy `EnvManager:`
/// namespace) and a JSON index file listing known keys.
///
/// The `security` CLI is used instead of the SecItem API on purpose — existing
/// entries were created by the CLI and their access control lists are bound to
/// it, so going through the same binary avoids authorization prompts.
enum KeychainService {
    static let servicePrefix = "SecretSauce:"
    static let legacyServicePrefix = "EnvManager:"

    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }
    private static var newIndexPath: String { "\(home)/.secret-sauce-keychain-index.json" }
    private static var oldIndexPath: String { "\(home)/.env-manager-keychain-index.json" }
    private static var account: String { NSUserName() }

    static func list() -> [String] {
        readIndexSafely()
    }

    private static func readIndexSafely() -> [String] {
        let fm = FileManager.default
        if fm.fileExists(atPath: oldIndexPath) && !fm.fileExists(atPath: newIndexPath) {
            try? fm.copyItem(atPath: oldIndexPath, toPath: newIndexPath)
        }
        let indexPath = fm.fileExists(atPath: newIndexPath) ? newIndexPath : oldIndexPath
        guard fm.fileExists(atPath: indexPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: indexPath)),
              !data.isEmpty,
              let keys = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return keys
    }

    private static func saveIndex(_ keys: [String]) {
        var seen = Set<String>()
        let unique = keys.filter { seen.insert($0).inserted }
        if let data = try? JSONEncoder().encode(unique) {
            try? data.write(to: URL(fileURLWithPath: newIndexPath))
        }
    }

    static func get(key: String) -> String? {
        for prefix in [servicePrefix, legacyServicePrefix] {
            if let out = try? ProcessRunner.run(
                "/usr/bin/security",
                ["find-generic-password", "-s", prefix + key, "-a", account, "-w"]
            ) {
                return out.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    static func set(key: String, value: String) throws {
        try ProcessRunner.run(
            "/usr/bin/security",
            ["add-generic-password", "-s", servicePrefix + key, "-a", account, "-w", value, "-U"]
        )
        var keys = readIndexSafely()
        keys.append(key)
        saveIndex(keys)
    }

    static func delete(key: String) {
        for prefix in [servicePrefix, legacyServicePrefix] {
            _ = try? ProcessRunner.run(
                "/usr/bin/security",
                ["delete-generic-password", "-s", prefix + key, "-a", account]
            )
        }
        saveIndex(readIndexSafely().filter { $0 != key })
    }
}
