import AppKit
import SwiftUI
import ImageData

struct MapScrollWheelMonitor: NSViewRepresentable {
    let onScroll: (Double, CGPoint) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onScroll = onScroll
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: Void) {
        view.stopMonitoring()
    }

    static func steps(deltaY: Double, precise: Bool) -> Double {
        min(4, max(-4, precise ? deltaY / 8 : deltaY))
    }

    final class MonitorView: NSView {
        var onScroll: (Double, CGPoint) -> Void = { _, _ in }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window, event.window === window else { return event }
                let appKitPoint = convert(event.locationInWindow, from: nil)
                guard bounds.contains(appKitPoint) else { return event }
                // AppKit's origin is bottom-left; SwiftUI and the web maps use top-left.
                let point = CGPoint(x: appKitPoint.x, y: bounds.height - appKitPoint.y)
                let steps = MapScrollWheelMonitor.steps(
                    deltaY: event.scrollingDeltaY,
                    precise: event.hasPreciseScrollingDeltas)
                if steps != 0 { onScroll(steps, point) }
                return nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

// The drawing ends exactly at (16, 42); .bottom anchors that tip to the coordinate.
struct PhotoMapPin: View {
    var preview = false

    var body: some View {
        Canvas { context, _ in
            var body = Path()
            body.move(to: CGPoint(x: 16, y: 42))
            body.addCurve(to: CGPoint(x: 0, y: 16), control1: CGPoint(x: 12, y: 34), control2: CGPoint(x: 0, y: 26))
            body.addCurve(to: CGPoint(x: 16, y: 0), control1: CGPoint(x: 0, y: 5), control2: CGPoint(x: 5, y: 0))
            body.addCurve(to: CGPoint(x: 32, y: 16), control1: CGPoint(x: 27, y: 0), control2: CGPoint(x: 32, y: 5))
            body.addCurve(to: CGPoint(x: 16, y: 42), control1: CGPoint(x: 32, y: 26), control2: CGPoint(x: 20, y: 34))
            body.closeSubpath()
            let red = Color(red: 0.91, green: 0.19, blue: 0.18)
            context.fill(body, with: .linearGradient(Gradient(colors: [.red, red]),
                startPoint: .zero, endPoint: CGPoint(x: 32, y: 42)))
            var mountains = Path()
            mountains.move(to: CGPoint(x: 6, y: 23))
            for point in [CGPoint(x: 13, y: 12), CGPoint(x: 18, y: 19),
                          CGPoint(x: 22, y: 15), CGPoint(x: 27, y: 23)] { mountains.addLine(to: point) }
            mountains.closeSubpath()
            context.fill(mountains, with: .color(.white))
            context.fill(Path(ellipseIn: CGRect(x: 20, y: 7, width: 5, height: 5)), with: .color(.white))
            var shine = Path()
            shine.move(to: CGPoint(x: 3, y: 15))
            shine.addCurve(to: CGPoint(x: 25, y: 5), control1: CGPoint(x: 4, y: 2), control2: CGPoint(x: 17, y: 0))
            context.stroke(shine, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
        }.frame(width: 32, height: 42)
            .opacity(preview ? 0.65 : 1)
            .accessibilityLabel(preview ? "地点预览" : "照片位置")
    }
}

struct PhotoThumbnailMapPin: View {
    let image: ImageData
    let selected: Bool
    var clusterCount = 1

    var body: some View {
        ZStack(alignment: .top) {
            PhotoThumbnailPinShape()
                .fill(LinearGradient(colors: shellColors,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    PhotoThumbnailPinShape()
                        .stroke(selected ? Color(red: 0.72, green: 0.04, blue: 0.04)
                                : Color.black.opacity(0.18), lineWidth: 0.8)
                }
                .frame(width: 48, height: 58)
                .shadow(color: .black.opacity(0.20), radius: 3, y: 1.5)
            PhotoThumbnail(image: image, fill: true, maxDimension: 96)
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.16), lineWidth: 0.75))
                .offset(y: 4)
            if clusterCount > 1 {
                Text("\(clusterCount)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? Color(red: 0.80, green: 0.06, blue: 0.05) : .primary)
                    .frame(minWidth: 21, minHeight: 21)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 0.75))
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .offset(x: 20, y: -5)
            }
        }
        .frame(width: 50, height: 58)
        .contentShape(Rectangle())
        .accessibilityLabel("照片 \(image.name) 的位置")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var shellColors: [Color] {
        selected
            ? [Color(red: 1.0, green: 0.29, blue: 0.25), Color(red: 0.88, green: 0.05, blue: 0.04)]
            : [.white, Color(nsColor: .windowBackgroundColor)]
    }
}

