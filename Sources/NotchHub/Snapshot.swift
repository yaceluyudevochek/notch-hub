import AppKit
import SwiftUI

/// Отладочный режим: `NotchHub --snapshot <папка>` рисует раскрытую панель во всех вкладках
/// и в обеих темах в PNG, а затем завершает приложение. Не требует доступа к записи экрана.
enum Snapshot {
    static var outputDir: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    /// `--demo` — выдуманные данные и «рабочий стол» вокруг, для картинок в README.
    /// Во время отрисовки в PNG анимации появления отключены — рендер берёт первый кадр.
    static var isRendering = false

    static var isDemo: Bool { CommandLine.arguments.contains("--demo") }

    @MainActor
    static func render(to dir: URL, clipboard: ClipboardStore, screenshots: ScreenshotStore, nowPlaying: NowPlayingStore) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        isRendering = true
        let notch = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            .map(NotchWindowController.notchSize(on:)) ?? CGSize(width: 190, height: 32)

        for scheme in [ColorScheme.dark, .light] {
            var states: [(String, NotchViewModel)] = NotchViewModel.Tab.allCases.map { tab in
                let model = NotchViewModel()
                model.notchSize = notch
                model.isExpanded = true
                model.selectedTab = tab
                return ("\(tab)", model)
            }
            let collapsed = NotchViewModel()
            collapsed.notchSize = notch
            collapsed.hasActivity = nowPlaying.isActive
            states.append(("collapsed", collapsed))

            for (name, model) in states {
                let view = NotchRootView(model: model, clipboard: clipboard,
                                         screenshots: screenshots, nowPlaying: nowPlaying)
                    .frame(width: NotchViewModel.expandedSize.width + 48,
                           height: NotchViewModel.expandedSize.height + 24)
                    .background(scheme == .dark ? Color(white: 0.25) : Color(white: 0.85))
                    .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                let file = dir.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png")
                try? png.write(to: file)
            }
        }
    }
}
