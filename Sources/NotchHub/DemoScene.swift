import AppKit
import SwiftUI

// Картинки для README: панель поверх выдуманного рабочего стола с демо-данными.
extension Snapshot {
    private static let demoNotch = CGSize(width: 186, height: 32)

    @MainActor
    static func renderDemo(to dir: URL, clipboard: ClipboardStore,
                           screenshots: ScreenshotStore, nowPlaying: NowPlayingStore) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        isRendering = true
        loadDemoData(clipboard: clipboard, screenshots: screenshots, nowPlaying: nowPlaying)

        let shots: [(String, NotchViewModel.Tab?, ColorScheme)] = [
            ("media-dark", .media, .dark),
            ("media-light", .media, .light),
            ("clipboard-dark", .clipboard, .dark),
            ("clipboard-light", .clipboard, .light),
            ("screenshots-dark", .screenshots, .dark),
            ("screenshots-light", .screenshots, .light),
            ("collapsed-dark", nil, .dark),
            ("collapsed-light", nil, .light),
        ]

        for (name, tab, scheme) in shots {
            let model = NotchViewModel()
            model.notchSize = demoNotch
            if let tab {
                model.isExpanded = true
                model.selectedTab = tab
            } else {
                model.hasActivity = true
            }
            let scene = DemoScene(model: model, clipboard: clipboard, screenshots: screenshots,
                                  nowPlaying: nowPlaying, compact: tab == nil)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: scene)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
        }
    }

    @MainActor
    private static func loadDemoData(clipboard: ClipboardStore, screenshots: ScreenshotStore,
                                     nowPlaying: NowPlayingStore) {
        let now = Date()
        let cover = drawImage(size: CGSize(width: 600, height: 600)) { r in
            NSGradient(colors: [.systemIndigo, .systemPink, .systemOrange])!.draw(in: r, angle: -45)
            for (i, alpha) in [0.5, 0.35, 0.2].enumerated() {
                let d = r.width * (0.75 - CGFloat(i) * 0.2)
                NSColor.white.withAlphaComponent(alpha).setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(x: r.midX - d / 2, y: r.midY - d / 2 - r.height * 0.08, width: d, height: d))
                ring.lineWidth = r.width * 0.02
                ring.stroke()
            }
            NSColor.black.withAlphaComponent(0.85).setFill()
            NSBezierPath(rect: NSRect(x: 0, y: r.height * 0.78, width: r.width, height: 3)).fill()
        }
        let safari = NSWorkspace.shared.icon(forFile: "/Applications/Safari.app")
        nowPlaying.loadDemo(NowPlaying(
            title: "Midnight Drive", artist: "Neon Coast", album: "Afterglow",
            duration: 214, elapsed: 83, timestamp: now, rate: 1, isPlaying: true,
            appName: "Safari", appIcon: safari, bundleID: "com.apple.Safari"
        ), artwork: cover)

        let photo = drawImage(size: CGSize(width: 800, height: 500)) { r in
            NSGradient(colors: [.systemTeal, .systemBlue])!.draw(in: r, angle: 90)
            NSColor.white.withAlphaComponent(0.8).setFill()
            NSBezierPath(ovalIn: NSRect(x: r.width * 0.7, y: r.height * 0.6, width: 90, height: 90)).fill()
        }
        clipboard.loadDemo([
            ClipItem(kind: .text, text: "Созвон с командой в 15:00, ссылка в календаре", date: now.addingTimeInterval(-20), sourceApp: "Заметки"),
            ClipItem(kind: .text, text: "https://github.com/topics/macos-notch", date: now.addingTimeInterval(-300), sourceApp: "Safari"),
            ClipItem(kind: .image, imageFile: "demo-photo", date: now.addingTimeInterval(-900), sourceApp: "Фото"),
            ClipItem(kind: .text, text: "let notch = NSScreen.main?.safeAreaInsets.top ?? 0", date: now.addingTimeInterval(-2400), sourceApp: "Xcode"),
            ClipItem(kind: .files, fileURLs: [URL(fileURLWithPath: "/System/Applications/Notes.app")], date: now.addingTimeInterval(-7200), sourceApp: "Finder"),
        ], images: ["demo-photo": photo])

        let palettes: [[NSColor]] = [
            [.systemPurple, .systemBlue], [.systemOrange, .systemRed], [.systemGreen, .systemTeal],
            [.systemPink, .systemPurple], [.systemBlue, .systemCyan], [.systemYellow, .systemOrange],
            [.systemIndigo, .systemTeal], [.systemGray, .darkGray],
        ]
        let demoShots = palettes.enumerated().map { i, colors -> (Screenshot, NSImage) in
            let image = drawImage(size: CGSize(width: 520, height: 340)) { r in
                NSGradient(colors: colors)!.draw(in: r, angle: -30)
                // «Окно» приложения на скриншоте
                let win = r.insetBy(dx: r.width * 0.14, dy: r.height * 0.16)
                NSColor.white.withAlphaComponent(0.92).setFill()
                NSBezierPath(roundedRect: win, xRadius: 14, yRadius: 14).fill()
                NSColor.black.withAlphaComponent(0.08).setFill()
                NSBezierPath(rect: NSRect(x: win.minX, y: win.maxY - 34, width: win.width, height: 34)).fill()
                for (j, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                    c.setFill()
                    NSBezierPath(ovalIn: NSRect(x: win.minX + 14 + CGFloat(j) * 20, y: win.maxY - 23, width: 12, height: 12)).fill()
                }
                for line in 0..<4 {
                    NSColor.black.withAlphaComponent(0.1).setFill()
                    let w = win.width * [0.7, 0.5, 0.62, 0.4][line]
                    NSBezierPath(roundedRect: NSRect(x: win.minX + 20, y: win.maxY - 70 - CGFloat(line) * 26, width: w, height: 12),
                                 xRadius: 6, yRadius: 6).fill()
                }
            }
            let shot = Screenshot(url: URL(fileURLWithPath: "/demo/shot-\(i).png"),
                                  date: now.addingTimeInterval(-Double(i * i + 1) * 240))
            return (shot, image)
        }
        screenshots.loadDemo(demoShots)
    }

    private static func drawImage(size: CGSize, draw: @escaping (CGRect) -> Void) -> NSImage {
        NSImage(size: size, flipped: false) { r in draw(r); return true }
    }
}

