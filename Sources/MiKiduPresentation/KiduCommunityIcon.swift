import SwiftUI
#if os(macOS)
import AppKit
import Combine
#elseif os(iOS)
import UIKit
#endif

/// Arte del icono, independiente de la vista animada y del almacenamiento de la app.
public enum KiduCommunityIcon {
    public struct Sample: Sendable {
        public let asset: String
        public let seed: String
        public let color: String
    }

    public static let samples: [Sample] = [
        .init(asset: "AppIcon", seed: "Community Amber", color: "#F39A44"),
        .init(asset: "IconLagoon", seed: "Community Lagoon", color: "#37A7A0"),
        .init(asset: "IconBerry", seed: "Community Berry", color: "#E66B9C"),
        .init(asset: "IconSky", seed: "Community Sky", color: "#6698EB"),
        .init(asset: "IconMoss", seed: "Community Moss", color: "#86AD59"),
        .init(asset: "IconIris", seed: "Community Iris", color: "#9F84E6")
    ]

    public static func recommendedName(seed: String, color: String?, kind: BlobatarEngine.Kind) -> String? {
        let wanted = BlobatarEngine.dibujo(identidad: seed, color: color, kind: kind)
        func distance(_ sample: Sample) -> Double {
            let option = BlobatarEngine.dibujo(identidad: sample.seed, color: sample.color, kind: .child)
            let hue = abs(option.tono - wanted.tono).truncatingRemainder(dividingBy: 360)
            return min(hue, 360 - hue) + (option.forma == wanted.forma ? 0 : 32)
        }
        let asset = samples.min { distance($0) < distance($1) }?.asset
        return asset == "AppIcon" ? nil : asset
    }

    public struct Tile: View {
        let drawing: BlobatarEngine.Dibujo
        let dark: Bool
        let rounded: Bool

        public init(seed: String, color: String?, kind: BlobatarEngine.Kind, dark: Bool, rounded: Bool) {
            drawing = BlobatarEngine.dibujo(identidad: seed, color: color, kind: kind)
            self.dark = dark; self.rounded = rounded
        }

        public var body: some View {
            Canvas { context, size in
                let edge = min(size.width, size.height)
                var layer = context
                layer.scaleBy(x: edge / 100, y: edge / 100)
                let inset = rounded ? 8.0 : 0
                let square = CGRect(x: inset, y: inset, width: 100 - inset * 2, height: 100 - inset * 2)
                let outline = Path(roundedRect: square, cornerRadius: rounded ? 20 : 0)
                layer.fill(outline, with: .color(dark ? rgb(0x192339) : rgb(0xFFF3DD)))
                layer.stroke(outline, with: .color(dark ? rgb(0x35415B) : rgb(0xDFCCAA)), lineWidth: rounded ? 1.1 : 0)
                let halo = Path(ellipseIn: CGRect(x: 18, y: 18, width: 64, height: 64))
                layer.fill(halo, with: .color(dark ? rgb(0x293853) : rgb(0xEDDDBB)))

                var avatar = layer
                avatar.translateBy(x: 11, y: 11 + drawing.bajada * 0.78)
                avatar.scaleBy(x: 0.78, y: 0.78)
                let contour = drawing.cuerpo.map { figure -> Path in
                    switch figure {
                    case let .circulo(x, y, r):
                        return Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                    case let .trazo(orders): return path(orders)
                    }
                }
                for body in contour {
                    avatar.stroke(body, with: .color(dark ? .white.opacity(0.26) : .black.opacity(0.26)), lineWidth: 1.4)
                }
                for body in contour {
                    avatar.fill(body, with: .color(rgb(hex(drawing.colorCabeza))))
                }
                for eye in drawing.ojos {
                    avatar.fill(path(eye), with: .color(rgb(hex(drawing.colorOjos))))
                }
            }
            .accessibilityHidden(true)
        }

        private func hex(_ css: String) -> UInt32 {
            let value = css.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            if value.count == 3 {
                return UInt32(String(value.flatMap { [$0, $0] }), radix: 16) ?? 0
            }
            return UInt32(value, radix: 16) ?? 0
        }

        private func rgb(_ hex: UInt32) -> Color {
            Color(.sRGB, red: Double(hex >> 16 & 255) / 255,
                  green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255)
        }

        private func path(_ orders: [BlobatarEngine.Dibujo.Orden]) -> Path {
            var result = Path()
            for order in orders {
                switch order {
                case let .m(x, y): result.move(to: CGPoint(x: x, y: y))
                case let .l(x, y): result.addLine(to: CGPoint(x: x, y: y))
                case let .h(x): result.addLine(to: CGPoint(x: x, y: result.currentPoint?.y ?? 0))
                case let .v(y): result.addLine(to: CGPoint(x: result.currentPoint?.x ?? 0, y: y))
                case let .c(ax, ay, bx, by, x, y):
                    result.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: ax, y: ay), control2: CGPoint(x: bx, y: by))
                case let .q(ax, ay, x, y):
                    result.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: ax, y: ay))
                case .z: result.closeSubpath()
                }
            }
            return result
        }
    }
}

