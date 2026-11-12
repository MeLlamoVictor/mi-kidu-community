import SwiftUI
import UniformTypeIdentifiers
import MiKiduCore
import MiKiduPresentation
import MiKiduShell
import MiKiduWidgetWatch

#if !os(watchOS)
struct KiduExperience: View {
    @ObservedObject var model: KiduAppModel
    var release: (() -> Void)?
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Mi Kidu").font(KiduTheme.font(34, .heavy))
                    Spacer()
                    if model.document != nil, let release {
                        Button(action: release) { Label("Liberar", systemImage: "arrow.up.forward") }
                            .buttonStyle(KiduControlStyle(primary: true))
                    }
                }
                if let document = model.document {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TU COMPAÑERO").font(KiduTheme.font(11, .semibold)).tracking(1)
                            Text(document.profile.displayName).font(KiduTheme.font(32, .heavy))
                            Label(document.care.resting ? "Dormido" : "Despierto", systemImage: document.care.resting ? "moon.zzz.fill" : "sun.max.fill")
                                .font(KiduTheme.font(14, .semibold))
                        }
                        Spacer(minLength: 4)
                        KiduAvatarView(profile: document.profile, resting: document.care.resting, reaction: model.reaction)
                            .frame(width: 112, height: 112)
                            .onTapGesture { model.perform(MiKiduAppActionV1.acariciar) }
                            .accessibilityLabel("Acariciar a \(document.profile.displayName)")
                            .accessibilityAddTraits(.isButton)
                    }
                    .padding(20).foregroundStyle(KiduTheme.onColor)
                    .background(KiduTheme.mint, in: RoundedRectangle(cornerRadius: 24))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metric("Comida", value: document.care.food, symbol: "carrot.fill")
                        metric("Agua", value: document.care.water, symbol: "drop.fill")
                        metric("Energía", value: document.care.energy, symbol: "bolt.fill")
                        metric("Ánimo", value: document.care.joy, symbol: "heart.fill")
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(availableActions, id: \.0) { action, title, symbol in
                            Button { model.perform(action) } label: { Label(title, systemImage: symbol).frame(maxWidth: .infinity) }
                                .buttonStyle(KiduControlStyle()).disabled(model.busy)
                        }
                    }
                    Label(model.busy ? "Guardando" : "Guardado en este dispositivo", systemImage: model.busy ? "clock" : "checkmark.circle")
                        .font(KiduTheme.font(12, .regular)).foregroundStyle(KiduTheme.text2)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "link.circle.fill").font(KiduTheme.font(48, .bold)).foregroundStyle(KiduTheme.mint)
                        Text("Enlaza tu Kidu").font(KiduTheme.font(26, .heavy))
                        Text("Abre una copia de tu Kidu para continuar.").font(KiduTheme.font(14)).foregroundStyle(KiduTheme.text2)
                        Button { model.link() } label: { Label("Abrir Kidu", systemImage: "folder") }
                            .buttonStyle(KiduControlStyle(primary: true))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).kiduCard()
                }
                if let problem = model.problem {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("No se pudo completar", systemImage: "exclamationmark.circle").font(KiduTheme.font(18, .bold))
                        Text(problem).font(KiduTheme.font(14)).foregroundStyle(KiduTheme.text2)
                        Button { model.retry() } label: { Label("Reintentar", systemImage: "arrow.clockwise") }.buttonStyle(KiduControlStyle())
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).kiduCard()
                }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .foregroundStyle(KiduTheme.text).background(KiduTheme.window.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $model.showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await model.importDocument(from: url) }
            case .failure(let error): model.reportImportFailure(error)
            }
        }
        .task { await model.load() }
        .onChange(of: phase) { _, phase in if phase == .active { Task { await model.load() } } }
    }
    private var availableActions: [(MiKiduAppActionV1, String, String)] {
        let actions: [(MiKiduAppActionV1, String, String)] = [
            (.alimentar, "Alimentar", "carrot.fill"), (.beberAgua, "Agua", "drop.fill"),
            (.acariciar, "Acariciar", "hand.draw.fill"), (.jugar, "Jugar", "gamecontroller.fill"),
            (.dormir, "Descansar", "moon.zzz.fill"), (.despertar, "Despertar", "sun.max.fill")
        ]
        return actions.filter { model.presentation.accionesDisponibles.contains($0.0) }
    }
    private func metric(_ title: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title.uppercased(), systemImage: symbol).font(KiduTheme.font(11, .semibold)).foregroundStyle(KiduTheme.text2)
            Text("\(value)").font(KiduTheme.font(32, .heavy)).foregroundStyle(KiduTheme.mint)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).kiduCard()
    }
}
private struct KiduControlStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(KiduTheme.font(14, .bold)).padding(.horizontal, 14).frame(minHeight: 44)
            .foregroundStyle(primary ? KiduTheme.onColor : KiduTheme.text)
            .background(primary ? KiduTheme.mint : KiduTheme.control, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
private extension View {
    func kiduCard() -> some View {
        background(KiduTheme.card, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(KiduTheme.line))
    }
}
#endif

@MainActor
func kiduSurfaceStyle(profile: KiduProfile?, reaction: Int = 0) -> MiKiduWidgetStyleV1 {
    MiKiduWidgetStyleV1(window: KiduTheme.window, card: KiduTheme.card, line: KiduTheme.line,
        text: KiduTheme.text, secondaryText: KiduTheme.text2, accent: KiduTheme.mint, onAccent: KiduTheme.onColor,
        eyebrow: KiduTheme.font(10, .semibold), title: KiduTheme.font(18, .heavy), body: KiduTheme.font(12), button: KiduTheme.font(13, .bold)) { snapshot in
        if let profile { AnyView(KiduAvatarView(profile: profile, resting: snapshot.isSleeping, reaction: reaction)) }
        else { AnyView(EmptyView()) }
    }
}
