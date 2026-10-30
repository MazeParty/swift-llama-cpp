#if compiler(>=6.4) && canImport(FoundationModels)
import Foundation
import FoundationModels
import Testing
@testable import SwiftLlama

@Suite(.serialized)
struct LFM3ToolCallingTests {
    @available(iOS 27.0, macOS 27.0, *)
    private var definitions: [Transcript.ToolDefinition] { LlamaToolCallingTests.definitions }
    private let call = "<tool_call>\n<function=calculator>\n<parameter=lhs>\n17\n</parameter>\n<parameter=operation>\nmultiply\n</parameter>\n<parameter=rhs>\n23\n</parameter>\n</function>\n</tool_call>"

    @available(iOS 27.0, macOS 27.0, *)
    @Test("LFM3 XML calls survive every fragment boundary without exposing control syntax")
    func fragmentation() throws {
        let raw = "Before " + call + "\nDone."
        for boundary in 0...raw.count {
            var parser = LlamaToolParser(usesXML: true)
            let split = raw.index(raw.startIndex, offsetBy: boundary)
            let visible = try parser.append(String(raw[..<split])) + parser.append(String(raw[split...]))
            let (trailing, calls) = try parser.finish(definitions: definitions)
            #expect(visible == "Before ")
            #expect(trailing == "\nDone.")
            #expect(calls.count == 1)
            #expect(calls.first?.arguments == #"{"lhs":17,"operation":"multiply","rhs":23}"#)
        }
    }

    @available(iOS 27.0, macOS 27.0, *)
    @Test("LFM3 rejects incomplete, unknown, duplicate and invalid arguments before any execution", arguments: [
        "<tool_call", "<tool_call><function=calculator>",
        "<tool_call><function=missing></function></tool_call>",
        "<tool_call><function=calculator><parameter=lhs>17</parameter></function></tool_call>",
        "<tool_call><function=calculator><parameter=lhs>17</parameter><parameter=lhs>23</parameter></function></tool_call>",
        "<tool_call><function=calculator><parameter=lhs>true</parameter><parameter=rhs>23</parameter><parameter=operation>multiply</parameter></function></tool_call>"
    ])
    func invalid(raw: String) throws {
        var parser = LlamaToolParser(usesXML: true)
        _ = try parser.append(raw)
        #expect(throws: (any Error).self) { try parser.finish(definitions: definitions) }
    }

    @available(iOS 27.0, macOS 27.0, *)
    @Test("Whole XML batches validate before any call is returned")
    func batches() throws {
        var parser = LlamaToolParser(usesXML: true)
        _ = try parser.append(call + "\n\n" + call)
        #expect(try parser.finish(definitions: definitions).1.count == 2)
        var invalid = LlamaToolParser(usesXML: true)
        _ = try invalid.append(call + "\n<tool_call><function=missing></function></tool_call>")
        #expect(throws: (any Error).self) { try invalid.finish(definitions: definitions) }
        var truncated = LlamaToolParser(usesXML: true)
        _ = try truncated.append(call + "Done.<tool_ca")
        #expect(throws: (any Error).self) { try truncated.finish(definitions: definitions) }
    }

