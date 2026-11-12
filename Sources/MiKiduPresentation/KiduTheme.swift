import SwiftUI

public enum KiduTheme {
    public static let window = Color(hex: 0x0A1316)
    public static let card = Color(hex: 0x111D21)
    public static let control = Color(hex: 0x1B2B31)
    public static let line = Color(hex: 0x1F3036)
    public static let text = Color(hex: 0xEAF2F3)
    public static let text2 = Color(hex: 0xA9BEC3)
    public static let mint = Color(hex: 0x8DCDB8)
    public static let onColor = Color(hex: 0x0A1316)

    public static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .heavy, .black: name = "AvenirNext-Heavy"
        case .bold: name = "AvenirNext-Bold"
        case .semibold: name = "AvenirNext-DemiBold"
        case .medium, .semibold: name = "AvenirNext-DemiBold"
        default: name = "AvenirNext-Regular"
        }
        return .custom(name, size: size, relativeTo: .body).monospacedDigit()
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
