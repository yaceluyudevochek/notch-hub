import AppKit

struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var isPlaying: Bool
    var appName: String
    var appIcon: NSImage?
    var bundleID: String?

    /// Текущая позиция с учётом времени, прошедшего с последнего обновления.
    func position(at date: Date = Date()) -> Double {
        guard isPlaying else { return elapsed }
        let value = elapsed + date.timeIntervalSince(timestamp) * max(rate, 1)
        return duration > 0 ? min(value, duration) : value
    }

    /// Подпись для браузерных источников: YouTube, SoundCloud и т.д. обычно пишут сайт в artist/album.
    var subtitle: String {
        [artist, album].first { !$0.isEmpty } ?? appName
    }
}

/// Получает «Сейчас играет» из MediaRemote через помощника, запущенного в /usr/bin/perl.
final class NowPlayingStore: ObservableObject {
    @Published private(set) var current: NowPlaying?
    @Published private(set) var artwork: NSImage?

    private var process: Process?
    private var buffer = Data()
    private var artworkHash: Int?
    private var restartWork: DispatchWorkItem?

    private var resources: URL { Bundle.main.resourceURL ?? URL(fileURLWithPath: ".") }
    private var dylib: URL { resources.appendingPathComponent("libNowPlaying.dylib") }
    private var script: URL { resources.appendingPathComponent("NowPlaying.pl") }

    var isActive: Bool { current?.isPlaying == true }

    func start() {
        guard FileManager.default.fileExists(atPath: dylib.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, dylib.path, "stream"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        // Помощник упал — перезапускаем через пару секунд.
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleRestart() }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            scheduleRestart()
        }
    }

    func stop() {
        restartWork?.cancel()
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    private func scheduleRestart() {
        restartWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.start() }
        restartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    // MARK: - Разбор JSON-строк

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                apply(json)
            }
        }
    }

    private func apply(_ json: [String: Any]) {
        let title = json["Title"] as? String ?? ""
        guard !title.isEmpty else {
            if current != nil { current = nil; artwork = nil; artworkHash = nil }
            return
        }

        let pid = json["pid"] as? Int ?? 0
        let app = NSRunningApplication(processIdentifier: pid_t(pid))
        let rate = json["PlaybackRate"] as? Double ?? 0
        let playing = (json["playing"] as? Bool ?? false) || rate > 0

        let info = NowPlaying(
            title: title,
            artist: json["Artist"] as? String ?? "",
            album: json["Album"] as? String ?? "",
            duration: json["Duration"] as? Double ?? 0,
            elapsed: json["ElapsedTime"] as? Double ?? 0,
            timestamp: (json["Timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) } ?? Date(),
            rate: rate,
            isPlaying: playing,
            appName: app?.localizedName ?? "Медиа",
            appIcon: app?.icon,
            bundleID: app?.bundleIdentifier
        )
        if info != current { current = info }

        let hash = json["ArtworkHash"] as? Int
        if hash == nil {
            if artwork != nil { artwork = nil }
            artworkHash = nil
        } else if hash != artworkHash, let base64 = json["Artwork"] as? String,
                  let data = Data(base64Encoded: base64) {
            artworkHash = hash
            artwork = NSImage(data: data)
        }
    }

    // MARK: - Управление

    func togglePlayPause() {
        send("toggle")
        // Оптимистично переключаем, не дожидаясь следующего опроса.
        if var info = current {
            info.elapsed = info.position()
            info.timestamp = Date()
            info.isPlaying.toggle()
            current = info
        }
    }

    func next() { send("next") }
    func previous() { send("previous") }

    func seek(to seconds: Double) {
        send("seek:\(seconds)")
        if var info = current {
            info.elapsed = seconds
            info.timestamp = Date()
            current = info
        }
    }

    func openSourceApp() {
        guard let id = current?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func send(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, dylib.path, "send"]
        process.environment = ["NH_CMD": command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}

extension NowPlayingStore {
    /// Подменяет трек демо-данными (только для `--snapshot --demo`).
    func loadDemo(_ info: NowPlaying, artwork: NSImage?) {
        current = info
        self.artwork = artwork
    }
}
