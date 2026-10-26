import Foundation

/// Every adb launch uses this environment. A sandboxed Mac app has no TMPDIR,
/// and adb then tries `/tmp`, which the sandbox denies. The server socket is
/// passed explicitly so the client and the bundled server agree.
public enum AdbLaunch {
    /// Shared port used by a normal adb install. A sandboxed app must not use it.
    public static let publicServerSocket = "tcp:localhost:5037"
    /// Private loopback port so a sandboxed Zapbar never attaches to someone else's server.
    /// `localhost` plus `-P` lets the helper start that server. A numeric address alone
    /// makes adb treat the server as remote and refuse to start it.
    public static let privateServerSocket = "tcp:localhost:5038"
    /// Quit waits at most this long for `adb kill-server`, then gives up.
    public static let quitWait: TimeInterval = 2

    public static func serverSocket(sandboxed: Bool) -> String {
        sandboxed ? privateServerSocket : publicServerSocket
    }

    /// Numeric port at the end of `tcp:host:port`. Nil when the socket has none.
    public static func serverPort(socket: String) -> String? {
        let trimmed = socket.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = trimmed.lastIndex(of: ":") else { return nil }
        let port = String(trimmed[trimmed.index(after: colon)...])
        guard !port.isEmpty, port.allSatisfy({ $0.isNumber }) else { return nil }
        return port
    }

    #if SANDBOX_BUILD
    public static let defaultServerSocket = privateServerSocket
    #else
    public static let defaultServerSocket = publicServerSocket
    #endif

    public static func environment(temporaryDirectory: String, serverSocket: String = defaultServerSocket) -> [String: String] {
        var values: [String: String] = [:]
        let temp = temporaryDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !temp.isEmpty {
            values["TMPDIR"] = temp
        }
        let socket = serverSocket.trimmingCharacters(in: .whitespacesAndNewlines)
        if !socket.isEmpty {
            values["ADB_SERVER_SOCKET"] = socket
        }
        return values
    }
}
