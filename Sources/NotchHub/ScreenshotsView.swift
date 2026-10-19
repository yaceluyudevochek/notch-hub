import SwiftUI
import UniformTypeIdentifiers

struct ScreenshotsView: View {
    @ObservedObject var store: ScreenshotStore
    @State private var showCopied = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ZStack(alignment: .bottom) {
            if store.items.isEmpty {
                EmptyState(icon: "camera.viewfinder", text: "Скриншотов пока нет — нажмите ⇧⌘4")
            } else {
                RenderableScroll {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(store.items.enumerated()), id: \.element.id) { index, shot in
                            ScreenshotCell(shot: shot, store: store) {
                                store.copy(shot)
                                withAnimation(.spring(response: 0.3)) { showCopied = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    withAnimation { showCopied = false }
                                }
                            }
                            .staggered(index)
                        }
                    }
                    .padding(4)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.items.map(\.id))
                }
            }

            if showCopied {
                CopiedToast().padding(.bottom, 4)
            }
        }
    }
}

private struct ScreenshotCell: View {
    let shot: Screenshot
    @ObservedObject var store: ScreenshotStore
    let onCopy: () -> Void
    @Environment(\.theme) private var theme
    @State private var image: NSImage?

    init(shot: Screenshot, store: ScreenshotStore, onCopy: @escaping () -> Void) {
        self.shot = shot
        self.store = store
        self.onCopy = onCopy
        _image = State(initialValue: store.cachedThumbnail(for: shot))
    }
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                theme.fg(0.06)
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 92)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.fg(hovering ? 0.5 : 0.1), lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) {
                Text(RelativeDateTimeFormatter.shared.localizedString(for: shot.date, relativeTo: Date()))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .padding(5)
            }

            if hovering {
                HStack(spacing: 4) {
                    IconButton(systemName: "doc.on.doc", help: "Скопировать", action: onCopy)
                    IconButton(systemName: "magnifyingglass", help: "Показать в Finder") { store.revealInFinder(shot) }
                }
                .padding(5)
                .transition(.opacity)
            }
        }
        .scaleEffect(hovering ? 1.04 : 1)
        .shadow(color: .black.opacity(hovering ? 0.3 : 0), radius: 8, y: 4)
        .zIndex(hovering ? 1 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { h in withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { hovering = h } }
        .onTapGesture(count: 1) { store.open(shot) }
        // Перетаскивание скриншота в любое приложение (Telegram, Finder, браузер…)
        .onDrag { NSItemProvider(contentsOf: shot.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Открыть") { store.open(shot) }
            Button("Скопировать", action: onCopy)
            Button("Показать в Finder") { store.revealInFinder(shot) }
            Divider()
            Button("Переместить в Корзину") { store.moveToTrash(shot) }
        }
        .help(shot.url.lastPathComponent)
        .onAppear {
            store.thumbnail(for: shot) { img in withAnimation(.easeOut(duration: 0.25)) { image = img } }
        }
    }
}
