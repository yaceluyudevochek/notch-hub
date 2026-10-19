// Рисует иконку приложения и фон окна DMG.
// Использование: swift scripts/make_art.swift <выходная папка>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/art")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(width: Int, height: Int, to url: URL, draw: (CGRect) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - Иконка: «экран» с челкой и выезжающей панелью

func drawIcon(_ r: CGRect) {
    let s = r.width
    let inset = s * 0.1
    let body = r.insetBy(dx: inset, dy: inset)
    let corner = s * 0.18

    NSGraphicsContext.current?.cgContext.setShadow(offset: CGSize(width: 0, height: -s * 0.015),
                                                   blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    let bg = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)
    NSGradient(colors: [NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.98, alpha: 1),
                        NSColor(calibratedRed: 0.93, green: 0.33, blue: 0.62, alpha: 1)])!
        .draw(in: bg, angle: -60)
    NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

    // Блик
    NSGraphicsContext.saveGraphicsState()
    bg.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.25), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Раскрытая «челка»
    let panelW = body.width * 0.74, panelH = body.height * 0.44
    let panel = NSRect(x: body.midX - panelW / 2, y: body.maxY - panelH, width: panelW, height: panelH)
    let path = NSBezierPath()
    let rr = s * 0.07
    path.move(to: NSPoint(x: panel.minX, y: panel.maxY))
    path.line(to: NSPoint(x: panel.maxX, y: panel.maxY))
    path.line(to: NSPoint(x: panel.maxX, y: panel.minY + rr))
    path.appendArc(withCenter: NSPoint(x: panel.maxX - rr, y: panel.minY + rr), radius: rr, startAngle: 0, endAngle: 270, clockwise: true)
    path.line(to: NSPoint(x: panel.minX + rr, y: panel.minY))
    path.appendArc(withCenter: NSPoint(x: panel.minX + rr, y: panel.minY + rr), radius: rr, startAngle: 270, endAngle: 180, clockwise: true)
    path.close()
    NSGraphicsContext.saveGraphicsState()
    bg.addClip()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Эквалайзер внутри панели
    let bars: [CGFloat] = [0.45, 0.85, 0.6, 1.0, 0.7]
    let barW = panelW * 0.07, gap = panelW * 0.05
    let total = CGFloat(bars.count) * barW + CGFloat(bars.count - 1) * gap
    var x = panel.midX - total / 2
    let maxH = panelH * 0.45
    for h in bars {
        let bh = maxH * h
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: panel.minY + panelH * 0.22 + (maxH - bh) / 2, width: barW, height: bh),
                               xRadius: barW / 2, yRadius: barW / 2)
        NSColor.white.setFill()
        bar.fill()
        x += barW + gap
    }

    // Карточки снизу: буфер и скриншоты
    let cardW = body.width * 0.3, cardH = body.height * 0.22
    for (i, alpha) in [0.9, 0.6].enumerated() {
        let cx = body.midX + (i == 0 ? -cardW - s * 0.02 : s * 0.02)
        let card = NSBezierPath(roundedRect: NSRect(x: cx, y: body.minY + body.height * 0.12, width: cardW, height: cardH),
                                xRadius: s * 0.035, yRadius: s * 0.035)
        NSColor.white.withAlphaComponent(alpha).setFill()
        card.fill()
    }
}

let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    render(width: size, height: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"), draw: drawIcon)
    render(width: size * 2, height: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"), draw: drawIcon)
}

// MARK: - Фон DMG (660×420 pt)

func drawBackground(scale: CGFloat) -> (CGRect) -> Void {
    return { r in
        NSGradient(colors: [NSColor(calibratedRed: 0.09, green: 0.08, blue: 0.16, alpha: 1),
                            NSColor(calibratedRed: 0.20, green: 0.10, blue: 0.27, alpha: 1)])!
            .draw(in: r, angle: -70)

        // Цветные пятна
        for (point, color) in [(CGPoint(x: 0.15, y: 0.85), NSColor.systemPurple), (CGPoint(x: 0.9, y: 0.2), NSColor.systemPink)] {
            let c = CGPoint(x: r.width * point.x, y: r.height * point.y)
            NSGradient(colors: [color.withAlphaComponent(0.35), color.withAlphaComponent(0)])!
                .draw(fromCenter: c, radius: 0, toCenter: c, radius: r.width * 0.45, options: [])
        }

        // «Челка» сверху
        let nw = 160 * scale, nh = 26 * scale
        let notch = NSBezierPath(roundedRect: NSRect(x: r.midX - nw / 2, y: r.maxY - nh, width: nw, height: nh * 2),
                                 xRadius: 14 * scale, yRadius: 14 * scale)
        NSColor.black.setFill()
        notch.fill()

        let title = NSAttributedString(string: "NotchHub", attributes: [
            .font: NSFont.systemFont(ofSize: 30 * scale, weight: .heavy),
            .foregroundColor: NSColor.white,
        ])
        title.draw(at: NSPoint(x: r.midX - title.size().width / 2, y: r.maxY - 92 * scale))

        let subtitle = NSAttributedString(string: "Перетащите приложение в папку «Программы»", attributes: [
            .font: NSFont.systemFont(ofSize: 14 * scale, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
        ])
        subtitle.draw(at: NSPoint(x: r.midX - subtitle.size().width / 2, y: r.maxY - 122 * scale))

        // Стрелка между иконками (иконки стоят на y = 230 от верха)
        let y = r.maxY - 230 * scale
        let arrow = NSBezierPath()
        arrow.lineWidth = 5 * scale
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(x: r.midX - 52 * scale, y: y))
        arrow.line(to: NSPoint(x: r.midX + 48 * scale, y: y))
        arrow.move(to: NSPoint(x: r.midX + 30 * scale, y: y + 18 * scale))
        arrow.line(to: NSPoint(x: r.midX + 50 * scale, y: y))
        arrow.line(to: NSPoint(x: r.midX + 30 * scale, y: y - 18 * scale))
        NSColor.white.withAlphaComponent(0.85).setStroke()
        arrow.stroke()

        let hint = NSAttributedString(string: "Наведите курсор на челку, чтобы открыть панель", attributes: [
            .font: NSFont.systemFont(ofSize: 12 * scale, weight: .regular),
            .foregroundColor: NSColor.white.withAlphaComponent(0.45),
        ])
        hint.draw(at: NSPoint(x: r.midX - hint.size().width / 2, y: 34 * scale))
    }
}

render(width: 660, height: 420, to: out.appendingPathComponent("background.png"), draw: drawBackground(scale: 1))
render(width: 1320, height: 840, to: out.appendingPathComponent("background@2x.png"), draw: drawBackground(scale: 2))
print("art ready: \(out.path)")
