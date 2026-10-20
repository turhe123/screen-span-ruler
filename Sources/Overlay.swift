import SwiftUI
import AppKit

/// Per-display measurement state: the frozen capture, the crosshair spans and the fitted box.
final class OverlayModel: ObservableObject {
    /// Crosshair result in pixels: pointer pixel plus the last matching pixel in each direction.
    struct Crosshair { var x, y, left, right, top, bottom: Int }

    let buffer: PixelBuffer
    let size: CGSize
    let scale: CGFloat
    let tolerance: Int
    @Published var showPixels: Bool
    @Published var crosshair: Crosshair?
    @Published var dragRect: CGRect?
    @Published var fitted: PixelRect?
    var releasePoint: CGPoint?

    init(buffer: PixelBuffer, size: CGSize, tolerance: Int, showPixels: Bool) {
        self.buffer = buffer
        self.size = size
        self.scale = size.width > 0 ? CGFloat(buffer.width) / size.width : 1
        self.tolerance = tolerance
        self.showPixels = showPixels
    }

    func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), size.width - 0.01), y: min(max(p.y, 0), size.height - 0.01))
    }

    private func pixel(_ p: CGPoint) -> (Int, Int) {
        (min(max(Int(p.x * scale), 0), buffer.width - 1), min(max(Int(p.y * scale), 0), buffer.height - 1))
    }

    /// Re-runs the four directional edge scans from a point (top-left origin, in points).
    func measure(at point: CGPoint) {
        let (x, y) = pixel(point)
        measurePixel(x, y)
    }

    private func measurePixel(_ x: Int, _ y: Int) {
        let t = tolerance
        crosshair = Crosshair(x: x, y: y,
                              left: buffer.scan(x: x, y: y, dx: -1, dy: 0, tolerance: t),
                              right: buffer.scan(x: x, y: y, dx: 1, dy: 0, tolerance: t),
                              top: buffer.scan(x: x, y: y, dx: 0, dy: -1, tolerance: t),
                              bottom: buffer.scan(x: x, y: y, dx: 0, dy: 1, tolerance: t))
    }

    /// Moves the crosshair by whole pixels.
    func nudge(dx: Int, dy: Int) {
        guard let c = crosshair else { return }
        fitted = nil
        measurePixel(min(max(c.x + dx, 0), buffer.width - 1), min(max(c.y + dy, 0), buffer.height - 1))
    }

    /// Converts the dragged rectangle to pixels and shrinks it to the content inside.
    func finishDrag() {
        guard let r = dragRect else { return }
        let (x0, y0) = pixel(r.origin)
        let (x1, y1) = pixel(CGPoint(x: r.maxX, y: r.maxY))
        let raw = PixelRect(minX: x0, minY: y0, maxX: max(x0, x1), maxY: max(y0, y1))
        fitted = buffer.fit(raw, tolerance: tolerance) ?? raw
        dragRect = nil
    }

    func pointRect(_ r: PixelRect) -> CGRect {
        CGRect(x: CGFloat(r.minX) / scale, y: CGFloat(r.minY) / scale,
               width: CGFloat(r.width) / scale, height: CGFloat(r.height) / scale)
    }

    /// Formats a pixel count in the active unit.
    func label(_ pixels: Int) -> String {
        if showPixels { return "\(pixels) px" }
        let points = CGFloat(pixels) / scale
        return points == points.rounded() ? "\(Int(points)) pt" : String(format: "%.1f pt", points)
    }

    /// Text placed on the clipboard by the C key.
    var summary: String? {
        if let f = fitted { return "\(label(f.width)) × \(label(f.height))" }
        if let c = crosshair { return "\(label(c.right - c.left + 1)) × \(label(c.bottom - c.top + 1))" }
        return nil
    }
}

/// SwiftUI content of an overlay: frozen screenshot, Canvas-drawn measurements and the help strip.
struct OverlayContent: View {
    @ObservedObject var model: OverlayModel
    private let accent = Color(red: 1, green: 0.18, blue: 0.47)

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(decorative: model.buffer.image, scale: model.scale)
                .resizable()
                .frame(width: model.size.width, height: model.size.height)
            Canvas { ctx, _ in draw(in: ctx) }
            helpStrip.padding(.bottom, 24)
        }
        .frame(width: model.size.width, height: model.size.height)
    }

    private var helpStrip: some View {
        Text("Move  measure   ·   Drag  fit box   ·   ⇧  lock axis   ·   ←↑↓→  nudge 1px   ·   U  units (\(model.showPixels ? "px" : "pt"), @\(String(format: "%g", model.scale))x)   ·   C  copy   ·   Esc  exit")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(.black.opacity(0.72)))
    }

    private func draw(in ctx: GraphicsContext) {
        let s = model.scale
        if let c = model.crosshair, model.dragRect == nil, model.fitted == nil {
            let y = (CGFloat(c.y) + 0.5) / s, x = (CGFloat(c.x) + 0.5) / s
            let x0 = CGFloat(c.left) / s, x1 = CGFloat(c.right + 1) / s
            let y0 = CGFloat(c.top) / s, y1 = CGFloat(c.bottom + 1) / s
            var path = Path()
            path.move(to: CGPoint(x: x0, y: y)); path.addLine(to: CGPoint(x: x1, y: y))
            path.move(to: CGPoint(x: x, y: y0)); path.addLine(to: CGPoint(x: x, y: y1))
            for tx in [x0, x1] { path.move(to: CGPoint(x: tx, y: y - 4)); path.addLine(to: CGPoint(x: tx, y: y + 4)) }
            for ty in [y0, y1] { path.move(to: CGPoint(x: x - 4, y: ty)); path.addLine(to: CGPoint(x: x + 4, y: ty)) }
            ctx.stroke(path, with: .color(accent), lineWidth: 1)
            pill(ctx, model.label(c.right - c.left + 1), at: CGPoint(x: (x0 + x1) / 2, y: y - 14))
            pill(ctx, model.label(c.bottom - c.top + 1), at: CGPoint(x: x + 8, y: (y0 + y1) / 2), leading: true)
        }
        let box = model.dragRect ?? model.fitted.map(model.pointRect)
        guard let box else { return }
        ctx.fill(Path(box), with: .color(accent.opacity(0.12)))
        ctx.stroke(Path(box), with: .color(accent), lineWidth: 1)
        if let f = model.fitted {
            pill(ctx, "\(model.label(f.width)) × \(model.label(f.height))", at: CGPoint(x: box.midX, y: box.maxY + 14))
        }
    }

    private func pill(_ ctx: GraphicsContext, _ string: String, at p: CGPoint, leading: Bool = false) {
        let text = ctx.resolve(Text(string).font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundColor(.white))
        let size = text.measure(in: CGSize(width: 400, height: 40))
        let center = leading ? CGPoint(x: p.x + size.width / 2 + 6, y: p.y) : p
        let rect = CGRect(x: center.x - size.width / 2 - 6, y: center.y - size.height / 2 - 3,
                          width: size.width + 12, height: size.height + 6)
        ctx.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(accent))
        ctx.draw(text, at: center)
    }
}

