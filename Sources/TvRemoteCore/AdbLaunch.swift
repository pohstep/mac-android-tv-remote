import Foundation

/// Every adb launch uses this environment. A sandboxed Mac app has no TMPDIR,
/// and adb then tries `/tmp`, which the sandbox denies. The server socket is
/// passed explicitly so the client and the bundled server agree.
public enum AdbLaunch {
    public static let defaultServerSocket = "tcp:localhost:5037"

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
