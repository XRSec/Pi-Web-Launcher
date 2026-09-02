import AppKit
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let controller = PiWebController()
    private var settingsWindowController: NSWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        PiWebDefaults.register()
        setupStatusItem()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "退出 Pi Web", action: #selector(quitAction), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Standard Edit Menu for Cut/Copy/Paste/Select All shortcuts
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "撤销", action: #selector(UndoManager.undo), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: #selector(UndoManager.redo), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        button.image = PiWebImages.menuBarIcon
        button.image?.size = NSSize(width: 22, height: 22)
        button.imagePosition = .imageOnly
        button.toolTip = "Pi Web"

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let statusMenuItem = NSMenuItem(title: "  \(controller.statusText)", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        if let statusImage = NSImage(systemSymbolName: controller.isRunning ? "circle.fill" : "circle", accessibilityDescription: nil) {
            statusImage.size = NSSize(width: 12, height: 12)
            statusMenuItem.image = statusImage
        }
        menu.addItem(statusMenuItem)

        if controller.lastError != nil {
            let errorItem = NSMenuItem(title: "  查看设置中的错误信息", action: #selector(openSettingsAction), keyEquivalent: "")
            errorItem.target = self
            if let warnImage = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil) {
                warnImage.size = NSSize(width: 12, height: 12)
                errorItem.image = warnImage
            }
            menu.addItem(errorItem)
        }

        menu.addItem(NSMenuItem.separator())

        if controller.isRunning {
            let openItem = NSMenuItem(title: "打开 Pi Web", action: #selector(openWebAction), keyEquivalent: "")
            openItem.target = self
            if let safariImage = NSImage(systemSymbolName: "safari", accessibilityDescription: nil) {
                safariImage.size = NSSize(width: 14, height: 14)
                openItem.image = safariImage
            }
            menu.addItem(openItem)

            let restartItem = NSMenuItem(title: "重启服务", action: #selector(restartAction), keyEquivalent: "")
            restartItem.target = self
            if let restartImage = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil) {
                restartImage.size = NSSize(width: 14, height: 14)
                restartItem.image = restartImage
            }
            menu.addItem(restartItem)

            let stopItem = NSMenuItem(title: "停止服务", action: #selector(stopAction), keyEquivalent: "")
            stopItem.target = self
            if let stopImage = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil) {
                stopImage.size = NSSize(width: 14, height: 14)
                stopItem.image = stopImage
            }
            menu.addItem(stopItem)
        } else {
            let startItem = NSMenuItem(title: "启动 Pi Web", action: #selector(startAction), keyEquivalent: "")
            startItem.target = self
            if let playImage = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil) {
                playImage.size = NSSize(width: 14, height: 14)
                startItem.image = playImage
            }
            menu.addItem(startItem)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsMenuItem = NSMenuItem(title: "设置…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsMenuItem.target = self
        if let gearImage = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) {
            gearImage.size = NSSize(width: 14, height: 14)
            settingsMenuItem.image = gearImage
        }
        menu.addItem(settingsMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 Pi Web", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        if let powerImage = NSImage(systemSymbolName: "power", accessibilityDescription: nil) {
            powerImage.size = NSSize(width: 14, height: 14)
            quitItem.image = powerImage
        }
        menu.addItem(quitItem)
    }

    @objc private func openWebAction() {
        controller.openWeb()
    }

    @objc private func restartAction() {
        controller.restart()
    }

    @objc private func stopAction() {
        controller.stop()
    }

    @objc private func startAction() {
        controller.start()
    }

    @objc private func openSettingsAction() {
        showSettingsWindow()
    }

    @objc private func quitAction() {
        controller.quit()
    }

    private func showSettingsWindow() {
        if let window = settingsWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(controller: controller)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Pi Web 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 700, height: 760))
        window.center()
        window.isReleasedWhenClosed = false

        let windowController = NSWindowController(window: window)
        self.settingsWindowController = windowController

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private enum PiWebImages {
    static let menuBarIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "PiWeb", withExtension: "icns"),
           let source = NSImage(contentsOf: url),
           let image = source.copy() as? NSImage {
            image.size = NSSize(width: 22, height: 22)
            image.isTemplate = false
            return image
        }

        let image = NSImage(systemSymbolName: "network", accessibilityDescription: "Pi Web") ?? NSImage()
        image.size = NSSize(width: 22, height: 22)
        return image
    }()
}

private struct SettingsView: View {
    @ObservedObject var controller: PiWebController

