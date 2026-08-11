import Foundation

enum YAMLScalarDecoder {
    static func decode(_ value: String) -> String {
        guard value.contains("\\") else { return value }

        var output = ""
        var index = value.startIndex
        while index < value.endIndex {
            let character = value[index]
            guard character == "\\" else {
                output.append(character)
                index = value.index(after: index)
                continue
            }

            let escapeIndex = value.index(after: index)
            guard escapeIndex < value.endIndex else {
                output.append(character)
                index = escapeIndex
                continue
            }

            let escape = value[escapeIndex]
            switch escape {
            case "0":
                output.append("\0")
                index = value.index(after: escapeIndex)
            case "a":
                output.append("\u{7}")
                index = value.index(after: escapeIndex)
            case "b":
                output.append("\u{8}")
                index = value.index(after: escapeIndex)
            case "t":
                output.append("\t")
                index = value.index(after: escapeIndex)
            case "n":
                output.append("\n")
                index = value.index(after: escapeIndex)
            case "v":
                output.append("\u{B}")
                index = value.index(after: escapeIndex)
            case "f":
                output.append("\u{C}")
                index = value.index(after: escapeIndex)
            case "r":
                output.append("\r")
                index = value.index(after: escapeIndex)
            case "e":
                output.append("\u{1B}")
                index = value.index(after: escapeIndex)
            case "\"", "'", "\\", "/":
                output.append(escape)
                index = value.index(after: escapeIndex)
            case "x":
                index = appendUnicodeEscape(from: value, after: escapeIndex, length: 2, to: &output)
                    ?? value.index(after: index)
            case "u":
                index = appendUnicodeEscape(from: value, after: escapeIndex, length: 4, to: &output)
                    ?? value.index(after: index)
            case "U":
                index = appendUnicodeEscape(from: value, after: escapeIndex, length: 8, to: &output)
                    ?? value.index(after: index)
            default:
                output.append(character)
                output.append(escape)
                index = value.index(after: escapeIndex)
            }
        }

        return output
    }

    private static func appendUnicodeEscape(
        from value: String,
        after escapeIndex: String.Index,
        length: Int,
        to output: inout String
    ) -> String.Index? {
        let hexStart = value.index(after: escapeIndex)
        var hexEnd = hexStart
        for _ in 0..<length {
            guard hexEnd < value.endIndex, value[hexEnd].isHexDigit else { return nil }
            hexEnd = value.index(after: hexEnd)
        }

        guard let scalarValue = UInt32(value[hexStart..<hexEnd], radix: 16),
              let scalar = UnicodeScalar(scalarValue) else {
            return nil
        }
        output.append(Character(scalar))
        return hexEnd
    }
}

enum MihomoInlineYAML {
    static func inlineMap(from line: String) -> [String: String] {
        guard let body = inlineMapBody(from: line) else { return [:] }
        return splitTopLevel(body, separator: ",").reduce(into: [String: String]()) { result, pair in
            let pieces = splitTopLevel(pair, separator: ":", maxSplits: 1)
            guard pieces.count == 2 else { return }
            let key = cleanInlineScalar(pieces[0])
            let value = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                result[key] = cleanInlineScalar(value, preserveArray: true)
            }
        }
    }

    static func parseInlineArray(_ value: String) -> [String] {
        var body = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("["), body.hasSuffix("]") {
            body.removeFirst()
            body.removeLast()
        }
        return splitTopLevel(body, separator: ",")
            .map { cleanInlineScalar($0) }
            .filter { !$0.isEmpty }
    }

    static func inlineMapBody(from line: String) -> String? {
        guard let open = line.firstIndex(of: "{") else { return nil }
        var depth = 0
        var end: String.Index?
        for index in line[open...].indices {
            let character = line[index]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    end = index
                    break
                }
            }
        }
        guard let end, end > open else { return nil }
        return String(line[line.index(after: open)..<end])
    }

    static func splitTopLevel(_ value: String, separator: Character, maxSplits: Int = Int.max) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var bracketDepth = 0
        var braceDepth = 0
        var splits = 0

        for character in value {
            if let currentQuote = quote {
                current.append(character)
                if character == currentQuote {
                    quote = nil
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
                current.append(character)
                continue
            }

            if character == "[" {
                bracketDepth += 1
                current.append(character)
                continue
            }

            if character == "]" {
                bracketDepth = max(0, bracketDepth - 1)
                current.append(character)
                continue
            }

            if character == "{" {
                braceDepth += 1
                current.append(character)
                continue
            }

            if character == "}" {
                braceDepth = max(0, braceDepth - 1)
                current.append(character)
                continue
            }

            if character == separator, bracketDepth == 0, braceDepth == 0, splits < maxSplits {
                parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                splits += 1
                continue
            }

            current.append(character)
        }

        parts.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts
    }

    static func cleanInlineScalar(_ value: String, preserveArray: Bool = false) -> String {
        var scalar = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preserveArray || !(scalar.hasPrefix("[") && scalar.hasSuffix("]")) {
            scalar = scalar.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        guard !preserveArray || !(scalar.hasPrefix("[") && scalar.hasSuffix("]")) else {
            return scalar
        }
        return YAMLScalarDecoder.decode(scalar)
    }
}
