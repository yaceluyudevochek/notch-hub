import SwiftUI

/// Палитра, которая следует системной теме. В свёрнутом виде «челка» всегда чёрная,
/// чтобы сливаться с аппаратным вырезом; раскрытая панель — в цветах темы.
struct Theme {
    let isDark: Bool

    var background: Color { isDark ? .black : Color(white: 0.965) }
    var primary: Color { isDark ? .white : .black }
    var shadow: Color { .black.opacity(isDark ? 0.5 : 0.22) }

    /// Цвет переднего плана с прозрачностью — тексты, иконки, подложки.
    func fg(_ opacity: Double) -> Color { primary.opacity(opacity) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(isDark: true)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Плавное появление элементов списка «лесенкой».
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var visible = Snapshot.isRendering

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 10)
            .scaleEffect(visible ? 1 : 0.97, anchor: .top)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)
                    .delay(Double(min(index, 12)) * 0.03)) {
                    visible = true
                }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}

/// ScrollView, который при отрисовке в PNG заменяется обычным контейнером:
/// ImageRenderer не рисует содержимое прокрутки.
struct RenderableScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if Snapshot.isRendering {
            content.frame(maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollView(.vertical, showsIndicators: false) { content }
        }
    }
}
