import Foundation

enum SettingsKeys {
    static let hostname = "hostname"
    static let port = "port"
    static let allowedHosts = "allowedHosts"
    static let workingDirectory = "workingDirectory"
    static let nodeBinPath = "nodeBinPath"
    static let piWebPath = "piWebPath"
    static let environmentPath = "environmentPath"
    static let nodeOptions = "nodeOptions"
    static let password = "password"
    static let customEnvironmentVariables = "customEnvironmentVariables"
    static let autoStart = "autoStart"
    static let openBrowserOnStart = "openBrowserOnStart"
}

enum PiWebDefaults {
    static let hostname = "127.0.0.1"
    static let port = "30141"
    static let allowedHosts = ""
    static let workingDirectory = "~"
    static let nodeBinPath = ""
    static let piWebPath = ""
    static var environmentPath: String {
        PiWebController.defaultRuntimePath()
    }
    static let password = ""
    static let nodeOptions = ""
    static let autoStart = false
    static let openBrowserOnStart = true

    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKeys.hostname: hostname,
            SettingsKeys.port: port,
            SettingsKeys.allowedHosts: allowedHosts,
            SettingsKeys.workingDirectory: workingDirectory,
            SettingsKeys.nodeBinPath: nodeBinPath,
            SettingsKeys.piWebPath: piWebPath,
            SettingsKeys.environmentPath: environmentPath,
            SettingsKeys.password: password,
            SettingsKeys.nodeOptions: nodeOptions,
            SettingsKeys.customEnvironmentVariables: "[]",
            SettingsKeys.autoStart: autoStart,
            SettingsKeys.openBrowserOnStart: openBrowserOnStart,
        ])
    }
}

struct EnvironmentVariable: Identifiable, Codable, Equatable {
    var id = UUID()
    var name = ""
    var value = ""
}

enum EnvironmentVariableStore {
    static func load() -> [EnvironmentVariable] {
        guard let json = UserDefaults.standard.string(forKey: SettingsKeys.customEnvironmentVariables),
              let data = json.data(using: .utf8),
              let variables = try? JSONDecoder().decode([EnvironmentVariable].self, from: data) else {
            return []
        }
        return variables
    }

    static func save(_ variables: [EnvironmentVariable]) {
        guard let data = try? JSONEncoder().encode(variables),
              let json = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(json, forKey: SettingsKeys.customEnvironmentVariables)
    }
}

struct LaunchConfiguration {
    static let builtInEnvironmentNames: Set<String> = [
        "PATH",
        "PI_WEB_ALLOWED_HOSTS",
        "PI_WEB_PASSWORD",
        "PI_WEB_CWD",
        "NODE_OPTIONS",
    ]

    let hostname: String
    let port: Int
    let allowedHosts: String
    let password: String
    let workingDirectory: String
    let nodeBinPath: String
    let piWebPath: String
    let environmentPath: String
    let nodeOptions: String
    let customEnvironment: [String: String]
    let openBrowserOnStart: Bool

    static func current() throws -> LaunchConfiguration {
        let defaults = UserDefaults.standard
        let hostname = defaults.string(forKey: SettingsKeys.hostname)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let portText = defaults.string(forKey: SettingsKeys.port)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let allowedHosts = defaults.string(forKey: SettingsKeys.allowedHosts)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = defaults.string(forKey: SettingsKeys.password) ?? ""
        let workingDirectory = expandTilde(defaults.string(forKey: SettingsKeys.workingDirectory) ?? "")
        let nodeBinPath = expandOptionalPath(defaults.string(forKey: SettingsKeys.nodeBinPath) ?? "")
        let piWebPath = expandOptionalPath(defaults.string(forKey: SettingsKeys.piWebPath) ?? "")
        let environmentPath = defaults.string(forKey: SettingsKeys.environmentPath)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nodeOptions = defaults.string(forKey: SettingsKeys.nodeOptions)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !hostname.isEmpty else {
            throw PiWebError.message("监听 IP 不能为空")
        }
        guard let port = Int(portText), (1...65535).contains(port) else {
            throw PiWebError.message("端口必须是 1–65535 之间的整数")
        }
        guard !workingDirectory.isEmpty else {
            throw PiWebError.message("工作目录不能为空")
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PiWebError.message("工作目录不存在：\(workingDirectory)")
        }

        var customEnvironment: [String: String] = [:]
        for variable in EnvironmentVariableStore.load() {
            let name = variable.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard isValidEnvironmentName(name) else {
                throw PiWebError.message("环境变量名无效：\(name)")
            }
            guard !builtInEnvironmentNames.contains(name) else {
                throw PiWebError.message("环境变量 \(name) 请直接在默认变量中修改")
            }
            customEnvironment[name] = variable.value
        }

        return LaunchConfiguration(
            hostname: hostname,
            port: port,
            allowedHosts: allowedHosts,
            password: password,
            workingDirectory: workingDirectory,
            nodeBinPath: nodeBinPath,
            piWebPath: piWebPath,
            environmentPath: environmentPath,
            nodeOptions: nodeOptions,
            customEnvironment: customEnvironment,
            openBrowserOnStart: defaults.bool(forKey: SettingsKeys.openBrowserOnStart)
        )
    }

    var webURLString: String {
        let host = allowedHosts
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? hostname
        return "http://\(host):\(port)"
    }

    private static func isValidEnvironmentName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }
}

func expandTilde(_ path: String) -> String {
    NSString(string: path).expandingTildeInPath
}

private func expandOptionalPath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "" : expandTilde(trimmed)
}

enum PiWebError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        }
    }
}
