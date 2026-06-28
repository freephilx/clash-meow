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
}
