import CellarDomain
import Foundation

/// The internet connections a running game holds open, read from macOS rather than from Wine.
///
/// A probe passing proves the bottle *could* reach a server. It said nothing about Planet Coaster
/// 2's Workshop, which talks through its own libcurl over Schannel and failed while every probe
/// passed (#23). The only honest answer to "does the game reach its servers" is what the game's own
/// process has connected to: Wine's sockets are ordinary macOS sockets owned by the process
/// running the Windows exe, so `lsof` lists them like any Mac app's.
public enum GameConnections {
    /// One established TCP connection's far end.
    public struct Endpoint: Hashable, Sendable {
        public let address: String
        public let port: Int
        public init(address: String, port: Int) { self.address = address; self.port = port }
        public var description: String { address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)" }
    }

    /// The established connections of `pids`, as `lsof` reports them right now.
    public static func established(pids: [pid_t]) -> Set<Endpoint> {
        guard !pids.isEmpty else { return [] }
        let list = pids.map { String($0) }.joined(separator: ",")
        let result = Shell.run("/usr/sbin/lsof", ["-nP", "-a", "-p", list, "-iTCP", "-sTCP:ESTABLISHED"])
        return remoteEndpoints(inLsof: result.stdout)
    }

    /// The far ends in `lsof -nP -iTCP` output: the part after `->` in its NAME column,
    /// `192.168.1.5:50123->151.101.1.1:443 (ESTABLISHED)` or `[fe80::1]:5->[2a00:1450::1]:443`.
    static func remoteEndpoints(inLsof text: String) -> Set<Endpoint> {
        var found = Set<Endpoint>()
        for line in text.split(whereSeparator: \.isNewline) {
            guard let arrow = line.range(of: "->") else { continue }
            let far = line[arrow.upperBound...].split(separator: " ").first.map(String.init) ?? ""
            guard let colon = far.lastIndex(of: ":"), let port = Int(far[far.index(after: colon)...]) else { continue }
            var address = String(far[..<colon])
            if address.hasPrefix("["), address.hasSuffix("]") { address = String(address.dropFirst().dropLast()) }
            guard !address.isEmpty else { continue }
            found.insert(Endpoint(address: address, port: port))
        }
        return found
    }

    /// Whether `address` is somewhere on the internet rather than this Mac or the local network —
    /// a game talking to its own launcher over loopback has not reached anything.
    static func isPublic(_ address: String) -> Bool {
        let lower = address.lowercased()
        if lower.contains(":") {
            return !(lower == "::1" || lower.hasPrefix("fe80") || lower.hasPrefix("fc") || lower.hasPrefix("fd")
                     || lower.hasPrefix("::ffff:127.") || lower.hasPrefix("::ffff:10.") || lower.hasPrefix("::ffff:192.168."))
        }
        let octets = lower.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (0, _), (169, 254), (192, 168): return false
        case (172, let second) where (16...31).contains(second): return false
        case (100, let second) where (64...127).contains(second): return false   // carrier-grade NAT
        default: return true
        }
    }

    /// What `host` resolves to on this Mac, now. CDNs rotate their addresses, so a check asks
    /// again while the game runs rather than once.
    public static func addresses(of host: String) -> Set<String> {
        let result = Shell.run("/usr/bin/dscacheutil", ["-q", "host", "-a", "name", host])
        return addresses(inDscacheutil: result.stdout)
    }

    /// The addresses in `dscacheutil -q host` output (`ip_address: 1.2.3.4`, `ipv6_address: …`).
    static func addresses(inDscacheutil text: String) -> Set<String> {
        var found = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, ["ip_address", "ipv6_address"].contains(parts[0]), !parts[1].isEmpty else { continue }
            found.insert(parts[1].lowercased())
        }
        return found
    }

    /// The host part of a profile's `online_hosts` entry, which may be written as a URL.
    static func hostName(_ entry: String) -> String {
        if let url = URL(string: entry), let host = url.host, entry.contains("://") { return host.lowercased() }
        return entry.split(separator: "/").first.map { String($0).lowercased() } ?? entry.lowercased()
    }
}