    @AppStorage(SettingsKeys.hostname) private var hostname = PiWebDefaults.hostname
    @AppStorage(SettingsKeys.port) private var port = PiWebDefaults.port
    @AppStorage(SettingsKeys.allowedHosts) private var allowedHosts = PiWebDefaults.allowedHosts
    @AppStorage(SettingsKeys.workingDirectory) private var workingDirectory = PiWebDefaults.workingDirectory
    @AppStorage(SettingsKeys.nodeBinPath) private var nodeBinPath = PiWebDefaults.nodeBinPath
    @AppStorage(SettingsKeys.piWebPath) private var piWebPath = PiWebDefaults.piWebPath
    @AppStorage(SettingsKeys.environmentPath) private var environmentPath = PiWebDefaults.environmentPath
    @AppStorage(SettingsKeys.nodeOptions) private var nodeOptions = PiWebDefaults.nodeOptions
    @AppStorage(SettingsKeys.autoStart) private var autoStart = PiWebDefaults.autoStart
    @AppStorage(SettingsKeys.openBrowserOnStart) private var openBrowserOnStart = PiWebDefaults.openBrowserOnStart
    @AppStorage(SettingsKeys.password) private var password = PiWebDefaults.password

    @State private var customEnvironmentVariables = EnvironmentVariableStore.load()
    @State private var detectionMessage: String?
    @State private var availableIPs: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    serviceCard
                    runtimeCard
                    environmentCard
                    launchCard
                    statusCard
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(width: 700, height: 760)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            availableIPs = getLocalIPAddresses()
            if !availableIPs.contains(hostname) {
                availableIPs.append(hostname)
            }
            bringToForegroundWhenOpen()
        }
        .onChange(of: customEnvironmentVariables) { newValue in
            EnvironmentVariableStore.save(newValue)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "network")
                .font(.system(size: 23, weight: .semibold))
                .foregroundColor(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Pi Web Launcher")
                    .font(.title2.weight(.semibold))
                Text("启动、配置并管理本机 Pi Web")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(controller.isRunning ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(controller.statusText)
                    .font(.callout.weight(.medium))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(Color.primary.opacity(0.06))
            )

            Button(action: {
                controller.isRunning ? controller.openWeb() : controller.start()
            }) {
                Label(
                    controller.isRunning ? "打开" : "启动",
                    systemImage: controller.isRunning ? "arrow.up.forward.square" : "play.fill"
                )
            }
            .buttonStyle(ProminentButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var serviceCard: some View {
        SettingsCard(
            title: "服务访问",
            subtitle: "设置 Pi Web 的监听地址",
            systemImage: "server.rack"
        ) {
            SettingRow(title: "监听 IP", subtitle: "默认 127.0.0.1，仅允许本机访问") {
                HStack(spacing: 8) {
                    Picker("", selection: $hostname) {
                        ForEach(availableIPs, id: \.self) { ip in
                            Text(ip).tag(ip)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 250)
                    .labelsHidden()

                    Button {
                        availableIPs = getLocalIPAddresses()
                        if !availableIPs.contains(hostname) {
                            availableIPs.append(hostname)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("刷新可用网卡 IP")
                }
            }

            SettingDivider()

            SettingRow(title: "端口", subtitle: "Pi Web 服务端口") {
                TextField("30141", text: $port)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 310)
            }
        }
    }

    private var runtimeCard: some View {
        SettingsCard(
            title: "运行时",
            subtitle: "留空时自动检测，也可以手动指定",
            systemImage: "terminal"
        ) {
            SettingRow(title: "工作目录", subtitle: "Pi Web 启动后的默认目录") {
                HStack(spacing: 8) {
                    TextField("~", text: $workingDirectory)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 230)
                    Button("选择…") {
                        chooseWorkingDirectory()
                    }
                }
            }

            SettingDivider()

            SettingRow(title: "Node Bin Path", subtitle: "例如 /opt/homebrew/bin 或 ~/.nvm/.../bin") {
                HStack(spacing: 8) {
                    TextField("留空自动检测", text: $nodeBinPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 230)
                    Button("检测") {
                        detectNodeBinPath()
                    }
                }
            }

            SettingDivider()

            SettingRow(title: "Pi Web Path", subtitle: "pi-web 可执行文件路径") {
                HStack(spacing: 8) {
                    TextField("留空自动检测", text: $piWebPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 230)
                    Button("检测") {
                        detectPiWebPath()
                    }
                }
            }

            if let detectionMessage {
                Text(detectionMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var environmentCard: some View {
        SettingsCard(
            title: "环境变量",
            subtitle: "默认值可直接覆盖，也可以继续添加任意自定义变量",
            systemImage: "curlybraces"
        ) {
            EnvironmentRow(name: "PATH", subtitle: "运行时 PATH 环境变量；可直接修改，也可点击重新检测") {
                HStack(spacing: 8) {
                    TextField("留空自动生成", text: $environmentPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(.callout, design: .monospaced))
                        .frame(width: 230)
                    Button("检测") {
                        detectEnvironmentPath()
                    }
                }
            }

            SettingDivider()

            EnvironmentRow(name: "PI_WEB_ALLOWED_HOSTS", subtitle: "反向代理或自定义域名，可留空") {
                TextField("例如 pi.example.com", text: $allowedHosts)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 310)
            }

            SettingDivider()

            EnvironmentRow(name: "PI_WEB_PASSWORD", subtitle: "Basic Auth 密码") {
                SecureField("留空表示不启用", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 310)
            }

            SettingDivider()

            EnvironmentRow(name: "NODE_OPTIONS", subtitle: "可选的 Node.js 运行参数") {
                TextField("例如 --use-system-ca", text: $nodeOptions)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 310)
            }

            ForEach($customEnvironmentVariables) { $variable in
                SettingDivider()

                HStack(spacing: 10) {
                    TextField("变量名", text: $variable.name)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.system(.callout, design: .monospaced))
                        .frame(width: 190)

                    TextField("值", text: $variable.value)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)

                    Button(action: {
                        customEnvironmentVariables.removeAll { $0.id == variable.id }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("删除环境变量")
                }
            }

            SettingDivider()

            HStack {
                Text("上面的默认变量都允许修改；同名变量请直接修改默认项")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    customEnvironmentVariables.append(EnvironmentVariable())
                } label: {
                    Label("添加变量", systemImage: "plus")
                }
            }
        }
    }

    private var launchCard: some View {
        SettingsCard(
            title: "启动行为",
            subtitle: "控制应用启动后的默认动作",
            systemImage: "power"
        ) {
            Toggle("打开 Pi Web Launcher 时自动启动服务", isOn: $autoStart)
                .toggleStyle(SwitchToggleStyle())

            SettingDivider()

            Toggle("服务启动后自动打开网页", isOn: $openBrowserOnStart)
                .toggleStyle(SwitchToggleStyle())
        }
    }

    private var statusCard: some View {
        SettingsCard(
            title: "当前状态",
            subtitle: controller.isRunning ? "Pi Web 服务正在运行" : "Pi Web 服务当前未运行",
            systemImage: controller.isRunning ? "checkmark.circle.fill" : "info.circle"
        ) {
            HStack(spacing: 10) {
                Circle()
                    .fill(controller.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(controller.statusText)
                    .fontWeight(.medium)
                Spacer()

                if controller.isRunning, !controller.runtimeURL.isEmpty {
                    Text(controller.runtimeURL)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if let error = controller.lastError, !error.isEmpty {
                SettingDivider()
                Label {
                    Text(error)
                        .font(.system(.caption, design: .monospaced))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundColor(.red)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("设置自动保存。运行参数修改后需要重启服务才能生效。")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if controller.isRunning {
                Button("停止") {
                    controller.stop()
                }
            }

            Button(controller.isRunning ? "应用并重启" : "应用并启动") {
                controller.restart()
            }
            .buttonStyle(ProminentButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func detectEnvironmentPath() {
        let detected = controller.detectDefaultPath()
        environmentPath = detected
        detectionMessage = "已检测并填入 PATH"
    }

    private func detectNodeBinPath() {
        if let detected = controller.detectNodeBinPath(environmentPath: environmentPath) {
            nodeBinPath = abbreviateHome(detected)
            detectionMessage = "已检测到 Node：\(nodeBinPath)"
        } else {
            detectionMessage = "当前 PATH 中未检测到 Node.js"
        }
    }

    private func detectPiWebPath() {
        if let detected = controller.detectPiWebPath(nodeBinPath: nodeBinPath, environmentPath: environmentPath) {
            piWebPath = abbreviateHome(detected)
            detectionMessage = "已检测到 Pi Web：\(piWebPath)"
        } else {
            detectionMessage = "当前 PATH 中未检测到 pi-web"
        }
    }

    private func bringToForegroundWhenOpen() {
        if !environmentPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Already has path
        } else {
            environmentPath = controller.detectDefaultPath()
        }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let settingsWindow = NSApp.windows.last { $0.canBecomeKey }
            settingsWindow?.makeKeyAndOrderFront(nil)
            settingsWindow?.orderFrontRegardless()
        }
    }

    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.directoryURL = URL(fileURLWithPath: expandTilde(workingDirectory))

        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = abbreviateHome(url.path)
        }
    }

    private func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        guard path == home || path.hasPrefix(home + "/") else { return path }
        if path == home { return "~" }
        return "~" + path.dropFirst(home.count)
    }
}

private struct ProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1.0))
            )
            .foregroundColor(.white)
            .font(.callout.weight(.medium))
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    private let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

private struct SettingRow<Content: View>: View {
    let title: String
    let subtitle: String
    private let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content
        }
    }
}

private struct EnvironmentRow<Content: View>: View {
    let name: String
    let subtitle: String
    private let content: Content

    init(name: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.name = name
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            content
        }
    }
}

private struct SettingDivider: View {
    var body: some View {
        Divider()
            .opacity(0.65)
    }
}

