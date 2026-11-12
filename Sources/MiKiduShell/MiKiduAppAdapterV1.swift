import SwiftUI

/// Adaptador de presentación provisional y local. No representa identidad, autenticación ni sincronización.
@MainActor
public protocol MiKiduAppAdapterV1: ObservableObject {
    var presentation: MiKiduPresentationV1 { get }
    func perform(_ action: MiKiduAppActionV1)
}

public enum MiKiduAppActionV1: String, CaseIterable, Hashable, Sendable {
    case alimentar
    case beberAgua
    case acariciar
    case jugar
    case dormir
    case despertar
    case enlazar
    case hablar
    case volver
    case reintentar
}

public enum MiKiduIdentityStatusV1: Equatable, Sendable {
    case sinVincular
    case disponible
}

public enum MiKiduAvailabilityV1: Equatable, Sendable {
    case listo
    case error(titulo: String, detalle: String, permiteReintentar: Bool)
}

/// Solo datos para mostrar. `accionesDisponibles` son capacidades locales de UI, no permisos del servidor.
public struct MiKiduPresentationV1: Equatable, Sendable {
    public var identidad: MiKiduIdentityStatusV1
    public var nombre: String?
    public var dormido: Bool
    public var availability: MiKiduAvailabilityV1
    public var accionesDisponibles: Set<MiKiduAppActionV1>

    public init(identidad: MiKiduIdentityStatusV1 = .sinVincular, nombre: String? = nil,
                dormido: Bool = false,
                availability: MiKiduAvailabilityV1 = .listo,
                accionesDisponibles: Set<MiKiduAppActionV1> = []) {
        self.identidad = identidad
        self.nombre = nombre
        self.dormido = dormido
        self.availability = availability
        self.accionesDisponibles = accionesDisponibles
    }
}

/// Paleta inyectada para que el origen futuro de Brand siga siendo único.
public struct MiKiduShellThemeV1 {
    public var window: Color
    public var card: Color
    public var control: Color
    public var line: Color
    public var text: Color
    public var secondaryText: Color
    public var accent: Color
    public var onAccent: Color
    public var controlText: Color
    public var typography: MiKiduShellTypographyV1
    public var metrics: MiKiduShellMetricsV1

    public init(window: Color, card: Color, control: Color, line: Color, text: Color,
                secondaryText: Color, accent: Color, onAccent: Color, controlText: Color,
                typography: MiKiduShellTypographyV1, metrics: MiKiduShellMetricsV1) {
        self.window = window
        self.card = card
        self.control = control
        self.line = line
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
        self.onAccent = onAccent
        self.controlText = controlText
        self.typography = typography
        self.metrics = metrics
    }
}

/// Tipografía construida desde el sistema común de tipos, con Avenir Next y Dynamic Type.
public struct MiKiduShellTypographyV1 {
    public var eyebrow: Font
    public var title: Font
    public var status: Font
    public var body: Font
    public var button: Font

    public init(eyebrow: Font, title: Font, status: Font, body: Font, button: Font) {
        self.eyebrow = eyebrow
        self.title = title
        self.status = status
        self.body = body
        self.button = button
    }
}

/// Métricas adaptadas desde Brand/Type compartidos, no medidas independientes por plataforma.
public struct MiKiduShellMetricsV1 {
    public var pageInset: CGFloat
    public var gap: CGFloat
    public var cardPadding: CGFloat
    public var cardRadius: CGFloat
    public var controlRadius: CGFloat
    public var controlHeight: CGFloat
    public var figureSize: CGFloat

    public init(pageInset: CGFloat, gap: CGFloat, cardPadding: CGFloat, cardRadius: CGFloat,
                controlRadius: CGFloat, controlHeight: CGFloat, figureSize: CGFloat) {
        self.pageInset = pageInset
        self.gap = gap
        self.cardPadding = cardPadding
        self.cardRadius = cardRadius
        self.controlRadius = controlRadius
        self.controlHeight = controlHeight
        self.figureSize = figureSize
    }
}
