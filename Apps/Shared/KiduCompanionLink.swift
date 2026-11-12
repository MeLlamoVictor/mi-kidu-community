#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
import Foundation
import WatchConnectivity

/// Alta inicial entre los dos targets propios emparejados por watchOS.
/// No sustituye estados existentes ni declara sincronización de acciones posteriores.
@MainActor
final class KiduCompanionLink: NSObject, WCSessionDelegate {
    var receiveDocument: ((Data) -> Void)?
    var requestedDocument: (() -> Void)?
    var reportProblem: ((String) -> Void)?
    private let session: WCSession
    override init() {
        session = .default
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }
    func requestLink() {
        guard session.activationState == .activated else {
            reportProblem?("El enlace con el iPhone aún no está listo."); return
        }
        session.transferUserInfo(["kiduLinkRequest": true])
    }
    func shareDocument(_ data: Data) {
        guard session.activationState == .activated else { return }
        do {
            if data.count < 48_000 {
                try session.updateApplicationContext(["kiduLinkDocument": data])
            } else {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MiKiduLinkTransfers", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let file = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
                try data.write(to: file, options: .atomic)
                session.transferFile(file, metadata: ["kiduLinkDocument": true])
            }
        } catch { reportProblem?("No se pudo enviar el enlace al reloj.") }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let succeeded = activationState == .activated && error == nil
        Task { @MainActor [weak self] in
            if succeeded {
                #if os(iOS)
                self?.requestedDocument?()
                #endif
            } else { self?.reportProblem?("No se pudo activar el enlace con el reloj.") }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["kiduLinkDocument"] as? Data, data.count <= 3_000_000 else { return }
        Task { @MainActor [weak self] in self?.receiveDocument?(data) }
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard userInfo["kiduLinkRequest"] as? Bool == true else { return }
        Task { @MainActor [weak self] in self?.requestedDocument?() }
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard file.metadata?["kiduLinkDocument"] as? Bool == true else { return }
        do {
            let size = try file.fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 3_000_000 else { return }
            let data = try Data(contentsOf: file.fileURL)
            Task { @MainActor [weak self] in self?.receiveDocument?(data) }
        } catch { Task { @MainActor [weak self] in self?.reportProblem?("No se pudo abrir el enlace de Kidu.") } }
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
#endif
