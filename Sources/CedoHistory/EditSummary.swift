import Foundation
import os

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Simple cases are recognized by rule. The rest go to the on-device Apple Intelligence model, which reads the
/// edits as rewritten, removed and added lines; given a raw diff it tends to retell the content instead.
enum EditSummary {
    /// Answers the instructions about the input in one line, or nil when no model is at hand.
    typealias Model = (_ instructions: String, _ input: String) -> String?

    private typealias Edit = Diff.Edit

    private static let timeout: TimeInterval = 15
    private static let maxInputLength = 2000

    static func describe(diff: String, model: Model = onDeviceModel) -> String? {
        let edits = Diff.edits(in: diff)
        guard !edits.isEmpty else { return nil }
        let language = Language.detect(in: text(of: edits))
        if let summary = ruleBasedSummary(of: edits, in: language) {
            return summary
        }
        guard let answer = model(language.instructions, modelInput(for: edits, in: language)) else { return nil }
        let line = cleanUp(answer, in: language)
        return line.isEmpty ? nil : String(line.prefix(80))
    }

    private static func ruleBasedSummary(of edits: [Edit], in language: Language) -> String? {
        let rewrites = edits.compactMap { edit -> (String, String)? in
            if case .rewritten(let old, let new) = edit { return (old, new) }
            return nil
        }
        guard rewrites.count == edits.count, let first = rewrites.first else { return nil }

        let (before, after) = Diff.changedTexts(first.0, first.1)
        let occurrences = rewrites.reduce(0) { $0 + $1.0.components(separatedBy: before).count - 1 }
        if !before.isEmpty, occurrences >= 2,
            rewrites.allSatisfy({ $0.0.replacingOccurrences(of: before, with: after) == $0.1 })
        {
            return language.renamed(before, after)
        }

        if rewrites.allSatisfy({
            let changed = Diff.changedTexts($0.0, $0.1)
            return changed.old.count <= 3 && changed.new.count <= 3
        }) {
            return language.smallFixes
        }
        return nil
    }

    private static func text(of edits: [Edit]) -> String {
        edits.map { edit in
            switch edit {
            case .rewritten(let old, let new): old + "\n" + new
            case .removed(let line), .added(let line): line
            }
        }
        .joined(separator: "\n")
    }

    private static func modelInput(for edits: [Edit], in language: Language) -> String {
        var lines: [String] = []
        var length = 0
        for edit in edits {
            let line =
                switch edit {
                case .rewritten(let old, let new):
                    "\(language.rewrittenLabel): \(language.quote(old)) → \(language.quote(new))"
                case .removed(let text): "\(language.removedLabel): \(language.quote(text))"
                case .added(let text): "\(language.addedLabel): \(language.quote(text))"
                }
            // The on-device model has a small context, and long inputs make it ramble
            guard length + line.count <= maxInputLength else {
                lines.append(language.more(edits.count - lines.count))
                break
            }
            lines.append(line)
            length += line.count
        }
        return lines.joined(separator: "\n")
    }

    private static func cleanUp(_ summary: String, in language: Language) -> String {
        var line = summary.split(separator: "\n").first.map(String.init) ?? ""
        line = line.trimmingCharacters(in: .whitespaces)
        while line.hasSuffix(language.period) { line.removeLast(language.period.count) }
        let (open, close) = language.quotes
        if line.hasPrefix(open), !line.dropFirst(open.count).contains(close) { line.removeFirst(open.count) }
        return line
    }

    private static func onDeviceModel(instructions: String, input: String) -> String? {
        #if canImport(FoundationModels)
            guard #available(macOS 26, *), SystemLanguageModel.default.isAvailable else { return nil }

            // Commits run on a background queue that waits for the answer
            let answer = OSAllocatedUnfairLock<String?>(initialState: nil)
            let done = DispatchSemaphore(value: 0)
            let task = Task {
                defer { done.signal() }
                let session = LanguageModelSession(instructions: instructions)
                let text = try? await session.respond(to: input, generating: Generated.self).content.text
                answer.withLock { $0 = text }
            }
            guard done.wait(timeout: .now() + timeout) == .success else {
                task.cancel()
                return nil
            }
            return answer.withLock { $0 }
        #else
            return nil
        #endif
    }
}

#if canImport(FoundationModels)
    @available(macOS 26, *)
    @Generable
    struct Generated {
        @Guide(description: "A single line describing what the writer did")
        var text: String
    }
#endif
