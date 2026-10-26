import Foundation

public struct AdbClient {
    public var runner: any CommandRunning
    public var adbPath: String
    public var timeout: TimeInterval
    public var temporaryDirectory: String
    public var serverSocket: String

    public init(
        runner: any CommandRunning,
        adbPath: String,
        timeout: TimeInterval = 12,
        temporaryDirectory: String? = nil,
        serverSocket: String = AdbLaunch.defaultServerSocket
    ) {
        self.runner = runner
        self.adbPath = adbPath
        self.timeout = timeout
        self.temporaryDirectory = temporaryDirectory ?? FileManager.default.temporaryDirectory.path
        self.serverSocket = serverSocket
    }

    public func pair(host: String, port: Int, code: String) throws -> Bool {
        let result = try run(AdbCommands.pair(host: host, port: port, code: code))
        return AdbOutput.parsePair(result.combined)
    }

    public func connect(host: String, port: Int) throws -> ConnectOutcome {
        let result = try run(AdbCommands.connect(host: host, port: port))
        return AdbOutput.parseConnect(result.combined)
    }

    public func listDevices() throws -> CommandResult {
        try run(AdbCommands.devices())
    }

    public func shell(_ arguments: [String], serial: String) throws -> String {
        let result = try run(["-s", serial, "shell"] + arguments)
        if result.status != 0 {
            throw RemoteError.commandFailed(result.combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.combined
    }

    public func keyEvent(_ key: AndroidKey, serial: String) throws {
        let result = try run(AdbCommands.keyEvent(serial: serial, key: key))
        if result.status != 0 {
            throw RemoteError.commandFailed(result.combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func inputText(_ text: String, serial: String) throws {
        let payloads = AdbText.shellPayloads(text)
        if payloads.isEmpty { return }
        for payload in payloads {
            let result = try run(AdbCommands.text(serial: serial, payload: payload))
            if result.status != 0 {
                throw RemoteError.commandFailed(result.combined.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    /// Launches by package name. Tries the Android TV leanback category first,
    /// then monkey, which is what sideloaded apps on a Bravia usually need.
    public func launchApp(packageName: String, serial: String) throws {
        guard PackageName.isValid(packageName) else {
            throw RemoteError.commandFailed("\(packageName) isn't a package name.")
        }

        let attempts: [[String]] = [
            AdbCommands.launchLeanback(serial: serial, packageName: packageName),
            AdbCommands.launchMonkey(
                serial: serial,
                packageName: packageName,
                category: "android.intent.category.LEANBACK_LAUNCHER"
            ),
            AdbCommands.launchMonkey(
                serial: serial,
                packageName: packageName,
                category: "android.intent.category.LAUNCHER"
            )
        ]

        var lastDetail = ""
        for arguments in attempts {
            let result = try run(arguments)
            if !AdbOutput.outputIndicatesFailure(result.combined, status: result.status) {
                return
            }
            lastDetail = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if lastDetail.isEmpty {
            lastDetail = "No launchable activity for \(packageName)."
        }
        throw RemoteError.commandFailed(lastDetail)
    }

    private func run(_ arguments: [String]) throws -> CommandResult {
        try runner.run(
            adbPath,
            arguments: arguments,
            timeout: timeout,
            environment: AdbLaunch.environment(temporaryDirectory: temporaryDirectory, serverSocket: serverSocket)
        )
    }
}
