import Foundation

struct EnvVar: Identifiable, Equatable {
    var key: String
    var value: String
    var id: String { key }
}

struct LaunchdService: Identifiable, Equatable {
    var label: String
    var filePath: String
    var vars: [EnvVar]
    var program: String
    var loaded: Bool
    var pid: Int?
    var lastExitCode: Int?
    var id: String { label }
}
