import Foundation

#if os(macOS)
import Network

/// Browses the service types in `DiscoveryService.types` with Network.framework.
/// Resolution opens a short TCP connection and cancels it once the address is known.
/// Untested against a television; the parser in `DiscoveryParse` is what the tests cover.
public final class BonjourListing: ServiceListing {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 2) {
        self.timeout = timeout
    }

    public func list() -> [ServiceEndpoint] {
        let queue = DispatchQueue(label: "zapbar.bonjour")
        let lock = NSLock()
        var found: [ServiceEndpoint] = []
        var browsers: [NWBrowser] = []
        var connections: [NWConnection] = []

        for type in DiscoveryService.types {
            let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
            browsers.append(browser)
            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    guard case .service(let name, let serviceType, _, _) = result.endpoint else { continue }
                    let model = BonjourListing.modelName(result.metadata)
                    let connection = NWConnection(to: result.endpoint, using: .tcp)
                    lock.lock()
                    connections.append(connection)
                    lock.unlock()
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            if let endpoint = BonjourListing.endpoint(
                                name: name,
                                serviceType: serviceType,
                                remote: connection.currentPath?.remoteEndpoint,
                                model: model
                            ) {
                                lock.lock()
                                found.append(endpoint)
                                lock.unlock()
                            }
                            connection.cancel()
                        case .failed, .cancelled:
                            connection.cancel()
                        default:
                            break
                        }
                    }
                    connection.start(queue: queue)
                }
            }
            browser.start(queue: queue)
        }

        Thread.sleep(forTimeInterval: timeout)
        for browser in browsers { browser.cancel() }
        lock.lock()
        let pending = connections
        lock.unlock()
        for connection in pending { connection.cancel() }
        Thread.sleep(forTimeInterval: 0.2)
        lock.lock()
        let snapshot = found
        lock.unlock()
        return snapshot
    }

    static func modelName(_ metadata: NWBrowser.Result.Metadata) -> String {
        switch metadata {
        case .bonjour(let record):
            return record["md"] ?? ""
        case .none:
            return ""
        @unknown default:
            return ""
        }
    }

    static func endpoint(name: String, serviceType: String, remote: NWEndpoint?, model: String) -> ServiceEndpoint? {
        guard case .hostPort(let host, let port)? = remote else { return nil }
        let hostText: String
        switch host {
        case .ipv4(let address):
            hostText = "\(address)"
        case .ipv6(let address):
            hostText = "\(address)"
        case .name(let value, _):
            hostText = value
        @unknown default:
            return nil
        }
        let number = Int(port.rawValue)
        guard !hostText.isEmpty, (1...65535).contains(number) else { return nil }
        return ServiceEndpoint(name: name, host: hostText, port: number, serviceType: DiscoveryService.normalize(serviceType), model: model)
    }
}
#endif
