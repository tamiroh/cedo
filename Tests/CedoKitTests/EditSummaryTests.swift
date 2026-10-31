import Foundation
import Testing

@testable import CedoKit

struct EditSummaryTests {
    @Test func readsRewritesRemovalsAndAdditions() {
        let diff = """
            diff --git a/a.md b/a.md
            --- a/a.md
            +++ b/a.md
            @@ -3 +3 @@
            -古い手順
            +新しい手順
            @@ -10,2 +9,0 @@
            -消したコード例
            -
            @@ -20,0 +18 @@
            +足した注意書き
            \\ No newline at end of file
            """
        #expect(
            EditSummary.edits(in: diff) == [
                .rewritten("古い手順", "新しい手順"), .removed("消したコード例"), .added("足した注意書き"),
            ])
    }

    @Test func recognizesARename() {
        let edits: [EditSummary.Edit] = [
            .rewritten("Docker でコンテナを起動する。", "Podman でコンテナを起動する。"),
            .rewritten("先に Docker のイメージを取得しておく。", "先に Podman のイメージを取得しておく。"),
        ]
        #expect(EditSummary.ruleBasedSummary(of: edits, in: .japanese) == "「Docker」を「Podman」に変えた")
    }

    @Test func recognizesSmallFixes() {
        let edits: [EditSummary.Edit] = [
            .rewritten("キャッシュを削除します。", "キャッシュを消去します。"),
            .rewritten("設定は 1 行で書く事ができる。", "設定は 1 行で書くことができる。"),
        ]
        #expect(EditSummary.ruleBasedSummary(of: edits, in: .japanese) == "細かな表記を直した")
    }

    @Test func leavesRealRewritesToTheModel() {
        let edits: [EditSummary.Edit] = [.rewritten("この API は非推奨です。", "この API は v3 で削除されたため、代わりに fetch を使ってください。")]
        #expect(EditSummary.ruleBasedSummary(of: edits, in: .japanese) == nil)
        #expect(EditSummary.ruleBasedSummary(of: [.removed("a"), .rewritten("b", "c")], in: .english) == nil)
    }

    @Test func cleansUpTheModelOutput() {
        #expect(EditSummary.cleanUp("「キャッシュの仕組みを説明する節を追加した\n余計な行", in: .japanese) == "キャッシュの仕組みを説明する節を追加した")
        #expect(EditSummary.cleanUp("「npm install」の手順を書き直した。", in: .japanese) == "「npm install」の手順を書き直した")
    }

    @Test func detectsTheLanguage() {
        #expect(EditSummary.Language.detect(in: "Docker でコンテナを起動する。").code == .japanese)
        #expect(EditSummary.Language.detect(in: "Added a code sample.").code == .english)
        #expect(EditSummary.Language.detect(in: "Ajouté un exemple de code.").code == .english)
    }

    @Test func cleansUpEnglishToo() {
        #expect(EditSummary.cleanUp("\"Rewrote the install steps.", in: .english) == "Rewrote the install steps")
        #expect(EditSummary.cleanUp("Renamed \"npm\" to \"pnpm\".", in: .english) == "Renamed \"npm\" to \"pnpm\"")
    }

    @Test func shortensLongInput() {
        let edits = Array(repeating: EditSummary.Edit.added(String(repeating: "あ", count: 300)), count: 10)
        let input = EditSummary.modelInput(for: edits, in: .japanese)
        #expect(input.count <= 2100)
        #expect(input.hasSuffix("（ほか 4 件）"))
    }
}
