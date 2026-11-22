import Foundation
import Testing

@testable import CedoKit

struct MarkdownSyntaxTests {
    @Test func appliesToMarkdownFiles() {
        #expect(MarkdownSyntax.applies(to: URL(fileURLWithPath: "/docs/セットアップ.md")))
        #expect(MarkdownSyntax.applies(to: URL(fileURLWithPath: "/docs/README.Markdown")))
        #expect(!MarkdownSyntax.applies(to: URL(fileURLWithPath: "/docs/CHANGELOG.txt")))
    }

    @Test func stylesBlocks() {
        let text = """
            # インストール
            ####### 7 つは見出しではない
            #タグ
            > macOS 14 以降が必要です
            - Homebrew で入れる
              2. `make install` を実行する
            ---
            * * *
            -v はリストではない
            """

        #expect(
            styled(text) == [
                .init("# インストール", .heading),
                .init("> macOS 14 以降が必要です", .quote),
                .init("-", .marker),
                .init("2.", .marker),
                .init("---", .marker),
                .init("* * *", .marker),
                .init("`make install`", .code),
            ])
    }

    @Test func stylesInlines() {
        let text =
            "設定は**必ず**保存する。*任意* の項目と _既定値_ は省略できる。MAX_RETRY_COUNT や 2*3*4 は強調ではない。詳しくは [API リファレンス](https://example.com/api \"API\") か <https://example.org/docs> を参照。"

        #expect(
            styled(text) == [
                .init("**必ず**", .emphasis),
                .init("*任意*", .emphasis),
                .init("_既定値_", .emphasis),
                .init("[API リファレンス]", .link),
                .init(#"(https://example.com/api "API")"#, .url),
                .init("<https://example.org/docs>", .url),
            ])
    }

    @Test func leavesCodeUnstyledInside() {
        let text = """
            `**kwargs` と ``a ` b`` はコード
            ```sh
            # brew の場合
            echo `date`
            ```
            # 使い方
            ~~~
            - 閉じていないコードブロックは最後まで続く
            """

        #expect(
            styled(text) == [
                .init("# 使い方", .heading),
                .init("`**kwargs`", .code),
                .init("``a ` b``", .code),
                .init("```sh\n# brew の場合\necho `date`\n```", .code),
                .init("~~~\n- 閉じていないコードブロックは最後まで続く", .code),
            ])
    }

    private struct Styled: Equatable, CustomStringConvertible {
        let text: String
        let style: MarkdownSyntax.Style

        init(_ text: String, _ style: MarkdownSyntax.Style) {
            self.text = text
            self.style = style
        }

        var description: String { "\(style): \(text.debugDescription)" }
    }

    private func styled(_ text: String) -> [Styled] {
        MarkdownSyntax.spans(in: text).map { span in
            Styled((text as NSString).substring(with: span.range), span.style)
        }
    }
}
