import Foundation

/// Every adb launch uses this environment. A sandboxed Mac app has no TMPDIR,
/// and adb then tries `/tmp`, which the sandbox denies. The server socket is
/// passed explicitly so the client and the bundled server agree.
public enum AdbLaunch {
    /// Shared port used by a normal adb install. A sandboxed app must not use it.
    public static let publicServerSocket = "tcp:localhost:5037"
    /// Private loopback port so a sandboxed Zapbar never attaches to someone else's server.
    public static let privateServerSocket = "tcp:127.0.0.1:5038"
    /// Quit waits at most this long for `adb kill-server`, then gives up.
    public static let quitWait: TimeInterval = 2

    public static func serverSocket(sandboxed: Bool) -> String {
        sandboxed ? privateServerSocket : publicServerSocket
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
