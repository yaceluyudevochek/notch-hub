import SwiftUI

/// Форма «челки»: вогнутые «ушки» сверху и скруглённые углы снизу.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = topRadius, b = bottomRadius
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var screenshots: ScreenshotStore
    @ObservedObject var nowPlaying: NowPlayingStore
    @Environment(\.colorScheme) private var scheme

    private var theme: Theme { Theme(isDark: scheme == .dark) }

    var body: some View {
        let expanded = model.isExpanded
        let size = expanded ? NotchViewModel.expandedSize : model.collapsedSize

        ZStack(alignment: .top) {
            NotchShape(topRadius: expanded ? 16 : 0, bottomRadius: expanded ? 26 : 9)
                .fill(expanded ? theme.background : Color.black)
                .overlay(
                    NotchShape(topRadius: expanded ? 16 : 0, bottomRadius: expanded ? 26 : 9)
                        .stroke(theme.fg(expanded && !theme.isDark ? 0.08 : 0), lineWidth: 1)
                )
                .shadow(color: expanded ? theme.shadow : .clear, radius: 18, y: 8)

            if expanded {
                ExpandedContent(model: model, clipboard: clipboard,
                                screenshots: screenshots, nowPlaying: nowPlaying)
                    .padding(.horizontal, 16 + 12)
                    .padding(.bottom, 16)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .top))
                                .animation(.spring(response: 0.42, dampingFraction: 0.8).delay(0.05)),
                            removal: .opacity.animation(.easeOut(duration: 0.12))
                        )
                    )
            } else if model.hasActivity {
                LiveActivityView(nowPlaying: nowPlaying, notchWidth: model.notchSize.width)
                    .frame(height: model.notchSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.theme, theme)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: model.hasActivity)
        .animation(.easeInOut(duration: 0.3), value: scheme)
    }
}

// MARK: - Свёрнутый режим: «живая активность» вокруг выреза

private struct LiveActivityView: View {
    @ObservedObject var nowPlaying: NowPlayingStore
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let art = nowPlaying.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else if let icon = nowPlaying.current?.appIcon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "music.note").foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .frame(maxWidth: .infinity)

            Color.clear.frame(width: notchWidth)

            EqualizerBars(isPlaying: nowPlaying.isActive)
                .frame(width: 18, height: 14)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Анимированный эквалайзер. Анимацию крутит Core Animation в системном рендер-сервере,
/// поэтому во время воспроизведения приложение не перерисовывает SwiftUI каждый кадр.
struct EqualizerBars: View {
    let isPlaying: Bool
    var color: NSColor = .white
    var count = 4

    var body: some View {
        if Snapshot.isRendering {
            // ImageRenderer не рисует NSView — для картинок статичный кадр.
            GeometryReader { geo in
                HStack(spacing: geo.size.width * 0.12) {
                    ForEach(0..<count, id: \.self) { i in
                        Capsule().fill(Color(nsColor: color))
                            .frame(height: geo.size.height * [0.55, 1, 0.4, 0.75][i % 4])
                            .frame(maxHeight: .infinity)
                    }
                }
            }
        } else {
            EqualizerLayerView(isPlaying: isPlaying, color: color, count: count)
        }
    }
}

private struct EqualizerLayerView: NSViewRepresentable {
    let isPlaying: Bool
    let color: NSColor
    let count: Int

    func makeNSView(context: Context) -> EqualizerNSView {
        EqualizerNSView(count: count, color: color)
    }

    func updateNSView(_ view: EqualizerNSView, context: Context) {
        view.setPlaying(isPlaying)
    }
}

final class EqualizerNSView: NSView {
    private var bars: [CALayer] = []
    private var playing = false
    private let durations: [CFTimeInterval] = [0.42, 0.55, 0.37, 0.49, 0.6]

    init(count: Int, color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        for _ in 0..<count {
            let bar = CALayer()
            bar.backgroundColor = color.cgColor
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let gap = bounds.width * 0.12
        let w = (bounds.width - gap * CGFloat(bars.count - 1)) / CGFloat(bars.count)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            bar.position = CGPoint(x: CGFloat(i) * (w + gap) + w / 2, y: bounds.midY)
            bar.cornerRadius = w / 2
        }
        CATransaction.commit()
        applyAnimations()
    }

