import AppKit
import SwiftUI
import MiKiduCore
import MiKiduPresentation
import MiKiduShell

@main
struct MiKiduApp: App {
    @StateObject private var model = KiduAppModel()
    private let desktop = MiKiduDesktopHost()
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        WindowGroup("Mi Kidu", id: "mi-kidu") {
            KiduExperience(model: model, release: release)
                .frame(minWidth: 440, minHeight: 540)
        }
        .defaultSize(width: 660, height: 780)
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                Text(model.document?.profile.displayName ?? "Mi Kidu").font(KiduTheme.font(20, .heavy))
                Button { release(); model.greet() } label: { Label("Ven aquí", systemImage: "hand.wave.fill") }
                    .disabled(model.document == nil)
                Button { desktop.cerrar() } label: { Label("Recoger", systemImage: "arrow.down.right.and.arrow.up.left") }
                Button { openWindow(id: "mi-kidu"); NSApp.activate(ignoringOtherApps: true) } label: {
                    Label("Abrir Mi Kidu", systemImage: "rectangle")
                }
            }
            .font(KiduTheme.font(14, .bold)).buttonStyle(.plain)
            .foregroundStyle(KiduTheme.text).padding(18).frame(width: 230)
            .background(KiduTheme.card).task { await model.load() }
        } label: {
            if let document = model.document {
                KiduAvatarView(profile: document.profile, resting: false).frame(width: 24, height: 24)
            } else { Image(systemName: "pawprint.fill") }
        }
        .menuBarExtraStyle(.window)
    }
    @MainActor private func release() {
        desktop.mostrar(adapter: model, theme: theme,
            menu: { adapter, _, close in KiduAgentMenu(model: adapter, close: close, open: openAgent) }) {
                if let document = model.document {
                    KiduAvatarView(profile: document.profile, resting: false, reaction: model.reaction)
                        .onTapGesture(perform: openAgent)
                }
            }
    }
    @MainActor private func openAgent() {
        openWindow(id: "mi-kidu")
        NSApp.activate(ignoringOtherApps: true)
    }
    @MainActor private var theme: MiKiduShellThemeV1 {
        MiKiduShellThemeV1(window: KiduTheme.window, card: KiduTheme.card, control: KiduTheme.control,
            line: KiduTheme.line, text: KiduTheme.text, secondaryText: KiduTheme.text2,
            accent: KiduTheme.mint, onAccent: KiduTheme.onColor, controlText: KiduTheme.text,
            typography: MiKiduShellTypographyV1(eyebrow: KiduTheme.font(11, .semibold), title: KiduTheme.font(24, .heavy),
                status: KiduTheme.font(13), body: KiduTheme.font(14), button: KiduTheme.font(14, .bold)),
            metrics: MiKiduShellMetricsV1(pageInset: 20, gap: 12, cardPadding: 20, cardRadius: 24,
                controlRadius: 12, controlHeight: 44, figureSize: 112))
    }
}
private struct KiduAgentMenu: View {
    @ObservedObject var model: KiduAppModel
    let close: () -> Void
    let open: () -> Void
    @State private var expanded = false
    var body: some View {
        Button { expanded.toggle() } label: {
            Image(systemName: "ellipsis").font(KiduTheme.font(14, .bold)).frame(width: 44, height: 44)
                .foregroundStyle(KiduTheme.text).background(KiduTheme.control, in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel("Acciones de Kidu")
        .popover(isPresented: $expanded, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.document?.profile.displayName ?? "Mi Kidu").font(KiduTheme.font(16, .heavy)).padding(.bottom, 6)
                Button { expanded = false; open() } label: {
                    Label("Abrir agente", systemImage: "rectangle").frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                }.buttonStyle(.plain)
                Button { expanded = false; close() } label: { Label("Recoger", systemImage: "arrow.down.right.and.arrow.up.left").frame(maxWidth: .infinity, minHeight: 36, alignment: .leading) }.buttonStyle(.plain)
            }
            .font(KiduTheme.font(14, .semibold)).foregroundStyle(KiduTheme.text)
            .padding(14).frame(width: 210).background(KiduTheme.card)
            .presentationBackground(KiduTheme.card)
        }
    }
}
