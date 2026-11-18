import Foundation
import Testing

@testable import CedoKit

struct EditSummaryTests {
    @Test func recognizesARename() {
        let summary = describe(
            """
            -Docker でコンテナを起動する。
            -先に Docker のイメージを取得しておく。
            +Podman でコンテナを起動する。
            +先に Podman のイメージを取得しておく。
            """)
        #expect(summary == "「Docker」を「Podman」に変えた")
    }

    @Test func recognizesSmallFixes() {
        let summary = describe(
            """
            -キャッシュを削除します。
            -設定は 1 行で書く事ができる。
            +キャッシュを消去します。
            +設定は 1 行で書くことができる。
            """)
        #expect(summary == "細かな表記を直した")
    }

    @Test func leavesRealRewritesToTheModel() {
        var asked = 0
        let model: EditSummary.Model = { _, _ in
            asked += 1
            return "非推奨の API の説明を書き直した"
        }
        #expect(
            describe("-この API は非推奨です。\n+この API は v3 で削除されたため、代わりに fetch を使ってください。", model: model)
                == "非推奨の API の説明を書き直した")
        #expect(describe("-a\n b\n-c\n+d", model: model) == "非推奨の API の説明を書き直した")
        #expect(asked == 2)
    }

    @Test func givesUpWithoutAModel() {
        #expect(describe("+キャッシュの仕組みを説明する節") == nil)
    }

    @Test func cleansUpTheModelOutput() {
        #expect(
            describe("+キャッシュの仕組み", answer: "「キャッシュの仕組みを説明する節を追加した\n余計な行")
                == "キャッシュの仕組みを説明する節を追加した")
        #expect(describe("+npm install でパッケージを入れる。", answer: "「npm install」の手順を書き直した。") == "「npm install」の手順を書き直した")
        #expect(describe("+Install steps", answer: "\"Rewrote the install steps.") == "Rewrote the install steps")
        #expect(describe("+npm to pnpm", answer: "Renamed \"npm\" to \"pnpm\".") == "Renamed \"npm\" to \"pnpm\"")
        #expect(describe("+空の答え", answer: "。") == nil)
    }

    @Test func asksInTheLanguageOfTheText() {
        #expect(instructions(for: "+Docker でコンテナを起動する。") == EditSummary.Language.japanese.instructions)
        #expect(instructions(for: "+Added a code sample.") == EditSummary.Language.english.instructions)
        #expect(instructions(for: "+Ajouté un exemple de code.") == EditSummary.Language.english.instructions)
    }

    @Test func shortensLongInput() {
        var input = ""
        let line = "+" + String(repeating: "あ", count: 300)
        _ = describe(Array(repeating: line, count: 10).joined(separator: "\n")) { _, given in
            input = given
            return nil
        }
        #expect(input.count <= 2100)
        #expect(input.hasSuffix("（ほか 4 件）"))
    }

    private func describe(_ body: String, model: EditSummary.Model = { _, _ in nil }) -> String? {
        EditSummary.describe(diff: "@@ -1 +1 @@\n" + body, model: model)
    }

    private func describe(_ body: String, answer: String) -> String? {
        describe(body) { _, _ in answer }
    }

    private func instructions(for body: String) -> String? {
        var asked: String?
        _ = describe(body) { instructions, _ in
            asked = instructions
            return nil
        }
        return asked
    }
}
