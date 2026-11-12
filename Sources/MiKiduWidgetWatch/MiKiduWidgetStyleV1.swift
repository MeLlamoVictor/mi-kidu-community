import SwiftUI

/// Tokens y renderer que el integrador construye desde Brand/Type y el renderer canónico.
public struct MiKiduWidgetStyleV1 {
    public let window: Color
    public let card: Color
    public let line: Color
    public let text: Color
    public let secondaryText: Color
    public let accent: Color
    public let onAccent: Color
    public let eyebrow: Font
    public let title: Font
    public let body: Font
    public let button: Font
    public let figure: (MiKiduSnapshotV1) -> AnyView

    public init(window: Color, card: Color, line: Color, text: Color, secondaryText: Color,
                accent: Color, onAccent: Color, eyebrow: Font, title: Font, body: Font,
                button: Font, figure: @escaping (MiKiduSnapshotV1) -> AnyView) {
        self.window = window
        self.card = card
        self.line = line
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
        self.onAccent = onAccent
        self.eyebrow = eyebrow
        self.title = title
        self.body = body
        self.button = button
        self.figure = figure
    }
}

@MainActor
public protocol MiKiduLocalCareAdapterV1: ObservableObject {
    var snapshot: MiKiduSnapshotV1 { get }
    func perform(_ action: MiKiduSnapshotV1.Action)
    func retry()
    func link()
}
