import Foundation
import NaturalLanguage

extension EditSummary {
    /// The wording of summaries in one language. Add a language by defining one more and listing it in `supported`.
    struct Language {
        let code: NLLanguage
        let quotes: (open: String, close: String)
        let period: String
        let instructions: String
        let rewrittenLabel: String
        let removedLabel: String
        let addedLabel: String
        let more: (Int) -> String
        let renamed: (String, String) -> String
        let smallFixes: String

        /// The first one is used when the text is in none of them.
        static let supported: [Language] = [.english, .japanese]

        static func detect(in text: String) -> Language {
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = supported.map(\.code)
            recognizer.processString(text)
            return supported.first { $0.code == recognizer.dominantLanguage } ?? supported[0]
        }

        func quote(_ text: String) -> String {
            quotes.open + text + quotes.close
        }

        static let english = Language(
            code: .english,
            quotes: ("\"", "\""),
            period: ".",
            instructions: """
                You write short notes for the edit history of a piece of writing.
                Read the list of changes and say in one line of at most 60 characters what the writer did,
                such as "Rewrote …", "Removed …" or "Added …". Describe the work, not the content.
                """,
            rewrittenLabel: "Rewrote",
            removedLabel: "Removed",
            addedLabel: "Added",
            more: { "(\($0) more)" },
            renamed: { "Changed \"\($0)\" to \"\($1)\"" },
            smallFixes: "Fixed small wording"
        )

        static let japanese = Language(
            code: .japanese,
            quotes: ("「", "」"),
            period: "。",
            instructions: """
                あなたは文章の編集履歴に短い説明を付けるアシスタントです。
                書き手が行った変更の一覧を読み、何をしたかを日本語で1行、40字以内で書いてください。
                「〜を書き直した」「〜を削除した」「〜を追加した」のように、行った作業を書いてください。
                内容の要約ではなく、作業の説明を書いてください。
                """,
            rewrittenLabel: "書き換え",
            removedLabel: "削除",
            addedLabel: "追加",
            more: { "（ほか \($0) 件）" },
            renamed: { "「\($0)」を「\($1)」に変えた" },
            smallFixes: "細かな表記を直した"
        )
    }
}
