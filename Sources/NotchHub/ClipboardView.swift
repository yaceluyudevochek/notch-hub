import SwiftUI

struct ClipboardView: View {
    @ObservedObject var store: ClipboardStore
    @State private var copiedID: UUID?

    var body: some View {
        ZStack(alignment: .bottom) {
            if store.items.isEmpty {
                EmptyState(icon: "doc.on.clipboard", text: "Скопируйте что-нибудь — оно появится здесь")
            } else {
                RenderableScroll {
                    VStack(spacing: 4) {
                        ForEach(Array(store.items.prefix(Snapshot.isRendering ? 4 : .max).enumerated()), id: \.element.id) { index, item in
                            ClipRow(item: item, store: store, isCopied: copiedID == item.id) {
                                store.copy(item)
                                withAnimation(.spring(response: 0.3)) { copiedID = item.id }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    withAnimation { if copiedID == item.id { copiedID = nil } }
                                }
                            }
                            .staggered(index)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .scale(scale: 0.9).combined(with: .opacity)))
                        }
                    }
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: store.items.map(\.id))
                }
            }

            if copiedID != nil {
                CopiedToast().padding(.bottom, 4)
            }
        }
    }
}

private struct ClipRow: View {
    let item: ClipItem
    @ObservedObject var store: ClipboardStore
    let isCopied: Bool
    let onCopy: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            preview
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(theme.fg(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.fg(0.92))
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.fg(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if hovering {
                IconButton(systemName: "xmark", help: "Удалить") { store.delete(item) }
            } else if isCopied {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.fg(hovering ? 0.1 : 0.04))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .scaleEffect(isCopied ? 0.98 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isCopied)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture(perform: onCopy)
        .help("Нажмите, чтобы скопировать")
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .text:
            Image(systemName: looksLikeURL ? "link" : "text.alignleft")
                .font(.system(size: 13))
                .foregroundStyle(theme.fg(0.7))
        case .image:
            if let image = store.image(for: item) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo").foregroundStyle(theme.fg(0.7))
            }
        case .files:
            if let url = item.fileURLs?.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().padding(3)
            }
        }
    }

    private var looksLikeURL: Bool {
        guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return text.hasPrefix("http://") || text.hasPrefix("https://")
    }

    private var title: String {
        switch item.kind {
        case .text:
            return (item.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ⏎ ")
        case .image:
            if let size = store.image(for: item)?.size {
                return "Изображение \(Int(size.width))×\(Int(size.height))"
            }
            return "Изображение"
        case .files:
            let urls = item.fileURLs ?? []
            if urls.count == 1 { return urls[0].lastPathComponent }
            return "\(urls.first?.lastPathComponent ?? "") и ещё \(urls.count - 1)"
        }
    }

    private var subtitle: String {
        let time = RelativeDateTimeFormatter.shared.localizedString(for: item.date, relativeTo: Date())
        if let app = item.sourceApp { return "\(app) · \(time)" }
        return time
    }
}

extension RelativeDateTimeFormatter {
    static let shared: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .short
        return f
    }()
}
