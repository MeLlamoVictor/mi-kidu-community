import SwiftUI
import MiKiduCore
#if os(macOS)
import MiKiduPresentation
#endif
import MiKiduShell
import MiKiduWidgetWatch
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class KiduAppModel: ObservableObject, MiKiduAppAdapterV1, MiKiduLocalCareAdapterV1 {
    #if os(macOS)
    private let dockIcon = KiduCommunityMacIcon()
    #endif
    @Published private(set) var document: KiduDocument? {
        didSet {
            #if os(macOS)
            let profile = document?.profile
            dockIcon.update(seed: profile?.seedInput, color: profile?.color,
                            kind: profile?.kind == .child ? .child : .adult)
            #endif
        }
    }
    @Published private(set) var problem: String?
    @Published private(set) var busy = false
    @Published private(set) var reaction = 0
    @Published private(set) var providerSending = false
    @Published var showingImporter = false
    #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
    private var companionLink: KiduCompanionLink?
    private var pendingWatchRequest = false
    #endif
    private var environment: KiduLocalEnvironment?

    var presentation: MiKiduPresentationV1 {
        var actions: Set<MiKiduAppActionV1> = []
        if problem != nil { actions.insert(.reintentar) }
        return MiKiduPresentationV1(identidad: document == nil ? .sinVincular : .disponible,
            nombre: document?.profile.displayName, dormido: false,
            availability: problem.map { .error(titulo: "No se pudo completar", detalle: $0, permiteReintentar: true) } ?? .listo,
            accionesDisponibles: actions)
    }
    var snapshot: MiKiduSnapshotV1 {
        guard let document else {
            return MiKiduSnapshotV1(state: problem == nil ? .unlinked : .error, message: problem)
        }
        return MiKiduSnapshotV1(state: .ready, name: document.profile.displayName,
            isSleeping: false, availableActions: [],
            saveSync: problem != nil ? .error : .saved, message: problem)
    }
    func load() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        configureCompanionLink()
        do {
            let environment = try KiduLocalEnvironment.app()
            self.environment = environment
            document = try await environment.store.snapshot()
            problem = nil
            shareCompanionLink()
        } catch KiduError.notInitialized { document = nil; problem = nil }
        catch { problem = safeMessage(error) }
    }
    func importDocument(from url: URL) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let size = values.fileSize, size <= 3_000_000 else { throw KiduError.invalidDocument }
            let data = try Data(contentsOf: url)
            let incoming = try JSONDecoder().decode(KiduDocument.self, from: data)
            try incoming.validate()
            guard incoming.profile.familySubject == nil else { throw KiduError.invalidDocument }
            try await initialize(incoming)
        } catch { problem = safeMessage(error) }
    }
    func createLocalProfile(named name: String) async {
        guard !busy, document == nil else { return }
        busy = true
        defer { busy = false }
        do { try await initialize(KiduLocalProfile.create(named: name)) }
        catch let error as KiduLocalProfile.NameError { problem = error.errorDescription }
        catch { problem = safeMessage(error) }
    }
    #if os(macOS) || os(iOS)
    func linkFamily() {
        guard !busy, document == nil else { return }
        busy = true
        problem = nil
        Task {
            defer { busy = false }
            do {
                let link = try KiduFamilyLink.inCurrentWindow()
                try await initialize(link.authorize())
            } catch let failure as KiduFamilyPairing.Failure {
                problem = failure.errorDescription
            } catch let failure as KiduError {
                problem = failure.errorDescription
            } catch {
                problem = "No se pudo completar la conexión con Kidual."
            }
        }
    }
    #endif
    private func initialize(_ incoming: KiduDocument) async throws {
        let environment = try self.environment ?? KiduLocalEnvironment.app()
        try await environment.store.initialize(incoming, deviceID: environment.deviceID(create: true))
        self.environment = environment
        document = incoming
        problem = nil
        refreshWidgets()
        shareCompanionLink()
    }
    func perform(_ action: MiKiduAppActionV1) {
        if action == .reintentar { retry() }
    }
    func perform(_ action: MiKiduSnapshotV1.Action) {}
    #if os(macOS)
    func sendToProvider(_ reviewed: String, executable: URL, provider: KiduAgentProvider, sessionID: UUID,
                        openClawAgent: String) async throws -> String {
        guard !providerSending else { throw KiduAgentProcessRunner.Failure.busy }
        providerSending = true
        defer { providerSending = false }
        return try await KiduAgentProcessRunner().send(reviewed, executable: executable, provider: provider,
                                                      sessionID: sessionID, openClawAgent: openClawAgent)
    }
    #endif
    func greet() { reaction += 1 }
    func retry() {
        Task { await load() }
    }
    func link() {
        #if os(watchOS)
        configureCompanionLink()
        companionLink?.requestLink()
        #else
        showingImporter = true
        #endif
    }
    func reportImportFailure(_ error: Error) { problem = "No se pudo abrir el enlace de Kidu." }
    private func configureCompanionLink() {
        #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
        guard companionLink == nil else { return }
        let link = KiduCompanionLink()
        link.reportProblem = { [weak self] message in self?.problem = message }
        link.requestedDocument = { [weak self] in
            self?.pendingWatchRequest = true
            self?.shareCompanionLink()
        }
        link.receiveDocument = { [weak self] data in
            Task { @MainActor [weak self] in await self?.receiveCompanionLink(data) }
        }
        companionLink = link
        #endif
    }
    private func shareCompanionLink() {
        #if os(iOS)
        guard pendingWatchRequest, let document, let companionLink else { return }
        do {
            if companionLink.shareDocument(try JSONEncoder().encode(document)) { pendingWatchRequest = false }
        } catch { problem = "No se pudo preparar el enlace del reloj." }
        #endif
    }
    private func receiveCompanionLink(_ data: Data) async {
        #if os(watchOS)
        do {
            let incoming = try JSONDecoder().decode(KiduDocument.self, from: data)
            try incoming.validate()
            let environment = try self.environment ?? KiduLocalEnvironment.app()
            do {
                let existing = try await environment.store.snapshot()
                guard existing.profile.personKey == incoming.profile.personKey else { throw KiduError.wrongOwner }
                // Una nueva entrega inicial nunca pisa cuidados hechos en el reloj.
                document = existing
            } catch KiduError.notInitialized {
                try await environment.store.initialize(incoming, deviceID: environment.deviceID(create: true))
                document = incoming
            }
            self.environment = environment
            problem = nil
        } catch { problem = safeMessage(error) }
        #endif
    }
    private func safeMessage(_ error: Error) -> String {
        (error as? KiduError)?.errorDescription ?? "No se pudo guardar el estado. Vuelve a intentarlo."
    }
    private func refreshWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
