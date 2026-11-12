import SwiftUI

/// Entrada de contenido compartida entre Mac e iPhone. El host inyecta renderer, paleta y modelo.
@MainActor
public struct MiKiduAppRootV1<Adapter: MiKiduAppAdapterV1, Figura: View>: View {
    @ObservedObject private var adapter: Adapter
    private let theme: MiKiduShellThemeV1
    private let figura: () -> Figura

    public init(adapter: Adapter, theme: MiKiduShellThemeV1,
                @ViewBuilder figura: @escaping () -> Figura) {
        self.adapter = adapter
        self.theme = theme
        self.figura = figura
    }

    public var body: some View {
        let datos = adapter.presentation
        ScrollView {
            VStack(alignment: .leading, spacing: theme.metrics.gap) {
                if datos.identidad == .sinVincular {
                    estadoSinVincular(datos)
                } else {
                    tarjetaIdentidad(datos)
                    switch datos.availability {
                    case .listo:
                        acciones(datos)
                    case .error(let titulo, let detalle, let permiteReintentar):
                        error(titulo: titulo, detalle: detalle,
                              permiteReintentar: permiteReintentar && datos.accionesDisponibles.contains(.reintentar))
                    }
                }
            }
            .padding(theme.metrics.pageInset)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.window.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func tarjetaIdentidad(_ datos: MiKiduPresentationV1) -> some View {
        HStack(alignment: .center, spacing: theme.metrics.gap) {
            VStack(alignment: .leading, spacing: theme.metrics.gap / 2) {
                Text("MI KIDU")
                    .font(theme.typography.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(theme.onAccent.opacity(0.84))
                Text(datos.nombre?.isEmpty == false ? datos.nombre! : "Tu Kidu")
                    .font(theme.typography.title)
                    .foregroundStyle(theme.onAccent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Label(datos.dormido ? "Dormido" : "Despierto",
                      systemImage: datos.dormido ? "moon.fill" : "sun.max.fill")
                    .font(theme.typography.status)
                    .foregroundStyle(theme.onAccent.opacity(0.88))
            }
            Spacer(minLength: 0)
            figura()
                .frame(width: theme.metrics.figureSize, height: theme.metrics.figureSize)
                .accessibilityHidden(true)
        }
        .padding(theme.metrics.cardPadding)
        .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.metrics.cardRadius))
    }

    @ViewBuilder
    private func estadoSinVincular(_ datos: MiKiduPresentationV1) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.gap) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 68, height: 68)
                .background(theme.accent.opacity(0.14), in: Circle())
            Text("Kidu sin vincular")
                .font(theme.typography.title)
                .foregroundStyle(theme.text)
            Text("Vincula Mi Kidu para empezar.")
                .font(theme.typography.body)
                .foregroundStyle(theme.secondaryText)
            accion(.enlazar, titulo: "Enlazar", icono: "link", tintada: true)
            if case .error(let titulo, let detalle, let permiteReintentar) = datos.availability {
                error(titulo: titulo, detalle: detalle,
                      permiteReintentar: permiteReintentar && datos.accionesDisponibles.contains(.reintentar))
            }
        }
        .padding(theme.metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.metrics.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.metrics.cardRadius).stroke(theme.line))
    }

    @ViewBuilder
    private func acciones(_ datos: MiKiduPresentationV1) -> some View {
        let columnas = [GridItem(.flexible(), spacing: theme.metrics.gap),
                        GridItem(.flexible(), spacing: theme.metrics.gap)]
        LazyVGrid(columns: columnas, spacing: theme.metrics.gap) {
            if datos.dormido, datos.accionesDisponibles.contains(.despertar) {
                accion(.despertar, titulo: "Despertar", icono: "sun.max.fill", tintada: true)
            } else if !datos.dormido, datos.accionesDisponibles.contains(.dormir) {
                accion(.dormir, titulo: "Descansar", icono: "moon.fill", tintada: true)
            }
            if datos.accionesDisponibles.contains(.alimentar) {
                accion(.alimentar, titulo: "Alimentar", icono: "carrot.fill", tintada: false)
            }
            if datos.accionesDisponibles.contains(.beberAgua) {
                accion(.beberAgua, titulo: "Agua", icono: "drop.fill", tintada: false)
            }
            if datos.accionesDisponibles.contains(.acariciar) {
                accion(.acariciar, titulo: "Acariciar", icono: "hand.point.up.left.fill", tintada: false)
            }
            if datos.accionesDisponibles.contains(.jugar) {
                accion(.jugar, titulo: "Jugar", icono: "gamecontroller.fill", tintada: false)
            }
            if datos.accionesDisponibles.contains(.hablar) {
                accion(.hablar, titulo: "Hablar", icono: "bubble.left.fill", tintada: false)
            }
            if datos.accionesDisponibles.contains(.volver) {
                accion(.volver, titulo: "Volver", icono: "arrow.uturn.backward", tintada: false)
            }
        }
    }

    private func error(titulo: String, detalle: String, permiteReintentar: Bool) -> some View {
        VStack(alignment: .leading, spacing: theme.metrics.gap) {
            Label(titulo, systemImage: "exclamationmark.circle.fill")
                .font(theme.typography.title)
                .foregroundStyle(theme.text)
            Text(detalle)
                .font(theme.typography.body)
                .foregroundStyle(theme.secondaryText)
            if permiteReintentar {
                accion(.reintentar, titulo: "Reintentar", icono: "arrow.clockwise", tintada: true)
            }
        }
        .padding(theme.metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.metrics.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: theme.metrics.cardRadius).stroke(theme.line))
    }

    @ViewBuilder
    private func accion(_ accion: MiKiduAppActionV1, titulo: String,
                        icono: String, tintada: Bool) -> some View {
        Button { adapter.perform(accion) } label: {
            Label(titulo, systemImage: icono)
                .font(theme.typography.button)
                .frame(maxWidth: .infinity, minHeight: theme.metrics.controlHeight)
                .foregroundStyle(tintada ? theme.onAccent : theme.controlText)
                .padding(.horizontal, theme.metrics.gap)
                .background(tintada ? theme.accent : theme.control,
                            in: RoundedRectangle(cornerRadius: theme.metrics.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: theme.metrics.controlRadius)
                    .stroke(tintada ? .clear : theme.line))
        }
        .buttonStyle(.plain)
        .accessibilityHint(titulo)
    }
}