    func setPlaying(_ value: Bool) {
        guard value != playing else { return }
        playing = value
        applyAnimations()
    }

    private func applyAnimations() {
        for (i, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "bounce")
            let rest: CGFloat = 0.18
            if playing {
                let anim = CABasicAnimation(keyPath: "transform.scale.y")
                anim.fromValue = 0.25
                anim.toValue = 1.0
                anim.duration = durations[i % durations.count]
                anim.autoreverses = true
                anim.repeatCount = .infinity
                anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                anim.timeOffset = Double(i) * 0.17
                bar.transform = CATransform3DMakeScale(1, 0.6, 1)
                bar.add(anim, forKey: "bounce")
            } else {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.3)
                bar.transform = CATransform3DMakeScale(1, rest, 1)
                CATransaction.commit()
            }
        }
    }
}

// MARK: - Раскрытый режим

private struct ExpandedContent: View {
    @ObservedObject var model: NotchViewModel
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var screenshots: ScreenshotStore
    @ObservedObject var nowPlaying: NowPlayingStore
    @Environment(\.theme) private var theme
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 10) {
            // Верхняя строка живёт по бокам аппаратного выреза.
            HStack(spacing: 0) {
                HStack(spacing: 3) {
                    ForEach(NotchViewModel.Tab.allCases) { tab in
                        TabButton(tab: tab, isSelected: model.selectedTab == tab, namespace: tabNamespace) {
                            model.select(tab)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: model.notchSize.width)

                HStack(spacing: 8) {
                    trailingAccessory
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: max(model.notchSize.height, 28))

            ZStack {
                switch model.selectedTab {
                case .media:
                    NowPlayingView(store: nowPlaying).transition(model.tabTransition)
                case .clipboard:
                    ClipboardView(store: clipboard).transition(model.tabTransition)
                case .screenshots:
                    ScreenshotsView(store: screenshots).transition(model.tabTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    @ViewBuilder private var trailingAccessory: some View {
        switch model.selectedTab {
        case .media:
            if let info = nowPlaying.current {
                HStack(spacing: 5) {
                    if let icon = info.appIcon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(info.appName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.fg(0.5))
                        .lineLimit(1)
                }
            }
        case .clipboard:
            counter(clipboard.items.count)
            if !clipboard.items.isEmpty {
                IconButton(systemName: "trash", help: "Очистить историю") {
                    withAnimation(.spring(response: 0.35)) { clipboard.clear() }
                }
            }
        case .screenshots:
            counter(screenshots.items.count)
            IconButton(systemName: "folder", help: "Открыть папку скриншотов") { screenshots.openFolder() }
        }
    }

    private func counter(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(theme.fg(0.45))
            .contentTransition(.numericText(value: Double(value)))
            .animation(.snappy, value: value)
    }
}

private struct TabButton: View {
    let tab: NotchViewModel.Tab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .symbolEffect(.bounce, value: isSelected)
                if isSelected {
                    Text(tab.title)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, isSelected ? 11 : 8)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? theme.background : theme.fg(hovering ? 0.95 : 0.6))
            .background {
                if isSelected {
                    Capsule().fill(theme.primary)
                        .matchedGeometryEffect(id: "tab", in: namespace)
                } else if hovering {
                    Capsule().fill(theme.fg(0.1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}

// MARK: - Общие элементы

struct IconButton: View {
    let systemName: String
    var help: String = ""
    var size: CGFloat = 24
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(theme.fg(hovering ? 1 : 0.6))
                .frame(width: size, height: size)
                .background(Circle().fill(theme.fg(hovering ? 0.15 : 0.06)))
                .scaleEffect(hovering ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .onHover { h in withAnimation(.spring(response: 0.25)) { hovering = h } }
    }
}

/// Лёгкое «вдавливание» кнопок при нажатии.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Короткое «Скопировано» поверх контента.
struct CopiedToast: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Label("Скопировано", systemImage: "checkmark.circle.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(theme.background)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(theme.primary))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.8)))
    }
}

struct EmptyState: View {
    let icon: String
    let text: String
    @Environment(\.theme) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundStyle(theme.fg(0.3))
                .symbolEffect(.bounce, value: appeared)
            Text(text).font(.system(size: 12)).foregroundStyle(theme.fg(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appeared = true }
    }
}
