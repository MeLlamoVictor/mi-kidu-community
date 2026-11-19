import SwiftUI
import UniformTypeIdentifiers
import MiKiduCore
import MiKiduPresentation
import MiKiduWidgetWatch
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

#if !os(watchOS)
struct KiduExperience: View {
    @ObservedObject var model: KiduAppModel
    var release: (() -> Void)?
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @AppStorage("community.agent.provider.v1") private var provider: KiduAgentProvider = .codex
    @State private var localName = ""
    @State private var brief = KiduAgentBrief()
    @State private var reviewed = ""
    @State private var reviewCopied = false
    @State private var formProblem: String?
    @State private var sheet: Sheet?
    #if os(macOS)
    @AppStorage("community.openClaw.executable.v1") private var openClawPath = ""
    @AppStorage("community.codex.executable.v1") private var codexPath = ""
    @AppStorage("community.claude.executable.v1") private var claudePath = ""
    @AppStorage("community.adapter.executable.v1") private var adapterPath = ""
    @AppStorage("community.openClaw.agent.v1") private var openClawAgent = ""
    @AppStorage("community.openClaw.session.v1") private var openClawSession = ""
    @State private var providerReply: String?
    @State private var providerProblem: String?
    #endif

    private enum Sheet: String, Identifiable {
        case account, profile, help, review
        var id: Self { self }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let document = model.document {
                    header(document.profile)
                    workspace
                } else {
                    welcome
                }
                if let problem = model.problem {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("No se pudo completar", systemImage: "exclamationmark.circle")
                            .font(KiduTheme.font(18, .bold))
                        Text(problem).font(KiduTheme.font(14))
                        Button("Reintentar") { model.retry() }.buttonStyle(KiduControlStyle())
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).kiduCard()
                }
            }.padding(20).frame(maxWidth: 740).frame(maxWidth: .infinity)
        }
        .foregroundStyle(KiduTheme.text).background(KiduTheme.window.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $model.showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await model.importDocument(from: url) }
            case .failure(let error): model.reportImportFailure(error)
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .account: accountAccess
            case .profile: if let profile = model.document?.profile { profileView(profile) }
            case .help: help
            case .review: review
            }
        }
        .task { await model.load() }
        .onChange(of: phase) { _, phase in if phase == .active { Task { await model.load() } } }
    }

    private func header(_ profile: KiduProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MI KIDU").font(KiduTheme.font(11, .semibold)).tracking(1.5)
                    Text(profile.displayName).font(KiduTheme.font(30, .heavy))
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                KiduAvatarView(profile: profile, resting: false, reaction: model.reaction)
                    .frame(width: 88, height: 88)
            }.foregroundStyle(KiduTheme.onColor).padding(18)
                .background(KiduTheme.mint, in: RoundedRectangle(cornerRadius: 24))
            HStack {
                Button { sheet = .profile } label: { Label("Perfil", systemImage: "person.crop.circle") }
                    .buttonStyle(KiduControlStyle())
                Button { sheet = .help } label: { Label("Ayuda", systemImage: "questionmark.circle") }
                    .buttonStyle(KiduControlStyle())
                if let release {
                    Button(action: release) { Label("Liberar", systemImage: "arrow.up.forward") }
                        .buttonStyle(KiduControlStyle())
                }
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "pawprint.circle.fill").font(KiduTheme.font(48, .bold))
                .foregroundStyle(KiduTheme.mint).accessibilityHidden(true)
            Text("Prepara tu próximo encargo").font(KiduTheme.font(30, .heavy))
                .accessibilityAddTraits(.isHeader)
            input("Tu nombre o apodo", text: $localName)
                .disabled(model.busy).onSubmit(createLocal)
            Button(action: createLocal) { Label("Continuar con mi nombre", systemImage: "person.fill") }
                .buttonStyle(KiduControlStyle(primary: true))
                .disabled(model.busy || localName.allSatisfy(\.isWhitespace))
            Button { sheet = .account } label: { Label("Entrar con Kidual", systemImage: "person.badge.key") }
                .buttonStyle(KiduControlStyle()).disabled(model.busy)
            Button { model.link() } label: { Label("Abrir una copia", systemImage: "folder") }
                .buttonStyle(KiduControlStyle()).disabled(model.busy)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).kiduCard()
    }

    private func createLocal() {
        guard !model.busy, !localName.allSatisfy(\.isWhitespace) else { return }
        Task {
            await model.createLocalProfile(named: localName)
            if model.document != nil { localName = "" }
        }
    }

    private var workspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Preparar contexto", systemImage: "square.and.pencil")
                .font(KiduTheme.font(21, .bold)).accessibilityAddTraits(.isHeader)
            input("¿Qué quieres conseguir?", text: $brief.goal, multiline: true)
            input("Contexto y hechos", text: $brief.context, multiline: true)
            input("Límites y permisos", text: $brief.limits, multiline: true)
            input("Resultado esperado", text: $brief.deliverable, multiline: true)
            if let formProblem {
                Label(formProblem, systemImage: "exclamationmark.circle").font(KiduTheme.font(14))
            }
            Button {
                do {
                    reviewed = try brief.prepare()
                    formProblem = nil
                    reviewCopied = false
                    #if os(macOS)
                    providerReply = nil
                    providerProblem = nil
                    #endif
                    sheet = .review
                } catch {
                    formProblem = (error as? LocalizedError)?.errorDescription ?? "Revisa los campos del encargo."
                }
            } label: { Label("Revisar encargo", systemImage: "checkmark.circle") }
                .buttonStyle(KiduControlStyle(primary: true))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).kiduCard()
    }

    private func input(_ title: String, text: Binding<String>, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(KiduTheme.font(12, .semibold)).foregroundStyle(KiduTheme.text2)
                .accessibilityHidden(true)
            if multiline {
                TextField(title, text: text, axis: .vertical).lineLimit(2...5)
            } else {
                TextField(title, text: text)
            }
        }.font(KiduTheme.font(15)).textFieldStyle(.plain).padding(10)
            .background(KiduTheme.control, in: RoundedRectangle(cornerRadius: 12))
    }

    private var accountAccess: some View {
        sheetBody("Entrar con Kidual") {
            if KiduFamilyLinkRelease.isEnabled {
                Button { model.linkFamily() } label: {
                    Label("Autorizar perfil Familia", systemImage: "arrow.up.right.square")
                }.buttonStyle(KiduControlStyle(primary: true)).disabled(model.busy)
                if let problem = model.problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                }
            } else {
                Label(KiduAccountAccess.availabilityMessage, systemImage: "link.badge.plus")
                Link(destination: KiduAccountAccess.website) {
                    Label("Abrir Kidual en el navegador", systemImage: "arrow.up.right.square")
                }.buttonStyle(KiduControlStyle(primary: true))
            }
        }
        .onChange(of: model.document?.profile.personKey) { _, key in
            if key != nil { sheet = nil }
        }
    }

    private func profileView(_ profile: KiduProfile) -> some View {
        sheetBody("Perfil") {
            #if os(iOS)
            KiduCommunityIconControl(seed: profile.seedInput, color: profile.color,
                                     kind: profile.kind == .child ? .child : .adult)
            #endif
            KiduAvatarView(profile: profile, resting: false).frame(width: 105, height: 105)
            Text(profile.displayName).font(KiduTheme.font(26, .heavy))
            Label(profile.familySubject == nil ? "Perfil local" : "Perfil Familia vinculado",
                  systemImage: profile.familySubject == nil ? "internaldrive" : "link")
            if profile.familySubject == nil && !KiduFamilyLinkRelease.isEnabled {
                Text(KiduAccountAccess.availabilityMessage).foregroundStyle(KiduTheme.text2)
            }
        }
    }

    private var help: some View {
        sheetBody("Ayuda") {
            Label("Describe el objetivo, los datos útiles y lo que debe entregar el proveedor.", systemImage: "text.alignleft")
            Label("Revisa y edita el texto antes de copiarlo. Pégalo tú en el proveedor que elijas.", systemImage: "checkmark.shield")
            Label("Puedes usar el mismo encargo con OpenClaw, Codex o Claude.", systemImage: "arrow.triangle.branch")
        }
    }

    private var review: some View {
        sheetBody("Revisar encargo") {
            TextEditor(text: $reviewed)
                .font(KiduTheme.font(15)).frame(minHeight: 180)
                .foregroundStyle(KiduTheme.text).scrollContentBackground(.hidden)
                .padding(6).background(KiduTheme.control, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Texto del encargo")
                .disabled(model.providerSending)
                .onChange(of: reviewed) { reviewCopied = false }
            Picker("Proveedor", selection: $provider) {
                ForEach(KiduAgentProvider.allCases) { provider in Text(provider.title).tag(provider) }
            }.disabled(model.providerSending)
                .onChange(of: provider) {
                    reviewCopied = false
                    #if os(macOS)
                    providerReply = nil
                    providerProblem = nil
                    #endif
                }
            #if os(macOS)
            localProviderControls
            #endif
            Button {
                copyReviewed()
            } label: { Label("Copiar para \(provider.title)", systemImage: "doc.on.doc") }
                .buttonStyle(KiduControlStyle(primary: !hasLocalProviderControls))
                .disabled(model.providerSending || reviewed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if reviewCopied {
                Label("Copiado. Pégalo en \(provider.title).", systemImage: "checkmark.circle")
                if let destination = provider.officialURL {
                    Button {
                        openURL(destination)
                    } label: {
                        Label(provider == .openClaw ? "Abrir guía oficial" : "Abrir sitio oficial",
                              systemImage: "arrow.up.right.square")
                    }.buttonStyle(KiduControlStyle())
                }
            }
        }
    }

    private var hasLocalProviderControls: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    #if os(macOS)
    private var executablePath: Binding<String> {
        switch provider {
        case .openClaw: $openClawPath
        case .codex: $codexPath
        case .claude: $claudePath
        case .localAdapter: $adapterPath
        }
    }

    private var localProviderControls: some View {
        let path = executablePath.wrappedValue
        let agent = openClawAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAgent = provider != .openClaw || KiduAgentProcessRunner.validOpenClawAgent(agent)
        return VStack(alignment: .leading, spacing: 12) {
            if path.isEmpty {
                Button { chooseExecutable() } label: { Label("Elegir ejecutable", systemImage: "folder") }
                    .buttonStyle(KiduControlStyle(primary: true)).disabled(model.providerSending)
            } else {
                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "terminal")
                    .accessibilityLabel("Ejecutable elegido")
                HStack {
                    Button("Cambiar ejecutable") { chooseExecutable() }.buttonStyle(KiduControlStyle())
                    Button("Quitar") {
                        executablePath.wrappedValue = ""
                        if provider == .openClaw { openClawSession = "" }
                        providerReply = nil
                        providerProblem = nil
                    }.buttonStyle(KiduControlStyle())
                }.disabled(model.providerSending)
                if provider == .openClaw {
                    input("ID de tu agente de conversación", text: $openClawAgent)
                        .disabled(model.providerSending)
                        .onChange(of: openClawAgent) { openClawSession = "" }
                }
                Button { sendToProvider() } label: { Label("Enviar a \(provider.title)", systemImage: "paperplane") }
                    .buttonStyle(KiduControlStyle(primary: true))
                    .disabled(model.providerSending || !hasAgent || reviewed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.providerSending { ProgressView("Esperando a \(provider.title)") }
            if let providerProblem {
                Label(providerProblem, systemImage: "exclamationmark.circle")
            }
            if let providerReply {
                Text("Respuesta de \(provider.title)").font(KiduTheme.font(18, .bold)).accessibilityAddTraits(.isHeader)
                Text(verbatim: providerReply).textSelection(.enabled)
            }
        }
    }

    private func chooseExecutable() {
        let provider = provider
        let binding = executablePath
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Elige el ejecutable de \(provider.title) que instalaste y en el que confías."
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            guard KiduAgentProcessRunner.canRun(url) else {
                providerProblem = "El archivo elegido no se puede ejecutar."
                return
            }
            if provider == .openClaw, binding.wrappedValue != url.path { openClawSession = "" }
            binding.wrappedValue = url.path
            providerProblem = nil
            providerReply = nil
        }
    }

    private func sendToProvider() {
        let path = executablePath.wrappedValue
        guard !model.providerSending, !path.isEmpty else { return }
        let prompt = reviewed
        let provider = provider
        let executable = URL(fileURLWithPath: path)
        let agent = openClawAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionID = (provider == .openClaw ? UUID(uuidString: openClawSession) : nil) ?? UUID()
        if provider == .openClaw { openClawSession = sessionID.uuidString }
        providerReply = nil
        providerProblem = nil
        Task {
            do {
                providerReply = try await model.sendToProvider(prompt, executable: executable, provider: provider,
                                                                sessionID: sessionID, openClawAgent: agent)
            } catch let failure as KiduAgentProcessRunner.Failure {
                providerProblem = failure.errorDescription
            } catch {
                providerProblem = "No se pudo completar el turno con \(provider.title)."
            }
        }
    }
    #endif

    private func copyReviewed() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        reviewCopied = NSPasteboard.general.setString(reviewed, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: reviewed]],
                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)])
        reviewCopied = true
        #endif
    }

    private func sheetBody<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(KiduTheme.font(25, .heavy)).accessibilityAddTraits(.isHeader)
                content()
                Button("Cerrar") { sheet = nil }.buttonStyle(KiduControlStyle()).disabled(model.providerSending)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }
        .frame(minWidth: 310, minHeight: 280)
        .font(KiduTheme.font(15)).foregroundStyle(KiduTheme.text).background(KiduTheme.window)
        .interactiveDismissDisabled(model.providerSending)
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
        eyebrow: KiduTheme.font(11, .semibold), title: KiduTheme.font(18, .heavy), body: KiduTheme.font(13),
        button: KiduTheme.font(14, .bold)) { _ in
        if let profile { AnyView(KiduAvatarView(profile: profile, resting: false, reaction: reaction)) }
        else { AnyView(EmptyView()) }
    }
}
