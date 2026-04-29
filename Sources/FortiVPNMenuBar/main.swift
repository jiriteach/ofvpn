import AppKit
import Foundation
import Darwin

enum VPNState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case error(String)

    var label: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .disconnecting:
            return "Disconnecting..."
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var menuBarTitle: String {
        switch self {
        case .disconnected:
            return "🔂 - OFVPN"
        case .connecting:
            return "🔂 - Connecting ..."
        case .connected:
            return "✳️ - OFVPN"
        case .disconnecting:
            return "🔂 - Disconnecting ..."
        case .error:
            return "🔂 - OFVPN - Error"
        }
    }
}

enum VPNProcessStatus {
    case stopped
    case starting
    case connected
}

private struct GitHubRelease: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}

final class FortiVPNApp: NSObject, NSApplicationDelegate {
    private let defaultConfigPath = "\(NSHomeDirectory())/Documents/.fortivpn-config"
    private let configPathDefaultsKey = "configPath"
    private let workDirectory: String
    private let stagedConfigPath: String
    private let logPath: String
    private let pidPath: String
    private let disconnectFlagPath: String
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Status: Disconnected", action: nil, keyEquivalent: "")
    private let externalIPMenuItem = NSMenuItem(title: "External IP: Checking...", action: nil, keyEquivalent: "")
    private let internalIPMenuItem = NSMenuItem(title: "Internal IPs: Checking...", action: nil, keyEquivalent: "")
    private let configMenuItem = NSMenuItem(title: "Configuration: .fortivpn-config", action: nil, keyEquivalent: "")
    private let connectMenuItem = NSMenuItem(title: "Connect", action: #selector(connect), keyEquivalent: "c")
    private let disconnectMenuItem = NSMenuItem(title: "Disconnect", action: #selector(disconnect), keyEquivalent: "d")

    private var state: VPNState = .disconnected
    private var vpnPID: Int32?
    private var refreshTimer: Timer?
    private var splashWindow: NSWindow?

    override init() {
        let tempDirectory = (NSTemporaryDirectory() as NSString).appendingPathComponent("fortivpn-menubar")
        workDirectory = tempDirectory
        stagedConfigPath = (tempDirectory as NSString).appendingPathComponent(".fortivpn-config")
        logPath = (tempDirectory as NSString).appendingPathComponent("openfortivpn-current.log")
        pidPath = (tempDirectory as NSString).appendingPathComponent("openfortivpn.pid")
        disconnectFlagPath = (tempDirectory as NSString).appendingPathComponent("disconnect.request")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        updateState(.disconnected)
        showSplashScreen()
        ensureInitialConfigSelected()
        refreshStatus()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func configureMenu() {
        menu.autoenablesItems = false

        if let button = statusItem.button {
            button.image = nil
            button.title = state.menuBarTitle
        }

        statusMenuItem.isEnabled = false
        externalIPMenuItem.isEnabled = false
        internalIPMenuItem.isEnabled = false
        configMenuItem.isEnabled = false
        connectMenuItem.target = self
        disconnectMenuItem.target = self

        menu.addItem(statusMenuItem)
        menu.addItem(externalIPMenuItem)
        menu.addItem(internalIPMenuItem)
        menu.addItem(configMenuItem)
        menu.addItem(.separator())
        menu.addItem(connectMenuItem)
        menu.addItem(disconnectMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Check Logs", action: #selector(openLog), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Exit", action: #selector(exitApp), keyEquivalent: "q"))

        menu.items.forEach { item in
            if item.action == #selector(openLog) || item.action == #selector(showAbout) || item.action == #selector(exitApp) {
                item.target = self
            }
        }

        updateConfigMenuItem()
        statusItem.menu = menu
    }

    private func showSplashScreen() {
        showSplashWindow(mode: .launch)
    }

    private enum SplashMode {
        case launch
        case about
    }

    private func showSplashWindow(mode: SplashMode) {
        NSApp.setActivationPolicy(.regular)

        let isAbout = mode == .about
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let height: CGFloat = isAbout ? 250 : 190
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.center()

        let container = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 360, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 18
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor

        let titleLabel = NSTextField(labelWithString: "🔂 - OFVPN")
        titleLabel.font = .systemFont(ofSize: 32, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.font = .systemFont(ofSize: 15, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.allowsEditingTextAttributes = true
        versionLabel.isSelectable = true
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        let creatorLabel = NSButton(title: "Created by - Jithen Singh", target: self, action: #selector(openCreatorLink))
        creatorLabel.isBordered = false
        creatorLabel.font = .systemFont(ofSize: 14, weight: .regular)
        creatorLabel.contentTintColor = .linkColor
        creatorLabel.translatesAutoresizingMaskIntoConstraints = false
        creatorLabel.isHidden = !isAbout

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeSplashWindow))
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isHidden = !isAbout

        container.addSubview(titleLabel)
        container.addSubview(versionLabel)
        container.addSubview(creatorLabel)
        container.addSubview(closeButton)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: isAbout ? -44 : -14),
            versionLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            versionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            creatorLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            creatorLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 28),
            closeButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            closeButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -22),
            closeButton.widthAnchor.constraint(equalToConstant: 86)
        ])

