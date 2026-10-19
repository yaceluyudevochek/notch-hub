import AppKit
import SwiftUI
import Combine

/// Состояние «челки»: размер аппаратного выреза, раскрыта ли панель, активная вкладка.
final class NotchViewModel: ObservableObject {
    enum Tab: Int, CaseIterable, Identifiable {
        case media, clipboard, screenshots
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .media: return "Сейчас играет"
            case .clipboard: return "Буфер обмена"
            case .screenshots: return "Скриншоты"
            }
        }
        var icon: String {
            switch self {
            case .media: return "play.circle.fill"
            case .clipboard: return "doc.on.clipboard"
            case .screenshots: return "camera.viewfinder"
            }
        }
    }

    @Published var isExpanded = false
    @Published var notchSize = CGSize(width: 200, height: 32)
    @Published var selectedTab: Tab = .clipboard
    /// Играет медиа — по бокам свёрнутой «челки» видны обложка и эквалайзер.
    @Published var hasActivity = false
    /// Направление перехода между вкладками (влево/вправо).
    @Published private(set) var tabTransition: AnyTransition = .opacity

    static let expandedSize = CGSize(width: 700, height: 280)
    static let activityWing: CGFloat = 38

    var collapsedSize: CGSize {
        CGSize(width: notchSize.width - 4 + (hasActivity ? Self.activityWing * 2 : 0),
               height: notchSize.height)
    }

    func select(_ tab: Tab) {
        guard tab != selectedTab else { return }
        let forward = tab.rawValue > selectedTab.rawValue
        tabTransition = .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { selectedTab = tab }
    }
}

/// Прозрачная панель поверх строки меню. Не активирует приложение и не крадёт фокус.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Не даём системе сдвигать окно ниже строки меню.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class NotchWindowController {
    private let panel: NotchPanel
    private let model = NotchViewModel()
    private var mouseTimer: Timer?
    private var outsideSince: Date?
    private var insideSince: Date?
    private var cancellables = Set<AnyCancellable>()
    private let nowPlaying: NowPlayingStore
    private var lastAutoShownTitle: String?

    /// Отступ под тень вокруг раскрытой панели.
    private let shadowPadding: CGFloat = 24

    init(clipboard: ClipboardStore, screenshots: ScreenshotStore, nowPlaying: NowPlayingStore) {
        self.nowPlaying = nowPlaying
        panel = NotchPanel(contentRect: .zero)
        let root = NotchRootView(model: model, clipboard: clipboard,
                                 screenshots: screenshots, nowPlaying: nowPlaying)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        reposition()

        nowPlaying.$current
            .map { $0?.isPlaying == true }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in self?.model.hasActivity = playing }
            .store(in: &cancellables)
    }

    func show() {
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = true
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.trackMouse()
        }
        RunLoop.main.add(mouseTimer!, forMode: .common)
    }

    /// Экран со «челкой» (или основной, если такого нет).
    private var targetScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    func reposition() {
        guard let screen = targetScreen else { return }
        model.notchSize = Self.notchSize(on: screen)

        let size = NotchViewModel.expandedSize
        let width = size.width + shadowPadding * 2
        let height = size.height + shadowPadding
        let frame = NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
    }

    static func notchSize(on screen: NSScreen) -> CGSize {
        let top = screen.safeAreaInsets.top
        if top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            return CGSize(width: width, height: top)
        }
        // Нет выреза — имитируем «челку» по высоте строки меню.
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(width: 190, height: max(menuBar, 24))
    }

    // MARK: - Наведение мыши

    private func trackMouse() {
        guard let screen = targetScreen else { return }
        let mouse = NSEvent.mouseLocation
        let notch = model.notchSize

        if model.isExpanded {
            let size = NotchViewModel.expandedSize
            let area = NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            ).insetBy(dx: -12, dy: -12)

            // Пока зажата кнопка мыши (например, тащим скриншот наружу) — не закрываем.
            if area.contains(mouse) || NSEvent.pressedMouseButtons != 0 {
                outsideSince = nil
            } else if let since = outsideSince {
                if Date().timeIntervalSince(since) > 0.25 { setExpanded(false) }
            } else {
                outsideSince = Date()
            }
        } else {
            let collapsed = model.collapsedSize
            let hot = NSRect(
                x: screen.frame.midX - collapsed.width / 2,
                y: screen.frame.maxY - notch.height,
                width: collapsed.width,
                height: notch.height + 1
            ).insetBy(dx: -6, dy: 0)

            if hot.contains(mouse), NSEvent.pressedMouseButtons == 0 {
                if let since = insideSince {
                    if Date().timeIntervalSince(since) > 0.08 { setExpanded(true) }
                } else {
                    insideSince = Date()
                }
            } else {
                insideSince = nil
            }
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard model.isExpanded != expanded else { return }
        outsideSince = nil
        insideSince = nil
        panel.ignoresMouseEvents = !expanded
        if expanded {
            // Новый трек с момента прошлого раскрытия — сразу показываем плеер.
            if let title = nowPlaying.current?.title, nowPlaying.isActive, title != lastAutoShownTitle {
                lastAutoShownTitle = title
                model.selectedTab = .media
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        withAnimation(expanded ? .spring(response: 0.42, dampingFraction: 0.74) : .spring(response: 0.34, dampingFraction: 0.9)) {
            model.isExpanded = expanded
        }
    }
}