/// Borderless window covering one display that is allowed to take keyboard focus.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Hosting view that turns mouse and keyboard events into measurement updates.
final class OverlayHostingView: NSHostingView<OverlayContent> {
    weak var controller: OverlayController?
    private var tracking: NSTrackingArea?
    private var shiftAnchor: CGPoint?
    private var dragStart: CGPoint?
    private var model: OverlayModel { rootView.model }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private func location(_ event: NSEvent) -> CGPoint {
        let p = event.locationInWindow
        return model.clamp(CGPoint(x: p.x, y: bounds.height - p.y))
    }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        if window?.isKeyWindow == false { mouseEntered(with: event) }
        NSCursor.crosshair.set()
        var p = location(event)
        if let release = model.releasePoint {
            guard hypot(p.x - release.x, p.y - release.y) > 8 else { return }
            model.releasePoint = nil
            model.fitted = nil
        }
        if let a = shiftAnchor {
            if abs(p.x - a.x) >= abs(p.y - a.y) { p.y = a.y } else { p.x = a.x }
        }
        model.measure(at: p)
    }

    override func mouseDown(with event: NSEvent) {
        let p = location(event)
        model.fitted = nil
        model.releasePoint = nil
        dragStart = p
        model.dragRect = CGRect(origin: p, size: .zero)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = location(event)
        model.dragRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        let p = location(event)
        dragStart = nil
        guard let rect = model.dragRect, rect.width >= 3 || rect.height >= 3 else {
            model.dragRect = nil
            model.measure(at: p)
            return
        }
        model.finishDrag()
        model.releasePoint = p
    }

    override func flagsChanged(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        if shift, shiftAnchor == nil, let c = model.crosshair {
            shiftAnchor = CGPoint(x: (CGFloat(c.x) + 0.5) / model.scale, y: (CGFloat(c.y) + 0.5) / model.scale)
        } else if !shift {
            shiftAnchor = nil
        }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: controller?.close()
        case 123: model.nudge(dx: -1, dy: 0)
        case 124: model.nudge(dx: 1, dy: 0)
        case 125: model.nudge(dx: 0, dy: 1)
        case 126: model.nudge(dx: 0, dy: -1)
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": copyMeasurement()
            case "u", "p": model.showPixels.toggle()
            default: super.keyDown(with: event)
            }
        }
    }

    private func copyMeasurement() {
        guard let text = model.summary else { NSSound.beep(); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Owns the per-display overlay windows for one measuring session and releases them on exit.
final class OverlayController {
    static let shared = OverlayController()
    private var windows: [OverlayWindow] = []
    private var capturing = false

    func start() {
        guard windows.isEmpty, !capturing else { return }
        guard CGPreflightScreenCaptureAccess() else {
            if !CGRequestScreenCaptureAccess() { Prefs.openScreenRecordingSettings() }
            return
        }
        capturing = true
        Task { @MainActor in
            defer { capturing = false }
            try? await Task.sleep(nanoseconds: 200_000_000) // let the menu panel fade out
            do {
                show(try await ScreenCapturer.capture(screens: NSScreen.screens))
            } catch {
                Notifier.post("ScreenSpanRuler couldn't capture the screen", error.localizedDescription)
            }
        }
    }

    private func show(_ shots: [(NSScreen, PixelBuffer)]) {
        let defaults = UserDefaults.standard
        let tolerance = Int(defaults.double(forKey: Prefs.tolerance))
        let pixels = defaults.bool(forKey: Prefs.unitPixels)
        let mouse = NSEvent.mouseLocation
        var keyView: OverlayHostingView?

        for (screen, buffer) in shots {
            let frame = screen.frame
            let model = OverlayModel(buffer: buffer, size: frame.size, tolerance: tolerance, showPixels: pixels)
            let window = OverlayWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(frame, display: false)
            window.level = .screenSaver
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let view = OverlayHostingView(rootView: OverlayContent(model: model))
            view.controller = self
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
            if frame.contains(mouse) {
                keyView = view
                model.measure(at: CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y))
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        if let keyView, let window = keyView.window {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(keyView)
        } else {
            windows.first?.makeKeyAndOrderFront(nil)
        }
        NSCursor.crosshair.set()
    }

    /// Closes every overlay and drops the captured buffers so large screenshots are freed.
    func close() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        NSCursor.arrow.set()
    }
}
