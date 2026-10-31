import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Simple cases are recognized by rule. The rest go to the on-device Apple Intelligence model, which reads the
/// edits as rewritten, removed and added lines; given a raw diff it tends to retell the content instead.
enum EditSummary {
    enum Edit: Equatable {
        case rewritten(String, String)
        case removed(String)
        case added(String)
    }

    private static let timeout: TimeInterval = 15
    private static let maxInputLength = 2000

    static func describe(diff: String) -> String? {
        let edits = edits(in: diff)
        guard !edits.isEmpty else { return nil }
        let language = Language.detect(in: text(of: edits))
        if let summary = ruleBasedSummary(of: edits, in: language) {
            return summary
        }
        return modelSummary(of: edits, in: language)
    }

    static func edits(in diff: String) -> [Edit] {
        var edits: [Edit] = []
        var removed: [String] = []
        var added: [String] = []
        func flush() {
            let pairs = min(removed.count, added.count)
            edits += (0..<pairs).map { .rewritten(removed[$0], added[$0]) }
            edits += removed.dropFirst(pairs).map { .removed($0) }
            edits += added.dropFirst(pairs).map { .added($0) }
            removed = []
            added = []
        }
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("---") || line.hasPrefix("+++") { continue }
            let text = line.dropFirst().trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("-") {
                if !text.isEmpty { removed.append(text) }
            } else if line.hasPrefix("+") {
                if !text.isEmpty { added.append(text) }
            } else if !line.hasPrefix("\\") {
                flush()
            }
        }
        flush()
        return edits
    }

    static func ruleBasedSummary(of edits: [Edit], in language: Language) -> String? {
        let rewrites = edits.compactMap { edit -> (String, String)? in
            if case .rewritten(let old, let new) = edit { return (old, new) }
            return nil
        }
        guard rewrites.count == edits.count, let first = rewrites.first else { return nil }

        let (from, to) = difference(first.0, first.1)
        let occurrences = rewrites.reduce(0) { $0 + $1.0.components(separatedBy: from).count - 1 }
        if !from.isEmpty, occurrences >= 2,
            rewrites.allSatisfy({ $0.0.replacingOccurrences(of: from, with: to) == $0.1 })
        {
            return language.renamed(from, to)
        }

        if rewrites.allSatisfy({ difference($0.0, $0.1).0.count <= 3 && difference($0.0, $0.1).1.count <= 3 }) {
            return language.smallFixes
        }
        return nil
    }

    static func difference(_ old: String, _ new: String) -> (String, String) {
        let ranges = Diff.changedRanges(old, new)
        return (String(Array(old)[ranges.old]), String(Array(new)[ranges.new]))
    }

    static func text(of edits: [Edit]) -> String {
        edits.map { edit in
            switch edit {
            case .rewritten(let old, let new): old + "\n" + new
            case .removed(let line), .added(let line): line
            }
        }
        .joined(separator: "\n")
    }

    static func modelInput(for edits: [Edit], in language: Language) -> String {
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

    static func cleanUp(_ summary: String, in language: Language) -> String {
        var line = summary.split(separator: "\n").first.map(String.init) ?? ""
        line = line.trimmingCharacters(in: .whitespaces)
        while line.hasSuffix(language.period) { line.removeLast(language.period.count) }
        let (open, close) = language.quotes
        if line.hasPrefix(open), !line.dropFirst(open.count).contains(close) { line.removeFirst(open.count) }
        return line
    }

    private static func modelSummary(of edits: [Edit], in language: Language) -> String? {
        #if canImport(FoundationModels)
            guard #available(macOS 26, *), SystemLanguageModel.default.isAvailable else { return nil }
            let input = modelInput(for: edits, in: language)
            let instructions = language.instructions

            // Commits run on a background queue that waits for the answer
            let answer = Handoff<String?>(nil)
            let done = DispatchSemaphore(value: 0)
            let task = Task {
                defer { done.signal() }
                let session = LanguageModelSession(instructions: instructions)
                answer.value = try? await session.respond(to: input, generating: Generated.self).content.text
            }
            guard done.wait(timeout: .now() + timeout) == .success else {
                task.cancel()
                return nil
            }
            let line = cleanUp(answer.value ?? "", in: language)
            return line.isEmpty ? nil : String(line.prefix(80))
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