struct PhotoEdgeIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pointing = false
    let image: ImageData
    let direction: Angle

    var body: some View {
        ZStack {
            PhotoEdgePinShape()
                .fill(LinearGradient(colors: [.white, Color(white: 0.98)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(PhotoEdgePinShape().stroke(Color.black.opacity(0.12), lineWidth: 0.6))
                .shadow(color: .black.opacity(0.15), radius: 2.5, y: 1)
            PhotoThumbnail(image: image, fill: true, maxDimension: 96)
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.16), lineWidth: 0.75))
                .rotationEffect(-direction)
                .offset(x: -6)
            Path { path in
                path.move(to: CGPoint(x: 40.5, y: 21))
                path.addLine(to: CGPoint(x: 45.5, y: 26))
                path.addLine(to: CGPoint(x: 40.5, y: 31))
                path.closeSubpath()
            }
                .fill(Color(red: 0.90, green: 0.23, blue: 0.20))
        }
        .frame(width: 52, height: 52)
        .compositingGroup()
        .rotationEffect(direction)
        .offset(rotatedOffset(length: pointing && !reduceMotion ? 7 : 0))
        .animation(reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(autoreverses: true),
                   value: pointing)
        .onAppear { pointing = !reduceMotion }
        .onChange(of: reduceMotion) { pointing = !reduceMotion }
        .accessibilityLabel("所选照片位于地图外：\(image.name)")
    }

    private func rotatedOffset(length: CGFloat) -> CGSize {
        CGSize(width: cos(direction.radians) * length,
               height: sin(direction.radians) * length)
    }
}

struct PhotoThumbnailPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let centerX = rect.midX
        var path = Path()
        path.move(to: CGPoint(x: centerX, y: rect.maxY - 0.5))
        path.addCurve(to: CGPoint(x: rect.minX + 2, y: rect.minY + 24),
                      control1: CGPoint(x: centerX - 4, y: rect.maxY - 10),
                      control2: CGPoint(x: rect.minX + 2, y: rect.minY + 38))
        path.addCurve(to: CGPoint(x: centerX, y: rect.minY + 1),
                      control1: CGPoint(x: rect.minX + 2, y: rect.minY + 10),
                      control2: CGPoint(x: rect.minX + 11, y: rect.minY + 1))
        path.addCurve(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 24),
                      control1: CGPoint(x: rect.maxX - 11, y: rect.minY + 1),
                      control2: CGPoint(x: rect.maxX - 2, y: rect.minY + 10))
        path.addCurve(to: CGPoint(x: centerX, y: rect.maxY - 0.5),
                      control1: CGPoint(x: rect.maxX - 2, y: rect.minY + 38),
                      control2: CGPoint(x: centerX + 4, y: rect.maxY - 10))
        path.closeSubpath()
        return path
    }
}

struct PhotoEdgePinShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ horizontal: CGFloat, _ vertical: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + horizontal * rect.width / 52,
                    y: rect.minY + vertical * rect.height / 52)
        }
        var path = Path()
        path.move(to: point(51, 26))
        path.addCurve(to: point(34.4, 11.3), control1: point(46.8, 21.4), control2: point(41.4, 15.6))
        path.addCurve(to: point(20, 7), control1: point(30.2, 8.7), control2: point(25.4, 7))
        path.addCurve(to: point(0.5, 26), control1: point(8.9, 7), control2: point(0.5, 15.4))
        path.addCurve(to: point(20, 45), control1: point(0.5, 36.6), control2: point(8.9, 45))
        path.addCurve(to: point(34.4, 40.7), control1: point(25.4, 45), control2: point(30.2, 43.3))
        path.addCurve(to: point(51, 26), control1: point(41.4, 36.4), control2: point(46.8, 30.6))
        path.closeSubpath()
        return path
    }
}