    @available(iOS 27.0, macOS 27.0, *)
    @Test("XML string, array and boolean arguments retain their schema types")
    func values() throws {
        let schema = try JSONDecoder().decode(GenerationSchema.self, from: Data(#"{"title":"Arguments","x-order":["title","items","enabled","optional"],"type":"object","properties":{"title":{"type":"string"},"items":{"type":"array","items":{"type":"integer"}},"enabled":{"type":"boolean"},"optional":{"type":"string"}},"required":["title","items","enabled","optional"],"additionalProperties":false}"#.utf8))
        let definition = Transcript.ToolDefinition(name: "save", description: "Save", parameters: schema)
        var parser = LlamaToolParser(usesXML: true)
        let raw = "<tool_call>\n<function=save>\n<parameter=title>\n17\n</parameter>\n<parameter=items>\n[1,-2,3]\n</parameter>\n<parameter=enabled>\ntrue\n</parameter>\n<parameter=optional>\nnull\n</parameter>\n</function>\n</tool_call>"
        for character in raw { #expect(try parser.append(String(character)).isEmpty) }
        let calls = try parser.finish(definitions: [definition]).1
        let arguments = try #require(calls.first).arguments
        let object = try #require(JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any])
        #expect(object["title"] as? String == "17")
        #expect(object["items"] as? [Int] == [1, -2, 3])
        #expect(object["enabled"] as? Bool == true)
        #expect(object["optional"] as? String == "null")
    }

    @available(iOS 27.0, macOS 27.0, *)
    @Test("The qualified LFM3 template preserves raw assistant history and wraps tool results")
    func template() throws {
        let transcript = Transcript(entries: [.instructions(.init(segments: [.text(.init(content: "Be helpful."))], toolDefinitions: definitions))])
        let mapped = try LlamaTranscriptMapper.messages(transcript, profile: .lfm3QADQ4_0)
        #expect(mapped[0].content.hasPrefix("Be helpful.\n\n<tools>\n{"))
        #expect(mapped[0].content.hasSuffix("\n</tools>"))
        #expect(mapped[0].usesLFM3Template)
        let messages: [LlamaChatMessage] = [.init(role: .system, content: ""), .init(role: .user, content: "Compute"), .init(role: .assistant, content: call), .init(role: .tool, content: "391")]
        let expected = "<|startoftext|><|im_start|>user\nCompute<|im_end|>\n<|im_start|>assistant\n<think></think>" + call + "<|im_end|>\n<|im_start|>tool\n<tool_response>\n391\n</tool_response><|im_end|>\n<|im_start|>assistant\n<think>"
        #expect(LlamaModel.renderLFM3Prompt(messages, bos: "<|startoftext|>", addAssistant: true) == expected)
    }

    @available(iOS 27.0, macOS 27.0, *)
    @Test("XML examples inside model reasoning cannot execute")
    func reasoning() throws {
        var parser = LlamaToolParser(usesXML: true)
        let text = "<think>Example: " + call + "</think>Answer."
        let visible = try parser.append(text)
        let (trailing, calls) = try parser.finish(definitions: definitions)
        #expect(visible + trailing == text)
        #expect(calls.isEmpty)
    }

    @available(iOS 27.0, macOS 27.0, *)
    @Test("A native prefilled-reasoning response cannot execute XML examples and retains replay without token inflation")
    func prefilledReasoning() async throws {
        let generated = "An example: " + call + "</think>Visible answer."
        let engine = PrefilledReasoningEngine(tokens: generated.map(String.init))
        let tool = PrefilledCalculator()
        let model = LlamaLanguageModel(capabilityProfile: .lfm3QADQ4_0, engineFactory: { engine })
        let session = LanguageModelSession(model: model, tools: [tool])
        let answer = try await session.respond(to: "Explain without calling any tool")
        #expect(answer.content == "Visible answer.")
        #expect(await tool.calls == 0)
        #expect(answer.usage.output.totalTokenCount == generated.count)
        let history = try LlamaTranscriptMapper.messages(session.transcript, profile: .lfm3QADQ4_0)
        #expect(history.last?.content == "<think>" + generated)
        await model.unload()
    }

    @available(iOS 27.0, macOS 27.0, *)
    @Test("Renamed model files cannot opt into LFM3 tool capability")
    func verification() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gguf")
        try Data("not the qualified model".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: LlamaToolError.unverifiedModel) { try LlamaCapabilityProfile.lfm3QADQ4_0.validate(modelURL: url) }
    }
}

@available(iOS 27.0, macOS 27.0, *)
private actor PrefilledCalculator: Tool {
    nonisolated let name = "calculator"
    nonisolated let description = "Calculate"
    @Generable struct Arguments: Sendable { var lhs: Double; var operation: String; var rhs: Double }
    private(set) var calls = 0
    func call(arguments: Arguments) async throws -> String { calls += 1; return "391" }
}

@available(iOS 27.0, macOS 27.0, *)
private actor PrefilledReasoningEngine: LlamaExecutorEngine {
    var tokens: [String]
    init(tokens: [String]) { self.tokens = tokens }
    func hasPrefilledReasoning() -> Bool { true }
    func prepare(_ messages: [LlamaChatMessage], addingAssistant: Bool) -> Int { 17 }
    func updateSamplingConfig(_ config: LlamaSamplingConfig) {}
    func generateNextToken() -> NextToken { tokens.isEmpty ? .endOfString : .token(tokens.removeFirst()) }
    func resetCompletion() {}
    func contextUsage(_ messages: [LlamaChatMessage], addingAssistant: Bool) -> LlamaContextUsage { .init(usedTokens: 17, effectiveCapacity: 4000) }
}
#endif