        window.contentView = container
        splashWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if isAbout {
            versionLabel.stringValue = "Version \(version) - Checking..."
            checkLatestRelease(currentVersion: version, versionLabel: versionLabel)
        }

        guard mode == .launch else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.splashWindow?.orderOut(nil)
            self?.splashWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc private func connect() {
        guard state != .connected && state != .connecting else { return }

        updateState(.connecting)
        do {
            try stageConfigFile()
        } catch {
            if chooseConfigFile() {
                do {
                    try stageConfigFile()
                } catch {
                    updateState(.error("Could not stage config: \(error.localizedDescription)"))
                    return
                }
            } else {
                updateState(.error("Could not stage config: \(error.localizedDescription)"))
                return
            }
        }

        runPrivilegedAppleScript(connectScript()) { [weak self] output, error in
            DispatchQueue.main.async(execute: {
                if let error {
                    self?.updateState(.error(error))
                    return
                }

                self?.vpnPID = Int32(output.trimmingCharacters(in: .whitespacesAndNewlines))
                self?.refreshStatus(forceIPRefresh: true)
            })
        }
    }

    @objc private func disconnect() {
        guard state != .disconnected && state != .disconnecting else { return }

        updateState(.disconnecting)
        do {
            try requestDisconnect()
            finishDisconnect()
        } catch {
            updateState(.error("Could not request disconnect: \(error.localizedDescription)"))
        }
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    @objc private func showAbout() {
        showSplashWindow(mode: .about)
    }

    @objc private func closeSplashWindow() {
        splashWindow?.orderOut(nil)
        splashWindow = nil
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func openCreatorLink() {
        if let url = URL(string: "https://github.com/jiriteach/") {
            NSWorkspace.shared.open(url)
        }
    }

    private func checkLatestRelease(currentVersion: String, versionLabel: NSTextField) {
        guard let url = URL(string: "https://api.github.com/repos/jiriteach/ofvpn/releases/latest") else {
            versionLabel.stringValue = "Version \(currentVersion) - Unable to Check"
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OFVPN", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self, weak versionLabel] data, response, error in
            let message: String
            let updateAvailable: Bool

            if error != nil {
                message = "Version \(currentVersion) - Unable to Check"
                updateAvailable = false
            } else if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                message = "Version \(currentVersion) - Unable to Check"
                updateAvailable = false
            } else if let data, let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) {
                let latestVersion = release.tagName
                switch Self.compareVersions(currentVersion, latestVersion) {
                case .orderedAscending:
                    message = "Version \(currentVersion) - Update Available"
                    updateAvailable = true
                case .orderedSame:
                    message = "Version \(currentVersion) - Latest"
                    updateAvailable = false
                case .orderedDescending:
                    message = "Version \(currentVersion) - Latest"
                    updateAvailable = false
                }
            } else {
                message = "Version \(currentVersion) - Unable to Check"
                updateAvailable = false
            }

            DispatchQueue.main.async(execute: {
                guard self?.splashWindow != nil, let versionLabel else { return }
                versionLabel.attributedStringValue = Self.versionStatusText(message, linkUpdateText: updateAvailable)
            })
        }.resume()
    }

