import Foundation
#if canImport(Network) && canImport(Security)
import Network
import Security

public enum AtvLinkError: Error {
    case address
    case identity
    case refused
    case mismatch
    case closed
}

public enum AtvLink {
    public static let commandPort: UInt16 = 6466
    public static let pairPort: UInt16 = 6467

    public static func pair(
        host: String,
        code: String,
        identity: AtvIdentity,
        queue: DispatchQueue,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard let port = NWEndpoint.Port(rawValue: pairPort) else {
            completion(.failure(AtvLinkError.address))
            return
        }
        let captured = PeerCapture()
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: tlsParameters(identity: identity, pin: nil, capture: captured))
        let machine = PairMachine(identity: identity, code: code, peer: captured)
        connection.stateUpdateHandler = { state in
            if case .failed = state {
                completion(.failure(AtvLinkError.refused))
                connection.cancel()
            }
        }
        connection.start(queue: queue)
        machine.run(connection, completion: completion)
    }

    static func tlsParameters(identity: AtvIdentity, pin: Data?, capture: PeerCapture) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        if let secIdentity = sec_identity_create(identity.certificate, identity.key) {
            sec_protocol_options_set_local_identity(security, secIdentity)
        }
        sec_protocol_options_set_verify_block(security, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            let chain = (SecTrustCopyCertificateChain(secTrust) as? [SecCertificate]) ?? []
            let leaf = chain.first.map { SecCertificateCopyData($0) as Data }
            capture.leaf = leaf
            if let pin {
                complete(leaf == pin)
            } else {
                complete(leaf != nil)
            }
        }, DispatchQueue(label: "app.pohstep.remote.tls"))
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }
}

final class PeerCapture: @unchecked Sendable {
    var leaf: Data?
}

final class PairMachine {
    private let identity: AtvIdentity
    private let code: String
    private let peer: PeerCapture
    private var buffer = Data()
    private var stage = 0

    init(identity: AtvIdentity, code: String, peer: PeerCapture) {
        self.identity = identity
        self.code = code
        self.peer = peer
    }

    func run(_ connection: NWConnection, completion: @escaping (Result<Data, Error>) -> Void) {
        send(AtvPairingMessage.framedRequest(), on: connection)
        receive(connection, completion: completion)
    }

    private func receive(_ connection: NWConnection, completion: @escaping (Result<Data, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self else { return }
            if error != nil {
                completion(.failure(AtvLinkError.closed))
                connection.cancel()
                return
            }
            if let data { self.buffer.append(data) }
            self.pump(connection, completion: completion)
        }
    }

    private func pump(_ connection: NWConnection, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let (payload, consumed) = framed(buffer) else {
            receive(connection, completion: completion)
            return
        }
        buffer.removeFirst(consumed)
        stage += 1
        if stage < 3, let reply = AtvPairingMessage.reply(to: payload) {
            send(Proto.frame(reply), on: connection)
            receive(connection, completion: completion)
            return
        }
        guard let leaf = peer.leaf, let pkcs1 = RsaPublic.pkcs1(in: leaf), let server = RsaPublic.numbers(pkcs1: pkcs1) else {
            completion(.failure(AtvLinkError.mismatch))
            connection.cancel()
            return
        }
        let clientExponent = AtvPairingHash.exponentBytes(identity.exponent)
        let serverExponent = AtvPairingHash.exponentBytes(server.exponent)
        guard AtvPairingHash.accepts(
            code: code,
            clientModulus: identity.modulus,
            clientExponent: clientExponent,
            serverModulus: server.modulus,
            serverExponent: serverExponent
        ) else {
            completion(.failure(AtvLinkError.mismatch))
            connection.cancel()
            return
        }
        let nonce = String(code.dropFirst(2))
        let digest = AtvPairingHash.digest(
            clientModulus: identity.modulus,
            clientExponent: clientExponent,
            serverModulus: server.modulus,
            serverExponent: serverExponent,
            nonceHex: nonce
        )
        send(Proto.frame(AtvPairingMessage.secret(digest)), on: connection)
        completion(.success(leaf))
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func framed(_ data: Data) -> (Data, Int)? {
        let bytes = [UInt8](data)
        var length: UInt64 = 0
        var shift: UInt64 = 0
        var index = 0
        while index < bytes.count {
            let piece = bytes[index]
            index += 1
            length |= UInt64(piece & 0x7f) << shift
            if piece & 0x80 == 0 { break }
            shift += 7
        }
        let end = index + Int(length)
        guard index > 0, end <= bytes.count else { return nil }
        return (Data(bytes[index..<end]), end)
    }

}

public extension AtvLink {
    static func openCommands(host: String, identity: AtvIdentity, pin: Data, queue: DispatchQueue, completion: @escaping (Result<NWConnection, Error>) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: commandPort) else {
            completion(.failure(AtvLinkError.address))
            return
        }
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: port,
            using: tlsParameters(identity: identity, pin: pin, capture: PeerCapture())
        )
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                completion(.success(connection))
            case .failed, .cancelled:
                completion(.failure(AtvLinkError.refused))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
}

public enum AdbLink {
    public static func connect(host: String, port: UInt16, queue: DispatchQueue, completion: @escaping (Result<NWConnection, Error>) -> Void) {
        guard let endpoint = NWEndpoint.Port(rawValue: port) else {
            completion(.failure(AtvLinkError.address))
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpoint, using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                completion(.success(connection))
            case .failed, .cancelled:
                completion(.failure(AtvLinkError.refused))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }
}
#endif
