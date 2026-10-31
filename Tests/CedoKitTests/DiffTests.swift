import Testing

@testable import CedoKit

struct DiffTests {
    @Test func readsHunksWithoutHeaders() {
        let diff = Diff(
            parsing: """
                diff --git a/guide.md b/guide.md
                index e42d46d..cad913e 100644
                --- a/guide.md
                +++ b/guide.md
                @@ -3,2 +3,2 @@ intro
                 npm を使う。
                -キャッシュを削除します。
                +キャッシュを消去します。
                @@ -20,0 +21 @@
                +## 設定
                \\ No newline at end of file
                """)

        #expect(diff.hunks.map(\.line) == [3, 21])
        #expect(
            diff.hunks[0].lines == [
                .init(kind: .context, text: "npm を使う。"),
                .init(kind: .removed, text: "キャッシュを削除します。", changed: 6..<8),
                .init(kind: .added, text: "キャッシュを消去します。", changed: 6..<8),
            ])
        #expect(diff.hunks[1].lines == [.init(kind: .added, text: "## 設定")])
    }

    @Test func leavesWhollyDifferentLinesUnmarked() {
        let diff = Diff(parsing: "@@ -1 +1 @@\n-古い\n+新しい手順\n")

        #expect(diff.hunks[0].lines.map(\.changed) == [nil, nil])
    }

    @Test func pairsRemovedAndAddedLinesInOrder() {
        let diff = Diff(parsing: "@@ -1,2 +1,3 @@\n-a1\n-b1\n+a2\n+b2\n+c\n")

        #expect(diff.hunks[0].lines.map(\.changed) == [1..<2, 1..<2, 1..<2, 1..<2, nil])
    }
}
