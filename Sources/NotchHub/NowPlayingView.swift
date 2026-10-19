import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var store: NowPlayingStore
    @Environment(\.theme) private var theme

    var body: some View {
        if let info = store.current {
                HStack(spacing: 18) {
                    Artwork(store: store, info: info)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(info.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(theme.fg(0.95))
                            .lineLimit(2)
                            .id(info.title)
                            .transition(.push(from: .bottom))
                        Text(info.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.fg(0.55))
                            .lineLimit(1)
                            .padding(.top, 3)

                        Spacer(minLength: 8)

                        ProgressBar(store: store, info: info)

                        Controls(store: store, info: info)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Мягкое свечение цветами обложки. В background, чтобы не влиять на раскладку.
                .background {
                    if let art = store.artwork {
                        GeometryReader { geo in
                            Image(nsImage: art)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .scaleEffect(1.4)
                                .blur(radius: 50)
                                .opacity(theme.isDark ? 0.35 : 0.25)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .transition(.opacity)
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: info.title)
        } else {
            EmptyState(icon: "music.note.tv",
                       text: "Включите музыку или видео — YouTube, Яндекс Музыку, SoundCloud…")
        }
    }
}

private struct Artwork: View {
    @ObservedObject var store: NowPlayingStore
    let info: NowPlaying
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(theme.fg(0.08))
            if let art = store.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity.combined(with: .scale(scale: 1.1)))
                    .id(art)
            } else if let icon = info.appIcon {
                Image(nsImage: icon).resizable().padding(28)
            } else {
                Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(theme.fg(0.4))
            }
        }
        .frame(width: 128, height: 128)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(alignment: .bottomTrailing) {
            if let icon = info.appIcon, store.artwork != nil {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
                    .shadow(radius: 3).offset(x: 6, y: 6)
            }
        }
        .shadow(color: .black.opacity(info.isPlaying ? 0.35 : 0.15), radius: info.isPlaying ? 14 : 6, y: 6)
        .scaleEffect(info.isPlaying ? (hovering ? 1.04 : 1) : 0.9)
        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: info.isPlaying)
        .animation(.spring(response: 0.3), value: hovering)
        .onHover { hovering = $0 }
        .onTapGesture { store.openSourceApp() }
        .help("Открыть \(info.appName)")
    }
}

private struct ProgressBar: View {
    @ObservedObject var store: NowPlayingStore
    let info: NowPlaying
    @Environment(\.theme) private var theme
    @State private var dragValue: Double?
    @State private var hovering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let position = dragValue ?? info.position(at: context.date)
            let fraction = info.duration > 0 ? position / info.duration : 0

            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.fg(0.15))
                        Capsule().fill(theme.fg(0.9))
                            .frame(width: max(0, geo.size.width * fraction))
                            .animation(dragValue == nil ? .linear(duration: 0.25) : nil, value: fraction)
                    }
                    .frame(height: hovering || dragValue != nil ? 7 : 4)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard info.duration > 0 else { return }
                                let f = min(max(value.location.x / geo.size.width, 0), 1)
                                dragValue = f * info.duration
                            }
                            .onEnded { _ in
                                if let target = dragValue { store.seek(to: target) }
                                dragValue = nil
                            }
                    )
                }
                .frame(height: 12)
                .animation(.spring(response: 0.25), value: hovering)
                .onHover { hovering = $0 }

                if info.duration > 0 {
                    HStack {
                        Text(format(position))
                        Spacer()
                        Text("-" + format(max(0, info.duration - position)))
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.fg(0.45))
                }
            }
        }
    }

    private func format(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct Controls: View {
    @ObservedObject var store: NowPlayingStore
    let info: NowPlaying
    @Environment(\.theme) private var theme
    @State private var skipTick = 0
    @State private var backTick = 0

    var body: some View {
        HStack(spacing: 22) {
            Spacer()
            Button {
                backTick += 1
                store.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 18))
                    .symbolEffect(.bounce.down, value: backTick)
            }

            Button { store.togglePlayPause() } label: {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 34)
            }

            Button {
                skipTick += 1
                store.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 18))
                    .symbolEffect(.bounce.down, value: skipTick)
            }
            Spacer()
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(theme.fg(0.9))
    }
}