    private static func versionStatusText(_ message: String, linkUpdateText: Bool) -> NSAttributedString {
        let attributedText = NSMutableAttributedString(
            string: message,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        guard linkUpdateText, let url = URL(string: "https://github.com/jiriteach/ofvpn/releases") else {
            return attributedText
        }

        let updateRange = (message as NSString).range(of: "Update Available")
        if updateRange.location != NSNotFound {
            attributedText.addAttributes(
                [
                    .link: url,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: updateRange
            )
        }

        return attributedText
    }

    @objc private func exitApp() {
        checkVPNStatus { [weak self] vpnStatus in
            DispatchQueue.main.async(execute: {
                guard let self else { return }
                guard vpnStatus == .connected || self.state == .connected else {
                    NSApp.terminate(nil)
                    return
                }

                let alert = NSAlert()
                alert.messageText = "✳️ - OFVPN - Connected. Disconnect & Exit?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Yes")
                alert.addButton(withTitle: "No")

                guard alert.runModal() == .alertFirstButtonReturn else {
                    return
                }

                self.updateState(.disconnecting)
                do {
                    try self.requestDisconnect()
                    self.finishDisconnect {
                        NSApp.terminate(nil)
                    }
                } catch {
                    self.updateState(.error("Could not request disconnect: \(error.localizedDescription)"))
                }
            })
        }
    }

    private func refreshStatus(forceIPRefresh: Bool = false) {
        checkVPNStatus { [weak self] vpnStatus in
            DispatchQueue.main.async(execute: {
                guard let self else { return }
                if self.state == .disconnecting {
                    return
                }

                if vpnStatus == .connected {
                    if self.state != .connected {
                        self.updateState(.connected)
                    }
                } else if vpnStatus == .starting {
                    if self.state != .connecting && self.state != .disconnecting {
                        self.updateState(.connecting)
                    }
                } else if self.state == .connected || self.state == .connecting || self.state == .disconnecting {
                    self.vpnPID = nil
                    self.updateState(.disconnected)
                }

                if forceIPRefresh || self.state == .connected || self.externalIPMenuItem.title.contains("Checking") {
                    self.refreshIPAddresses()
                }
            })
        }
    }

    private func refreshIPAddresses() {
        refreshInternalIPAddresses()
        refreshPublicIP()
    }

    private func refreshPublicIP() {
        guard let url = URL(string: "https://api.ipify.org") else { return }

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let ip = data.flatMap { String(data: $0, encoding: .utf8) }?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async(execute: {
                self?.externalIPMenuItem.title = "External IP: \(ip?.isEmpty == false ? ip! : "Unavailable")"
            })
        }
        task.resume()
    }

    private func refreshInternalIPAddresses() {
        let addresses = Self.internalIPv4Addresses()
        internalIPMenuItem.title = "Internal IPs: \(addresses.isEmpty ? "Unavailable" : addresses.joined(separator: ", "))"
    }