/// Выдуманный рабочий стол: обои, строка меню и аппаратная «челка».
private struct DemoScene: View {
    @ObservedObject var model: NotchViewModel
    let clipboard: ClipboardStore
    let screenshots: ScreenshotStore
    let nowPlaying: NowPlayingStore
    let compact: Bool
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.10, green: 0.09, blue: 0.22), Color(red: 0.32, green: 0.13, blue: 0.36), Color(red: 0.10, green: 0.20, blue: 0.35)]
                    : [Color(red: 0.80, green: 0.86, blue: 1.0), Color(red: 0.98, green: 0.84, blue: 0.90), Color(red: 1.0, green: 0.93, blue: 0.82)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            menuBar

            NotchRootView(model: model, clipboard: clipboard, screenshots: screenshots, nowPlaying: nowPlaying)
                .frame(height: NotchViewModel.expandedSize.height + 30)

            // Аппаратный вырез экрана.
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10)
                .fill(Color.black)
                .frame(width: model.notchSize.width - 8, height: model.notchSize.height)
        }
        .frame(width: compact ? 760 : 1000, height: compact ? 120 : 380, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var menuBar: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo").font(.system(size: 14, weight: .semibold))
            Text("Finder").fontWeight(.bold)
            Text("Файл")
            Text("Правка")
            Text("Вид")
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Пн 19 окт.  16:50")
        }
        .font(.system(size: 13))
        .foregroundStyle(dark ? Color.white : Color.black)
        .padding(.horizontal, 18)
        .frame(height: model.notchSize.height)
        .background(dark ? Color.black.opacity(0.25) : Color.white.opacity(0.35))
    }
}
