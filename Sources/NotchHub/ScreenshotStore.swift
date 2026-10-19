import AppKit
import QuickLookThumbnailing

struct Screenshot: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let date: Date
}

/// Находит недавние скриншоты: через Spotlight (kMDItemIsScreenCapture) и сканированием
/// папки, куда macOS сохраняет снимки. Обновляется автоматически.
final class ScreenshotStore: ObservableObject {
    @Published private(set) var items: [Screenshot] = []

    private let limit = 40
    private let query = NSMetadataQuery()
    private var folderWatcher: DispatchSourceFileSystemObject?
    private var thumbnails: [URL: NSImage] = [:]
    /// Работа с файлами — в фоне: первый доступ к «Рабочему столу» ждёт ответа на запрос
    /// приватности macOS, и на главном потоке это замораживало бы всё приложение.
    private let fileQueue = DispatchQueue(label: "notchhub.screenshots", qos: .utility)

    /// Папка из настроек «Снимок экрана» (по умолчанию — Рабочий стол).
    var screenshotFolder: URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location") {
            let expanded = (path as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    func start() {
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: .NSMetadataQueryDidFinishGathering, object: query)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: .NSMetadataQueryDidUpdate, object: query)
        query.start()

        let folder = screenshotFolder
        fileQueue.async { [weak self] in self?.watchFolder(folder) }
        refresh()
    }

    @objc func refresh() {
        var found: [URL: Date] = [:]
        let folder = screenshotFolder

        query.disableUpdates()
        for case let item as NSMetadataItem in query.results.prefix(limit) {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
            let date = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? .distantPast
            found[URL(fileURLWithPath: path)] = date
        }
        query.enableUpdates()

        // Spotlight может отставать или быть выключен — дополняем сканированием папки.
        let limit = self.limit
        fileQueue.async { [weak self] in
            for (url, date) in Self.scanFolder(folder) { found[url] = date }
            let list = Array(found
                .filter { FileManager.default.fileExists(atPath: $0.key.path) }
                .map { Screenshot(url: $0.key, date: $0.value) }
                .sorted { $0.date > $1.date }
                .prefix(limit))
            DispatchQueue.main.async {
                guard let self, list != self.items else { return }
                self.items = list
            }
        }
    }

    private static func scanFolder(_ folder: URL) -> [(URL, Date)] {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        let exts: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "pdf", "mov"]
        return urls.compactMap { url in
            guard exts.contains(url.pathExtension.lowercased()), Self.isScreenCapture(url) else { return nil }
            let date = (try? url.resourceValues(forKeys: Set(keys)).creationDate) ?? .distantPast
            return (url, date)
        }
    }

    /// macOS помечает снимки экрана расширенным атрибутом kMDItemIsScreenCapture.
    private static func isScreenCapture(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }

    private func watchFolder(_ folder: URL) {
        let fd = Darwin.open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            // Даём системе дописать файл и атрибуты.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.refresh() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        DispatchQueue.main.async { [weak self] in self?.folderWatcher = source }
    }

    // MARK: - Действия

    func thumbnail(for shot: Screenshot, completion: @escaping (NSImage) -> Void) {
        if let cached = thumbnails[shot.url] { completion(cached); return }
        let request = QLThumbnailGenerator.Request(
            fileAt: shot.url, size: CGSize(width: 260, height: 170),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            guard let image = rep?.nsImage else { return }
            DispatchQueue.main.async {
                self?.thumbnails[shot.url] = image
                completion(image)
            }
        }
    }

    func open(_ shot: Screenshot) {
        NSWorkspace.shared.open(shot.url)
    }

    func copy(_ shot: Screenshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let image = NSImage(contentsOf: shot.url) {
            pb.writeObjects([shot.url as NSURL, image])
        } else {
            pb.writeObjects([shot.url as NSURL])
        }
    }

    func revealInFinder(_ shot: Screenshot) {
        NSWorkspace.shared.activateFileViewerSelecting([shot.url])
    }

    func moveToTrash(_ shot: Screenshot) {
        NSWorkspace.shared.recycle([shot.url]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.thumbnails[shot.url] = nil
                self?.refresh()
            }
        }
    }

    func openFolder() {
        NSWorkspace.shared.open(screenshotFolder)
    }
}

extension ScreenshotStore {
    func cachedThumbnail(for shot: Screenshot) -> NSImage? { thumbnails[shot.url] }

    /// Подменяет список демо-данными (только для `--snapshot --demo`).
    func loadDemo(_ demo: [(Screenshot, NSImage)]) {
        for (shot, image) in demo { thumbnails[shot.url] = image }
        items = demo.map(\.0)
    }
}
