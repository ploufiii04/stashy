//
//  TrustAllSessionDelegate.swift
//  stashy
//

import Foundation

// MARK: - Host matching & local-network policy (shared by GraphQL, images, drafts)

enum SSLTrustHostMatching {

    /// Strips brackets for IPv6 — host string compare only.
    static func normalizeHost(_ raw: String) -> String {
        var h = raw.lowercased()
        if h.hasPrefix("["), h.hasSuffix("]"), h.count >= 3 {
            h = String(h.dropFirst().dropLast())
        }
        return h
    }

    static func hostsMatch(_ challengeHost: String, configuredHost: String) -> Bool {
        normalizeHost(challengeHost) == normalizeHost(configuredHost)
    }

    static func isLocalOrPrivateNetworkHost(_ host: String) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }

        let privateRanges = [
            "10.", "172.16.", "172.17.", "172.18.", "172.19.", "172.20.", "172.21.", "172.22.", "172.23.", "172.24.", "172.25.",
            "172.26.", "172.27.", "172.28.", "172.29.", "172.30.", "172.31.", "192.168."
        ]
        if privateRanges.contains(where: { host.hasPrefix($0) }) { return true }

        return false
    }

    static func isLegacySandboxHost(_ host: String) -> Bool {
        host.contains("gole.tz")
    }
}

// MARK: - Active server: optional “trust all certificates” for this host only

enum ActiveServerSSLTrust {
    private static let lock = NSLock()
    private static var trustAllForActiveServer: Bool = false
    private static var activeCanonicalHost: String?

    static func update(from config: ServerConfig?) {
        lock.lock()
        defer { lock.unlock() }
        trustAllForActiveServer = config?.trustAllCertificates ?? false
        if let c = config, let u = URL(string: c.baseURL), let h = u.host {
            activeCanonicalHost = SSLTrustHostMatching.normalizeHost(h)
        } else {
            activeCanonicalHost = nil
        }
    }

    static func shouldTrustConfiguredServer(challengeHost: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard trustAllForActiveServer, let pinned = activeCanonicalHost else { return false }
        return SSLTrustHostMatching.normalizeHost(challengeHost) == pinned
    }
}

// MARK: - URLSession delegate (GraphQL, image loader, login)

final class TrustAllSessionDelegate: NSObject, URLSessionDelegate {
    static let shared = TrustAllSessionDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        #if DEBUG
        print("📱 SSL Challenge for host: \(host)")
        #endif

        let accept =
            SSLTrustHostMatching.isLocalOrPrivateNetworkHost(host)
            || ActiveServerSSLTrust.shouldTrustConfiguredServer(challengeHost: host)
            || SSLTrustHostMatching.isLegacySandboxHost(host)

        if accept, let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        completionHandler(.performDefaultHandling, nil)
    }
}