    private func finishDisconnect(completion: (() -> Void)? = nil) {
        vpnPID = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: {
            self.checkVPNStatus { [weak self] vpnStatus in
                DispatchQueue.main.async(execute: {
                    guard let self else { return }
                    if vpnStatus != .stopped {
                        self.updateState(.error("Disconnect did not stop VPN"))
                        return
                    }

                    self.updateState(.disconnected)
                    self.refreshIPAddresses()
                    completion?()
                })
            }
        })
    }

    private func checkVPNStatus(completion: @escaping (VPNProcessStatus) -> Void) {
        DispatchQueue.global(qos: .utility).async(execute: {
            if Self.shell(["/usr/bin/pgrep", "-x", "pppd"]).exitCode == 0 {
                completion(.connected)
                return
            }

            if Self.shell(["/usr/bin/pgrep", "-x", "openfortivpn"]).exitCode == 0 {
                completion(.starting)
                return
            }

            completion(.stopped)
        })
    }

    private func updateState(_ newState: VPNState) {
        state = newState
        statusMenuItem.title = "Status: \(newState.label)"
        connectMenuItem.isEnabled = newState == .disconnected || {
            if case .error = newState { return true }
            return false
        }()
        disconnectMenuItem.isEnabled = newState == .connected

        if let button = statusItem.button {
            button.image = nil
            button.title = newState.menuBarTitle
        }
    }

    private func connectScript() -> String {
        let quotedConfig = shellQuote(stagedConfigPath)
        let quotedLog = shellQuote(logPath)
        let quotedPID = shellQuote(pidPath)
        let quotedFlag = shellQuote(disconnectFlagPath)
        let quotedPattern = shellQuote("[o]penfortivpn.*-c \(stagedConfigPath)")
        let quotedPPPPattern = shellQuote("/usr/sbin/[p]ppd .*ipcp-accept-local.*nodetach")
        let launchHeader = "OFVPN launching: openfortivpn -c \(stagedConfigPath)"
        let stopCommand = """
        printf '\\nOFVPN disconnect requested\\n' >> \(quotedLog); \
        if [ -f \(quotedPID) ]; then pid=$(/bin/cat \(quotedPID) 2>/dev/null); case "$pid" in ''|*[!0-9]*) ;; *) /bin/kill -TERM "$pid" 2>/dev/null || true ;; esac; fi; \
        /usr/bin/pkill -TERM -f \(quotedPattern) 2>/dev/null || true; \
        /usr/bin/pkill -TERM -f \(quotedPPPPattern) 2>/dev/null || true; \
        /bin/sleep 1; \
        if [ -f \(quotedPID) ]; then pid=$(/bin/cat \(quotedPID) 2>/dev/null); case "$pid" in ''|*[!0-9]*) ;; *) /bin/kill -KILL "$pid" 2>/dev/null || true ;; esac; fi; \
        /usr/bin/pkill -KILL -f \(quotedPattern) 2>/dev/null || true; \
        /usr/bin/pkill -KILL -f \(quotedPPPPattern) 2>/dev/null || true; \
        /bin/rm -f \(quotedPID) \(quotedFlag); \
        printf '\\nOFVPN disconnected\\n' >> \(quotedLog); \
        if /usr/bin/pgrep -x openfortivpn >/dev/null 2>&1; then printf 'openfortivpn process: still running\\n' >> \(quotedLog); else printf 'No openfortivpn process exists.\\n' >> \(quotedLog); fi; \
        if /usr/bin/pgrep -x pppd >/dev/null 2>&1; then printf 'pppd process: still running\\n' >> \(quotedLog); else printf 'No pppd process exists.\\n' >> \(quotedLog); fi
        """
        let monitorCommand = """
        while true; do \
        if [ -f \(quotedFlag) ]; then \(stopCommand); exit 0; fi; \
        if ! /usr/bin/pgrep -x openfortivpn >/dev/null 2>&1 && ! /usr/bin/pgrep -x pppd >/dev/null 2>&1; then /bin/rm -f \(quotedPID) \(quotedFlag); exit 0; fi; \
        /bin/sleep 1; \
        done
        """
        let launchCommand = "trap '' HUP; exec </dev/null; /bin/rm -f \(quotedFlag); printf '%s\\n' \(shellQuote(launchHeader)) > \(quotedLog); openfortivpn -c \(quotedConfig) >> \(quotedLog) 2>&1 & pid=$!; printf '%s' \"$pid\" > \(quotedPID); /bin/sh -c \(shellQuote(monitorCommand)) >/dev/null 2>&1 & printf '%s' \"$pid\""
        let shellCommand = "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; /bin/mkdir -p \(shellQuote(workDirectory)); /bin/chmod 700 \(shellQuote(workDirectory)); /bin/sh -c \(shellQuote(launchCommand))"

        return "do shell script \(appleScriptQuote(shellCommand)) with administrator privileges with prompt \"OFVPN needs administrator access to start the VPN.\""
    }

    private func stageConfigFile() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: workDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workDirectory)

        let sourceURL = URL(fileURLWithPath: selectedConfigPath)
        let stagedURL = URL(fileURLWithPath: stagedConfigPath)
        let configData = try Data(contentsOf: sourceURL)
        try configData.write(to: stagedURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stagedConfigPath)
    }

    private func requestDisconnect() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: workDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workDirectory)
        try "disconnect\n".write(toFile: disconnectFlagPath, atomically: true, encoding: .utf8)
    }

    private var selectedConfigPath: String {
        UserDefaults.standard.string(forKey: configPathDefaultsKey) ?? defaultConfigPath
    }

    private func updateConfigMenuItem() {
        let filename = URL(fileURLWithPath: selectedConfigPath).lastPathComponent
        configMenuItem.title = "Configuration: \(filename.isEmpty ? selectedConfigPath : filename)"
    }

    private func ensureInitialConfigSelected() {
        guard UserDefaults.standard.string(forKey: configPathDefaultsKey) == nil else { return }

        if !chooseConfigFile() {
            updateState(.error("Configuration required"))
        }
    }

    private func chooseConfigFile() -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Select FortiVPN Config"
        panel.message = "Choose the openfortivpn config file to use."
        panel.prompt = "Use Config"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: (selectedConfigPath as NSString).deletingLastPathComponent)
        panel.nameFieldStringValue = URL(fileURLWithPath: selectedConfigPath).lastPathComponent

        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }

        UserDefaults.standard.set(url.path, forKey: configPathDefaultsKey)
        updateConfigMenuItem()
        return true
    }

    private func runPrivilegedAppleScript(_ source: String, completion: @escaping (_ output: String, _ error: String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async(execute: {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()

                let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    completion(output, nil)
                } else {
                    let message = error.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(output, message.isEmpty ? "Command failed" : message)
                }
            } catch {
                completion("", error.localizedDescription)
            }
        })
    }

    private func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            try? process.run()
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptQuote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func shell(_ arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (1, error.localizedDescription)
        }
    }

    private static func compareVersions(_ currentVersion: String, _ latestVersion: String) -> ComparisonResult {
        let currentComponents = versionComponents(from: currentVersion)
        let latestComponents = versionComponents(from: latestVersion)
        let componentCount = max(currentComponents.count, latestComponents.count)

        for index in 0..<componentCount {
            let current = index < currentComponents.count ? currentComponents[index] : 0
            let latest = index < latestComponents.count ? latestComponents[index] : 0

            if current < latest {
                return .orderedAscending
            }

            if current > latest {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func versionComponents(from version: String) -> [Int] {
        version
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }

    private static func internalIPv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddress = ifaddr else {
            return addresses
        }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: firstAddress, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            guard isUp, !isLoopback, let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if result == 0 {
                let ip = String(cString: hostname)
                if !addresses.contains(ip) {
                    addresses.append(ip)
                }
            }
        }

        return addresses
    }
}

let app = NSApplication.shared
let delegate = FortiVPNApp()
app.delegate = delegate
app.run()
