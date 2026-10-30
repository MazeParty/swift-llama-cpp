#if compiler(>=6.4) && canImport(FoundationModels)
import Foundation
import FoundationModels

/// Reads LFM3's literal parameter protocol; this is not a general XML document parser.
@available(iOS 27.0, macOS 27.0, *)
struct LlamaXMLCallReader {
    private var remaining: Substring

    init(_ text: String) { remaining = text[...] }

    mutating func calls(definitions: [Transcript.ToolDefinition]) throws -> (String, [LlamaParsedToolCall]) {
        var calls: [LlamaParsedToolCall] = []
        while true {
            try require("<tool_call>")
            let name = try tagName(prefix: "<function=")
            guard let definition = definitions.first(where: { $0.name == name }) else { throw LlamaToolError.unknownTool(name) }
            let schema = try JSONSerialization.jsonObject(with: JSONEncoder().encode(definition.parameters))
            var arguments: [String: Any] = [:]
            while remaining.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<parameter=") {
                let key = try tagName(prefix: "<parameter=")
                guard arguments[key] == nil, let end = remaining.range(of: "</parameter>") else { throw LlamaToolError.malformedCall }
                var literal = String(remaining[..<end.lowerBound])
                if literal.hasPrefix("\n") { literal.removeFirst() }
                if literal.hasSuffix("\n") { literal.removeLast() }
                remaining = remaining[end.upperBound...]
                guard let property = property(key, schema: schema, root: schema) else { throw LlamaToolError.invalidArguments(name) }
                if let value = try? JSONSerialization.jsonObject(with: Data(literal.utf8), options: .fragmentsAllowed),
                   LlamaToolSchema.validate(value, schema: property, root: schema) {
                    arguments[key] = value
                } else if LlamaToolSchema.validate(literal, schema: property, root: schema) {
                    arguments[key] = literal
                } else { throw LlamaToolError.invalidArguments(name) }
            }
            try require("</function>")
            try require("</tool_call>")
            guard LlamaToolSchema.validate(arguments, schema: schema, root: schema) else { throw LlamaToolError.invalidArguments(name) }
            let data = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes])
            calls.append(.init(name: name, arguments: String(decoding: data, as: UTF8.self)))
            let suffix = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if suffix.hasPrefix("<tool_call>") { continue }
            let truncated = ["<tool_call>", "</tool_call>"].contains { marker in
                (1..<marker.count).contains { remaining.hasSuffix(marker.prefix($0)) }
            }
            guard !remaining.contains("<tool_call>"), !remaining.contains("</tool_call>"),
                  !truncated, !suffix.hasPrefix("<tool_call"), !suffix.hasPrefix("</tool_call") else { throw LlamaToolError.malformedCall }
            return (String(remaining), calls)
        }
    }

    private mutating func require(_ token: String) throws {
        remaining = remaining.drop(while: \.isWhitespace)
        guard remaining.hasPrefix(token) else { throw LlamaToolError.malformedCall }
        remaining = remaining.dropFirst(token.count)
    }

    private mutating func tagName(prefix: String) throws -> String {
        try require(prefix)
        guard let end = remaining.firstIndex(of: ">") else { throw LlamaToolError.malformedCall }
        let name = String(remaining[..<end])
        guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { throw LlamaToolError.malformedCall }
        remaining = remaining[remaining.index(after: end)...]
        return name
    }

    private func property(_ key: String, schema: Any, root: Any, depth: Int = 0) -> Any? {
        guard depth < 64, let object = schema as? [String: Any] else { return nil }
        if let ref = object["$ref"] as? String, ref.hasPrefix("#/") {
            var value = root
            for component in ref.dropFirst(2).split(separator: "/") {
                guard let next = (value as? [String: Any])?[String(component).replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")] else { return nil }
                value = next
            }
            return property(key, schema: value, root: root, depth: depth + 1)
        }
        return (object["properties"] as? [String: Any])?[key]
    }
}
#endif
