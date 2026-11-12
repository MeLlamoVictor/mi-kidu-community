import SwiftUI
import MiKiduCore

public struct KiduAvatarView: View {
    private let profile: KiduProfile
    private let resting: Bool
    private let reaction: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    public init(profile: KiduProfile, resting: Bool, reaction: Int = 0) {
        self.profile = profile
        self.resting = resting
        self.reaction = reaction
    }

    public var body: some View {
        let drawing = BlobatarEngine.dibujo(identidad: profile.seedInput, color: profile.color,
                                            kind: profile.kind == .child ? .child : .adult)
        let canvas = Canvas { context, size in
            let scale = min(size.width, size.height) / 100
            var c = context
            c.translateBy(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            c.scaleBy(x: scale, y: scale)
            var body = Path()
            for shape in drawing.cuerpo {
                switch shape {
                case .circulo(let x, let y, let r): body.addEllipse(in: CGRect(x: x-r, y: y-r, width: r*2, height: r*2))
                case .trazo(let orders): body.addPath(path(orders))
                }
            }
            c.translateBy(x: 0, y: drawing.bajada)
            c.fill(body, with: .color(Color(svg: drawing.colorCabeza)))
            let sleeping = resting
            for orders in drawing.ojos {
                if sleeping {
                    var lid = Path()
                    let bounds = path(orders).boundingRect
                    lid.move(to: CGPoint(x: bounds.minX, y: bounds.midY)); lid.addQuadCurve(to: CGPoint(x: bounds.maxX, y: bounds.midY), control: CGPoint(x: bounds.midX, y: bounds.maxY + bounds.height * 0.35))
                    c.stroke(lid, with: .color(Color(svg: drawing.colorOjos)), lineWidth: 1.6)
                } else {
                    c.fill(path(orders), with: .color(Color(svg: drawing.colorOjos)))
                }
            }
        }
        Group {
            if resting && !reduceMotion && scenePhase == .active {
                canvas.phaseAnimator([false, true]) { view, inhale in
                    view.scaleEffect(inhale ? 1.012 : 1)
                } animation: { _ in .easeInOut(duration: 1.2) }
            } else {
                canvas
            }
        }
        .keyframeAnimator(initialValue: 1.0, trigger: reaction) { view, pulse in
            view.scaleEffect(pulse)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.06, duration: 0.12)
                CubicKeyframe(1.0, duration: 0.24)
            }
        }
        .accessibilityLabel(profile.displayName)
        .accessibilityAddTraits(.isImage)
    }

    private func path(_ commands: [BlobatarEngine.Dibujo.Orden]) -> Path {
        var p = Path()
        for command in commands {
            switch command {
            case .m(let x, let y): p.move(to: CGPoint(x: x, y: y))
            case .l(let x, let y): p.addLine(to: CGPoint(x: x, y: y))
            case .h(let x): p.addLine(to: CGPoint(x: x, y: p.currentPoint?.y ?? 0))
            case .v(let y): p.addLine(to: CGPoint(x: p.currentPoint?.x ?? 0, y: y))
            case .c(let x1, let y1, let x2, let y2, let x, let y): p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
            case .q(let x1, let y1, let x, let y): p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x1, y: y1))
            case .z: p.closeSubpath()
            }
        }
        return p
    }
}

private extension Color {
    init(svg: String) {
        let value = UInt32(svg.dropFirst(), radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
