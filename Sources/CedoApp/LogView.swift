import CedoKit
import SwiftUI

struct LogView: View {
    let log: DebugLog

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(log.entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.date, format: .dateTime.hour().minute().second())
                                .foregroundStyle(Theme.muted)
                            Text(entry.message)
                                .foregroundStyle(entry.isError ? Theme.danger : Theme.text)
                        }
                        .id(entry.id)
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
            }
            .onAppear { scrollToEnd(proxy) }
            .onChange(of: log.entries.last?.id) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        if let id = log.entries.last?.id {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}
