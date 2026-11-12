import SwiftUI
import MiKiduCore
import MiKiduShell
import MiKiduWidgetWatch
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class KiduAppModel: ObservableObject, MiKiduAppAdapterV1, MiKiduLocalCareAdapterV1 {
    @Published private(set) var document: KiduDocument?
    @Published private(set) var problem: String?
    @Published private(set) var busy = false
    @Published private(set) var reaction = 0
    @Published var showingImporter = false
    #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
    private var companionLink: KiduCompanionLink?
    #endif
    private var environment: KiduLocalEnvironment?
    private var lastFailedAction: KiduCareAction?

    var presentation: MiKiduPresentationV1 {
        var actions: Set<MiKiduAppActionV1> = []
        if let document {
            actions = document.care.resting ? [.despertar, .acariciar] : [.alimentar, .beberAgua, .acariciar, .jugar, .dormir]
        }
        if problem != nil { actions.insert(.reintentar) }
        return MiKiduPresentationV1(identidad: document == nil ? .sinVincular : .disponible,
            nombre: document?.profile.displayName, dormido: document?.care.resting ?? false,
            availability: problem.map { .error(titulo: "No se pudo completar", detalle: $0, permiteReintentar: true) } ?? .listo,
            accionesDisponibles: actions)
    }
    var snapshot: MiKiduSnapshotV1 {
        guard let document else {
            return MiKiduSnapshotV1(state: problem == nil ? .unlinked : .error, message: problem)
        }
        let actions: Set<MiKiduSnapshotV1.Action> = document.care.resting ? [.wake, .pet] : [.feed, .drink, .pet, .play, .sleep]
        return MiKiduSnapshotV1(state: .ready, name: document.profile.displayName,
            isSleeping: document.care.resting, availableActions: actions,
            saveSync: problem != nil ? .error : .saved, message: problem)
    }
    func load() async {
        guard !busy else { return }
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
            let environment = try self.environment ?? KiduLocalEnvironment.app()
            try await environment.store.initialize(incoming, deviceID: environment.deviceID(create: true))
            self.environment = environment
            document = incoming
            problem = nil
            refreshWidgets()
            shareCompanionLink()
        } catch { problem = safeMessage(error) }
    }
    func perform(_ action: MiKiduAppActionV1) {
        if action == .reintentar { retry(); return }
        guard let care = KiduCareAction(rawValue: action.rawValue) else { return }
        run(care)
    }
    func perform(_ action: MiKiduSnapshotV1.Action) { run(action.coreAction) }
    func greet() { reaction += 1 }
    func retry() {
        if let action = lastFailedAction { run(action) }
        else { Task { await load() } }
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
    private func run(_ action: KiduCareAction) {
        guard !busy, let environment else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let result = try await environment.store.perform(action, deviceID: environment.deviceID())
                document = result.document
                reaction += 1
                lastFailedAction = nil
                problem = nil
                refreshWidgets()
            } catch {
                // perform es una transacción local: si lanza, no confirmó ninguna escritura.
                lastFailedAction = action
                problem = safeMessage(error)
            }
        }
    }
    private func configureCompanionLink() {
        #if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
        guard companionLink == nil else { return }
        let link = KiduCompanionLink()
        link.reportProblem = { [weak self] message in self?.problem = message }
        link.requestedDocument = { [weak self] in self?.shareCompanionLink() }
        link.receiveDocument = { [weak self] data in
            Task { @MainActor [weak self] in await self?.receiveCompanionLink(data) }
        }
        companionLink = link
        #endif
    }
    private func shareCompanionLink() {
        #if os(iOS)
        guard let document else { return }
        do { companionLink?.shareDocument(try JSONEncoder().encode(document)) }
        catch { problem = "No se pudo preparar el enlace del reloj." }
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

extension MiKiduSnapshotV1.Action {
    var coreAction: KiduCareAction {
        switch self {
        case .feed: .alimentar; case .drink: .beberAgua; case .pet: .acariciar
        case .play: .jugar; case .sleep: .dormir; case .wake: .despertar
        }
    }
}
