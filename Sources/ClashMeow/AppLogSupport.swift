import Foundation

enum LogTimeSupport {
    private static func makeFormatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = dateFormat
        return formatter
    }

    static func string(from date: Date = Date()) -> String {
        makeFormatter(dateFormat: "yyyy-MM-dd'T'HH:mm:ssZZZZZ").string(from: date)
    }

    static func displayString(from timestamp: String?) -> String? {
        guard let timestamp else { return nil }
        let trimmed = timestamp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let date = date(from: trimmed) else { return trimmed }
        return makeFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss").string(from: date)
    }

    private static func date(from timestamp: String) -> Date? {
        let isoFormatterWithFractionalSeconds = ISO8601DateFormatter()
        isoFormatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatterWithFractionalSeconds.date(from: timestamp) {
            return date
        }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: timestamp) {
            return date
        }
        return nil
    }
}

enum AppLogSupport {
    static func debug(_ message: String, module: String, logsDirectory: URL) {
        write(level: "debug", message: message, module: module, logsDirectory: logsDirectory)
    }

    static func info(_ message: String, module: String, logsDirectory: URL) {
        write(level: "info", message: message, module: module, logsDirectory: logsDirectory)
    }

    static func warning(_ message: String, module: String, logsDirectory: URL) {
        write(level: "warning", message: message, module: module, logsDirectory: logsDirectory)
    }

    static func error(_ message: String, module: String, logsDirectory: URL) {
        write(level: "error", message: message, module: module, logsDirectory: logsDirectory)
    }

    private static func write(level: String, message: String, module: String, logsDirectory: URL) {
        guard LogPreference.isAppLoggingEnabled else { return }
        let timestamp = LogTimeSupport.string()
        let sanitized = message.replacingOccurrences(of: "\n", with: "\\n")
        let line = "[\(timestamp)] [\(level.uppercased())] [\(module)] \(sanitized)\n"
        let fileURL = logsDirectory.appending(path: "app.log")
        try? CoreLogSupport.appendWithLimit(line, to: fileURL)
    }
}
