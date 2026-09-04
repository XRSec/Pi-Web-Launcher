import AppKit
import Foundation

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

@MainActor
final class PiWebController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "已停止"
    @Published private(set) var lastError: String?
    @Published private(set) var runtimeURL = ""
    @Published private(set) var logs = ""
    @Published private(set) var appliedConfigurationRevision = 0

    private var process: Process?
    private var outputPipe: Pipe?

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop()
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard UserDefaults.standard.bool(forKey: SettingsKeys.autoStart) else { return }
            self?.start()
        }
    }

    func start() {
        guard process == nil else { return }

        do {
            lastError = nil
            statusText = "正在启动…"
            appendLogLine("[服务] 正在启动 Pi Web")

            let config = try LaunchConfiguration.current()
            try requireLocalAddress(config.hostname)
            let runtime = try resolveRuntime(config: config)
            try stopSamePortPiWeb(port: config.port)

            let child = Process()
            child.executableURL = URL(fileURLWithPath: runtime.piWeb)
            child.arguments = [
                "--hostname", config.hostname,
                "--port", String(config.port),
                "--no-open",
            ]
            child.currentDirectoryURL = URL(fileURLWithPath: config.workingDirectory)

            var environment = ProcessInfo.processInfo.environment
            config.customEnvironment.forEach { environment[$0.key] = $0.value }
            environment["PATH"] = runtime.path
            environment["PI_WEB_ALLOWED_HOSTS"] = config.allowedHosts
            environment["PI_WEB_PASSWORD"] = config.password
            environment["PI_WEB_CWD"] = config.workingDirectory
            environment["NODE_OPTIONS"] = config.nodeOptions
            environment["PI_WEB_NO_OPEN"] = "1"
            child.environment = environment

            let pipe = Pipe()
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async {
                    self?.consumeOutput(text)
                }
            }
            child.standardOutput = pipe
            child.standardError = pipe

            child.terminationHandler = { [weak self, weak child] _ in
                DispatchQueue.main.async {
                    guard let self, self.process === child else { return }
                    self.finishStoppedState(message: "已停止")
                }
            }

            try child.run()
            process = child
            outputPipe = pipe
            isRunning = true
            statusText = "运行中"
            runtimeURL = config.webURLString
            appliedConfigurationRevision += 1

            if config.openBrowserOnStart {
                let pid = child.processIdentifier
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self,
                          self.process?.processIdentifier == pid,
                          self.process?.isRunning == true else { return }
                    self.openWeb()
                }
            }
        } catch {
            finishStoppedState(message: "启动失败")
            lastError = error.localizedDescription
        }
    }

    func stop() {
        guard let child = process else {
            finishStoppedState(message: "已停止")
            return
        }

        statusText = "正在停止…"
        pipeCleanup()
        child.terminate()

        for _ in 0..<20 where child.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if child.isRunning {
            kill(child.processIdentifier, SIGKILL)
        }

        finishStoppedState(message: "已停止")
    }

    func restart() {
        stop()
        start()
    }

    func checkForUpdates(onUpdate: @escaping (String, URL) -> Void) {
        guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !currentVersion.isEmpty else {
            appendLogLine("[更新] 检查失败：无法读取当前应用版本")
            return
        }

        guard let url = URL(string: "https://api.github.com/repos/XRSec/Pi-Web-Launcher/releases/latest") else {
            appendLogLine("[更新] 检查失败：GitHub Releases 地址无效")
            return
        }

        appendLogLine("[更新] 正在检查 GitHub Releases…")

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pi-Web-Launcher", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.appendLogLine("[更新] 检查失败：\(error.localizedDescription)")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let data else {
                    let status = (response as? HTTPURLResponse)?.statusCode
                    self.appendLogLine("[更新] 检查失败：GitHub 返回状态 \(status.map(String.init) ?? "未知")")
                    return
                }

                do {
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    let latestVersion = self.normalizedVersion(release.tagName)
                    let installedVersion = self.normalizedVersion(currentVersion)

                    if latestVersion.compare(installedVersion, options: .numeric) == .orderedDescending {
                        self.appendLogLine("[更新] 发现新版本 \(release.tagName)，当前版本 v\(installedVersion)")
                        onUpdate(release.tagName, release.htmlURL)
                    } else {
                        self.appendLogLine("[更新] 当前已是最新版本 v\(installedVersion)")
                    }
                } catch {
                    self.appendLogLine("[更新] 检查失败：无法解析 GitHub Release（\(error.localizedDescription)）")
                }
            }
        }.resume()
    }

    func openWeb() {
        let target: String
        if !runtimeURL.isEmpty {
            target = runtimeURL
        } else if let config = try? LaunchConfiguration.current() {
            target = config.webURLString
        } else {
            return
        }

        guard let url = URL(string: target) else { return }
        NSWorkspace.shared.open(url)
    }

    func quit() {
        stop()
        NSApplication.shared.terminate(nil)
    }

    private func consumeOutput(_ text: String) {
        logs += text

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.localizedCaseInsensitiveContains("error") || trimmed.localizedCaseInsensitiveContains("failed") {
            lastError = trimmed
        }
    }

    private func appendLogLine(_ text: String) {
        if !logs.isEmpty && !logs.hasSuffix("\n") {
            logs += "\n"
        }
        logs += text + "\n"
    }

    private func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "v" || first == "V" else { return trimmed }
        return String(trimmed.dropFirst())
    }

    private func finishStoppedState(message: String) {
        pipeCleanup()
        process = nil
        isRunning = false
        statusText = message
        runtimeURL = ""
    }

    private func pipeCleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
    }

    private func requireLocalAddress(_ address: String) throws {
        guard address != "0.0.0.0" else { return }

        let result = try runProcess(executable: "/sbin/ifconfig", arguments: [])
        guard result.status == 0 else {
            throw PiWebError.message("无法读取本机网络接口")
        }

        var found = false
        for line in result.output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.count >= 2,
               fields[0] == "inet",
               fields[1] == Substring(address) {
                found = true
                break
            }
        }

        guard found else {
            throw PiWebError.message("本机未配置 IP \(address)，拒绝启动 pi-web")
        }
    }

    func detectDefaultPath() -> String {
        Self.defaultRuntimePath()
    }

    func detectNodeBinPath(environmentPath: String) -> String? {
        guard let node = resolveExecutable(named: "node", path: baseRuntimePath(environmentPath)) else { return nil }
        return URL(fileURLWithPath: node).deletingLastPathComponent().path
    }

    func detectPiWebPath(nodeBinPath: String, environmentPath: String) -> String? {
        var path = baseRuntimePath(environmentPath)
        let manualNodeBin = expandTilde(nodeBinPath.trimmingCharacters(in: .whitespacesAndNewlines))
        if !manualNodeBin.isEmpty {
            path = prependPath(manualNodeBin, to: path)
        }
        return resolveExecutable(named: "pi-web", path: path)
    }

    private func resolveRuntime(config: LaunchConfiguration) throws -> RuntimeEnvironment {
        var path = baseRuntimePath(config.environmentPath)

        if !config.nodeBinPath.isEmpty {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: config.nodeBinPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw PiWebError.message("Node Bin 目录不存在：\(config.nodeBinPath)")
            }
            let node = URL(fileURLWithPath: config.nodeBinPath).appendingPathComponent("node").path
            guard FileManager.default.isExecutableFile(atPath: node) else {
                throw PiWebError.message("Node Bin 目录中找不到可执行的 node：\(config.nodeBinPath)")
            }
            path = prependPath(config.nodeBinPath, to: path)
        } else if resolveExecutable(named: "node", path: path) == nil {
            throw PiWebError.message("找不到 Node.js，请设置 PATH 或 Node Bin Path")
        }

        let piWeb: String
        if !config.piWebPath.isEmpty {
            guard FileManager.default.isExecutableFile(atPath: config.piWebPath) else {
                throw PiWebError.message("Pi Web 路径不可执行：\(config.piWebPath)")
            }
            piWeb = config.piWebPath
        } else if let detected = resolveExecutable(named: "pi-web", path: path) {
            piWeb = detected
        } else {
            throw PiWebError.message("找不到 pi-web，请设置 Pi Web 路径或运行 npm install -g @agegr/pi-web@latest")
        }

        return RuntimeEnvironment(piWeb: piWeb, path: path)
    }

    private func baseRuntimePath(_ configuredPath: String) -> String {
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Self.defaultRuntimePath() }

        return trimmed
            .split(separator: ":", omittingEmptySubsequences: true)
            .map { expandTilde(String($0)) }
            .joined(separator: ":")
    }

    private func prependPath(_ directory: String, to path: String) -> String {
        ([directory] + path.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { result, item in
                guard !item.isEmpty, !result.contains(item) else { return }
                result.append(item)
            }
            .joined(separator: ":")
    }

    nonisolated static func defaultRuntimePath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let environmentPath = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let commonPaths = [
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.volta/bin",
        ] + nvmBinPaths(home: home) + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
        ]

        return (environmentPath + commonPaths)
            .reduce(into: [String]()) { result, item in
                guard !item.isEmpty, !result.contains(item) else { return }
                result.append(item)
            }
            .joined(separator: ":")
    }

    nonisolated private static func nvmBinPaths(home: String) -> [String] {
        let versionsDirectory = "\(home)/.nvm/versions/node"
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: versionsDirectory) else {
            return []
        }

        return versions
            .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            .map { "\(versionsDirectory)/\($0)/bin" }
    }

    private func resolveExecutable(named command: String, path: String) -> String? {
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(command)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func stopSamePortPiWeb(port: Int) throws {
        let script = #"""
        port="$1"
        listener_pids=($( /usr/sbin/lsof -tiTCP:"$port" -sTCP:LISTEN -n -P 2>/dev/null || true ))
        (( ${#listener_pids[@]} )) || exit 0

        pi_web_pids=()
        for listener_pid in "${listener_pids[@]}"; do
          current_pid="$listener_pid"
          while [[ "$current_pid" == <-> ]] && (( current_pid > 1 )); do
            command="$(ps -o command= -p "$current_pid" 2>/dev/null || true)"
            if [[ "$command" == *"/@agegr/pi-web/bin/pi-web.js"* ]]; then
              pi_web_pids+=("$current_pid")
              break
            fi
            parent_pid="$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ' || true)"
            [[ -n "$parent_pid" && "$parent_pid" != "$current_pid" ]] || break
            current_pid="$parent_pid"
          done
        done

        pi_web_pids=(${(u)pi_web_pids[@]})
        if (( ${#pi_web_pids[@]} == 0 )); then
          exit 2
        fi

        kill "${pi_web_pids[@]}" 2>/dev/null || true
        managed_pids=(${(u)pi_web_pids[@]} ${(u)listener_pids[@]})
        for _ in {1..50}; do
          running=0
          for current_pid in "${managed_pids[@]}"; do
            if kill -0 "$current_pid" 2>/dev/null; then
              running=1
              break
            fi
          done
          (( running )) || exit 0
          sleep 0.1
        done
        kill -KILL "${managed_pids[@]}" 2>/dev/null || true
        """#

        let result = try runProcess(
            executable: "/bin/zsh",
            arguments: ["-c", script, "pi-web-stop", String(port)]
        )
        if result.status == 2 {
            throw PiWebError.message("端口 \(port) 已被其他程序占用，请在设置中更换端口")
        }
        guard result.status == 0 else {
            throw PiWebError.message("无法停止端口 \(port) 上已有的 pi-web")
        }
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> ProcessResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        if let environment {
            var merged = ProcessInfo.processInfo.environment
            environment.forEach { merged[$0.key] = $0.value }
            task.environment = merged
        }

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        return ProcessResult(
            status: task.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

private struct RuntimeEnvironment {
    let piWeb: String
    let path: String
}

private struct ProcessResult {
    let status: Int32
    let output: String
}