#if os(macOS)
@MainActor public final class KiduCommunityMacIcon {
    private var token: AnyCancellable?
    private var identity: Input?
    private struct Input: Equatable {
        let seed: String
        let color: String?
        let kind: BlobatarEngine.Kind
    }

    public init() {
        token = NSApplication.shared.publisher(for: \.effectiveAppearance).sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    /// Llámalo con el perfil resuelto y con nil al desvincular.
    public func update(seed: String?, color: String?, kind: BlobatarEngine.Kind) {
        let next = seed.map { Input(seed: $0, color: color, kind: kind) }
        guard next != identity else { return }
        identity = next
        refresh()
    }

    private func refresh() {
        guard identity != nil else { NSApplication.shared.applicationIconImage = nil; return }
        if let icon = makeImage() { NSApplication.shared.applicationIconImage = icon }
    }

    private func makeImage() -> NSImage? {
        guard let identity else { return nil }
        let dark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return ImageRenderer(content: KiduCommunityIcon.Tile(seed: identity.seed, color: identity.color,
            kind: identity.kind, dark: dark, rounded: true).frame(width: 512, height: 512)).nsImage
    }

    /// Guardar solo tras la elección explícita de una ubicación. No modifica el bundle.
    public func saveFinderShortcut(at destination: URL) throws {
        guard destination.isFileURL, destination.pathExtension.lowercased() == "alias",
              let icon = makeImage() else { throw CocoaError(.fileWriteInvalidFileName) }
        let fileManager = FileManager.default
        let scratch = destination.deletingLastPathComponent()
            .appendingPathComponent(".icon-" + UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: scratch) }
        let alias = scratch.appendingPathComponent("Kidu.alias")
        let bookmark = try Bundle.main.bundleURL.bookmarkData(options: .suitableForBookmarkFile,
                                                             includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(bookmark, to: alias)
        guard NSWorkspace.shared.setIcon(icon, forFile: alias.path, options: []) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try fileManager.moveItem(at: alias, to: destination)
    }
}
#elseif os(iOS)
@MainActor public extension KiduCommunityIcon {
    /// Invocar desde un botón explícito. UIKit puede mostrar el aviso del sistema.
    static func apply(seed: String, color: String?, kind: BlobatarEngine.Kind) async throws {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { throw CocoaError(.featureUnsupported) }
        let name = recommendedName(seed: seed, color: color, kind: kind)
        if name != app.alternateIconName { try await app.setAlternateIconName(name) }
    }

    static func reset() async throws {
        let app = UIApplication.shared
        if app.supportsAlternateIcons, app.alternateIconName != nil { try await app.setAlternateIconName(nil) }
    }
}

public struct KiduCommunityIconControl: View {
    let seed: String
    let color: String?
    let kind: BlobatarEngine.Kind
    @State private var busy = false
    @State private var problem = false
    @State private var selected = UIApplication.shared.alternateIconName

    public init(seed: String, color: String?, kind: BlobatarEngine.Kind) {
        self.seed = seed; self.color = color; self.kind = kind
    }

    public var body: some View {
        if UIApplication.shared.supportsAlternateIcons {
            let name = KiduCommunityIcon.recommendedName(seed: seed, color: color, kind: kind)
            DisclosureGroup("Icono del iPhone") {
                HStack {
                    if let sample = KiduCommunityIcon.samples.first(where: { $0.asset == (name ?? "AppIcon") }) {
                        ForEach([false, true], id: \.self) { dark in
                            VStack {
                                KiduCommunityIcon.Tile(seed: sample.seed, color: sample.color, kind: .child,
                                    dark: dark, rounded: false).frame(width: 42, height: 42).clipShape(.rect(cornerRadius: 9))
                                Text(dark ? "Oscuro" : "Claro").font(.caption)
                            }
                        }
                    }
                }
                Button("Usar icono recomendado") { change(reset: false) }.disabled(busy || selected == name)
                if selected != nil {
                    Button("Volver al icono original") { change(reset: true) }.disabled(busy)
                }
                if problem {
                    Label("No se pudo cambiar el icono. Vuelve a intentarlo.", systemImage: "exclamationmark.circle")
                }
            }
        }
    }

    private func change(reset: Bool) {
        busy = true; problem = false
        Task { @MainActor in
            defer { busy = false }
            do {
                if reset { try await KiduCommunityIcon.reset() }
                else { try await KiduCommunityIcon.apply(seed: seed, color: color, kind: kind) }
                selected = UIApplication.shared.alternateIconName
            } catch { problem = true }
        }
    }
}
#endif
