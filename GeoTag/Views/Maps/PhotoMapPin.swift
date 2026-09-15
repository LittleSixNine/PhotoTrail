import SwiftUI

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
