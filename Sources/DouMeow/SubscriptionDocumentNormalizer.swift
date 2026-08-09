import Foundation

enum SubscriptionDocumentNormalizer {
    static func normalize(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProfileRepositoryError.emptyDocument
        }

        if ProfileRepository.isLikelyMihomoYAML(trimmed) {
            return trimmed
        }

        if let decoded = decodeBase64Text(trimmed), ProfileRepository.isLikelyMihomoYAML(decoded) {
            return decoded
        }

        if let yaml = shareLinkSubscriptionYAML(from: trimmed) {
            return yaml
        }

        if let decoded = decodeBase64Text(trimmed),
           let yaml = shareLinkSubscriptionYAML(from: decoded) {
            return yaml
        }

        throw ProfileRepositoryError.invalidYAML
    }

    static func proxyCount(in yaml: String) -> Int {
        ProxyNodeInfo.parsed(from: yaml).count
    }

    private static func decodeBase64Text(_ value: String) -> String? {
        let sanitized = value.replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: sanitized) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func shareLinkSubscriptionYAML(from value: String) -> String? {
        let proxies = value
            .split(whereSeparator: \.isNewline)
            .compactMap { proxy(from: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard !proxies.isEmpty else { return nil }

        let names = proxies.map { $0.name }
        var lines: [String] = [
            "proxies:"
        ]
        for proxy in proxies {
            lines.append("  - name: \(quotedYAML(proxy.name))")
            for (key, value) in proxy.fields {
                lines.append("    \(key): \(value)")
            }
        }
        lines.append("")
        lines.append("proxy-groups:")
        lines.append("  - name: Proxy")
        lines.append("    type: select")
        lines.append("    proxies:")
        for name in names {
            lines.append("      - \(quotedYAML(name))")
        }
        lines.append("      - DIRECT")
        lines.append("")
        lines.append("rules:")
        lines.append("  - MATCH,Proxy")
        return lines.joined(separator: "\n")
    }

    private static func proxy(from line: String) -> ShareProxy? {
        guard let url = URLComponents(string: line),
              let scheme = url.scheme?.lowercased(),
              ["vless", "ss", "anytls"].contains(scheme),
              let host = url.host,
              let port = url.port else {
            return nil
        }

        let name = decodedName(url.percentEncodedFragment, fallback: "\(scheme)-\(host)-\(port)")
        let query = queryItems(url)
        switch scheme {
        case "vless":
            guard let uuid = url.user, !uuid.isEmpty else { return nil }
            return vlessProxy(name: name, server: host, port: port, uuid: uuid, query: query)
        case "ss":
            return shadowsocksProxy(name: name, server: host, port: port, encodedUser: url.percentEncodedUser)
        case "anytls":
            guard let password = url.user, !password.isEmpty else { return nil }
            return anyTLSProxy(name: name, server: host, port: port, password: password, query: query)
        default:
            return nil
        }
    }

    private static func vlessProxy(
        name: String,
        server: String,
        port: Int,
        uuid: String,
        query: [String: String]
    ) -> ShareProxy {
        var fields: [(String, String)] = [
            ("type", "vless"),
            ("server", quotedYAML(server)),
            ("port", "\(port)"),
            ("uuid", quotedYAML(uuid)),
            ("network", quotedYAML(query["type"] ?? "tcp")),
            ("udp", "true")
        ]
        if let flow = query["flow"], !flow.isEmpty {
            fields.append(("flow", quotedYAML(flow)))
        }
        let security = query["security"]?.lowercased()
        if security == "tls" || security == "reality" {
            fields.append(("tls", "true"))
        }
        if let servername = query["sni"] ?? query["servername"], !servername.isEmpty {
            fields.append(("servername", quotedYAML(servername)))
        }
        if let fingerprint = query["fp"], !fingerprint.isEmpty {
            fields.append(("client-fingerprint", quotedYAML(fingerprint)))
        }
        if security == "reality", let publicKey = query["pbk"], !publicKey.isEmpty {
            fields.append(("reality-opts", ""))
            fields.append(("  public-key", quotedYAML(publicKey)))
            if let shortID = query["sid"], !shortID.isEmpty {
                fields.append(("  short-id", quotedYAML(shortID)))
            }
        }
        return ShareProxy(name: name, fields: fields)
    }

    private static func shadowsocksProxy(
        name: String,
        server: String,
        port: Int,
        encodedUser: String?
    ) -> ShareProxy? {
        guard let encodedUser,
              let decoded = decodeBase64URLText(encodedUser),
              let separator = decoded.firstIndex(of: ":") else {
            return nil
        }
        let cipher = String(decoded[..<separator])
        let password = String(decoded[decoded.index(after: separator)...])
        guard !cipher.isEmpty, !password.isEmpty else { return nil }
        return ShareProxy(
            name: name,
            fields: [
                ("type", "ss"),
                ("server", quotedYAML(server)),
                ("port", "\(port)"),
                ("cipher", quotedYAML(cipher)),
                ("password", quotedYAML(password)),
                ("udp", "true")
            ]
        )
    }

    private static func anyTLSProxy(
        name: String,
        server: String,
        port: Int,
        password: String,
        query: [String: String]
    ) -> ShareProxy {
        var fields: [(String, String)] = [
            ("type", "anytls"),
            ("server", quotedYAML(server)),
            ("port", "\(port)"),
            ("password", quotedYAML(password))
        ]
        if let sni = query["sni"], !sni.isEmpty {
            fields.append(("sni", quotedYAML(sni)))
        }
        if query["insecure"] == "1" || query["allowInsecure"]?.lowercased() == "true" {
            fields.append(("skip-cert-verify", "true"))
        }
        return ShareProxy(name: name, fields: fields)
    }

    private static func queryItems(_ url: URLComponents) -> [String: String] {
        (url.queryItems ?? []).reduce(into: [:]) { result, item in
            result[item.name] = item.value ?? ""
        }
    }

    private static func decodedName(_ encoded: String?, fallback: String) -> String {
        guard let encoded,
              let decoded = encoded.removingPercentEncoding,
              !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return decoded
    }

    private static func decodeBase64URLText(_ value: String) -> String? {
        var sanitized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = sanitized.count % 4
        if padding > 0 {
            sanitized += String(repeating: "=", count: 4 - padding)
        }
        guard let data = Data(base64Encoded: sanitized) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func quotedYAML(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private struct ShareProxy {
        let name: String
        let fields: [(String, String)]
    }
}
