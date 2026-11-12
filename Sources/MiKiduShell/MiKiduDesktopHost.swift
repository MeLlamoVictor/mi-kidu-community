#if os(macOS)
import AppKit
import SwiftUI
#if canImport(MiKiduWindowMotion)
import MiKiduWindowMotion
#endif

/// Panel superior no activador. No captura pantalla, inspecciona otras apps ni solicita permisos de Accesibilidad.
@MainActor
public final class MiKiduDesktopHost: NSObject, NSWindowDelegate {
    public private(set) var panel: NSPanel?
    public private(set) var presence: MiKiduPanelPresence = .cerrado

    private var hostingView: MiKiduPassthroughHostingView<AnyView>?
    private var displayObserver: MiKiduNotificationObserverToken?
    private var pantallaID: NSNumber?
#if canImport(MiKiduWindowMotion)
    private let motionAdapter = MiKiduWindowMotionMacAdapterV1()
#endif

    public override init() {
        super.init()
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recolocar() }
        }
        displayObserver = MiKiduNotificationObserverToken(center: center, token: token)
    }

    public func mostrar<Adapter: MiKiduAppAdapterV1, Figura: View, MenuContent: View>(
        adapter: Adapter,
        theme: MiKiduShellThemeV1,
        @ViewBuilder menu: (Adapter, MiKiduShellThemeV1, @escaping () -> Void) -> MenuContent,
        @ViewBuilder figura: @escaping () -> Figura
    ) {
        cerrar()
        guard adapter.presentation.identidad == .disponible else { return }
        guard let pantalla = pantallaInicial() else { return }

        let onCerrar: () -> Void = { [weak self] in
            guard let self else { return }
            self.cerrar()
        }
        let menuView = menu(adapter, theme, onCerrar)
        let vista = MiKiduDesktopPanelRoot(adapter: adapter, menu: menuView,
                                           onCerrar: onCerrar, figura: figura)
        let host = MiKiduPassthroughHostingView(rootView: AnyView(vista))
        host.allowedHitRects = [MiKiduPanelGeometry.avatarHitRectTopLeft, MiKiduPanelGeometry.menuHitRectTopLeft]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.frame = CGRect(origin: .zero, size: MiKiduPanelGeometry.size)

        let frame = CGRect(origin: MiKiduPanelGeometry.origin(visibleFrame: pantalla.visibleFrame),
                           size: MiKiduPanelGeometry.size)
        let ventana = MiKiduNonActivatingPanel(contentRect: frame,
                                               styleMask: [.borderless, .nonactivatingPanel],
                                               backing: .buffered, defer: false)
        ventana.isOpaque = false
        ventana.backgroundColor = .clear
        ventana.hasShadow = false
        ventana.level = .floating
        ventana.isFloatingPanel = true
        ventana.ignoresMouseEvents = false
        ventana.hidesOnDeactivate = false
        ventana.isReleasedWhenClosed = false
        ventana.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        ventana.delegate = self
        ventana.contentView = host

        panel = ventana
        hostingView = host
        pantallaID = pantalla.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        presence = .visible
        ventana.orderFrontRegardless()
    }

    public func actualizar<Adapter: MiKiduAppAdapterV1, Figura: View, MenuContent: View>(
        adapter: Adapter,
        theme: MiKiduShellThemeV1,
        @ViewBuilder menu: (Adapter, MiKiduShellThemeV1, @escaping () -> Void) -> MenuContent,
        @ViewBuilder figura: @escaping () -> Figura
    ) {
        guard adapter.presentation.identidad == .disponible else { cerrar(); return }
        guard let hostingView else { return }
        let onCerrar: () -> Void = { [weak self] in
            guard let self else { return }
            self.cerrar()
        }
        let menuView = menu(adapter, theme, onCerrar)
        hostingView.rootView = AnyView(MiKiduDesktopPanelRoot(
            adapter: adapter, menu: menuView, onCerrar: onCerrar, figura: figura
        ))
    }

    public func cerrar() {
#if canImport(MiKiduWindowMotion)
        motionAdapter.stop(hostVisible: false)
#endif
        presence = .cerrado
        panel?.delegate = nil
        panel?.contentView = nil
        panel?.close()
        panel = nil
        hostingView = nil
        pantallaID = nil
    }

#if canImport(MiKiduWindowMotion)
    /// AX devuelve ventanas y geometría, nunca pestañas. Si falta permiso el resultado no contiene anclas.
    public func anclasDeVentanasVisibles(proceso pid: Int32) -> Result<[MiKiduMotionAnchorV1], MiKiduWindowGeometryErrorV1> {
        motionAdapter.visibleWindowAnchors(processIdentifier: pid)
    }

    /// Inicia el salto si el destino sigue visible. Destinos inválidos/tapados terminan en el suelo seguro.
    @discardableResult
    public func saltar(a ancla: MiKiduMotionAnchorV1, dormido: Bool = false) -> MiKiduMotionDecisionV1 {
        guard let panel, let screen = panel.screen,
              let visibleDesktop = MiKiduWindowMotionMacAdapterV1.accessibilityRect(from: screen.visibleFrame),
              let safeFloor = MiKiduWindowMotionMacAdapterV1.safeFloorPoint(
                panelSize: panel.frame.size, visibleFrame: screen.visibleFrame
              ) else { return .held(.unavailableGeometry) }
        return motionAdapter.move(panel: panel, to: ancla, visibleDesktop: visibleDesktop,
                                  safeFloor: safeFloor, sleeping: dormido,
                                  hostVisible: panel.isVisible)
    }

    /// El coordinador llama esto al dormir/ocultar; no se mantiene vigilancia de ventanas.
    public func detenerMovimiento(dormido: Bool = false, visible: Bool = true) {
        motionAdapter.stop(hostSleeping: dormido, hostVisible: visible)
    }
#endif

    public func windowDidChangeScreen(_ notification: Notification) {
        guard let pantalla = panel?.screen else { return }
        pantallaID = pantalla.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        recolocar()
    }

    public func windowDidResignKey(_ notification: Notification) {
        // El panel no se convierte en key ni activa la aplicación; aquí no se pausa el renderer.
    }

    private func pantallaInicial() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        return screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? screens.first
    }

    private func recolocar() {
        guard let panel else { return }
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let pantallaGuardada = screens.first {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == pantallaID
        }
        let pantalla = pantallaGuardada ?? pantallaInicial() ?? screens[0]
        pantallaID = pantalla.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let limitado = MiKiduPanelGeometry.limitar(panel.frame, a: pantalla.visibleFrame)
        panel.setFrame(limitado, display: true, animate: false)
    }
}

private struct MiKiduDesktopPanelRoot<Adapter: MiKiduAppAdapterV1, Figura: View, MenuContent: View>: View {
    @ObservedObject var adapter: Adapter
    let menu: MenuContent
    var onCerrar: () -> Void
    @ViewBuilder var figura: () -> Figura

    init(adapter: Adapter, menu: MenuContent,
         onCerrar: @escaping () -> Void, figura: @escaping () -> Figura) {
        self.adapter = adapter
        self.menu = menu
        self.onCerrar = onCerrar
        self.figura = figura
    }

    var body: some View {
        HStack(spacing: 8) {
            figura()
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
                .accessibilityLabel("Mi Kidu de \(adapter.presentation.nombre ?? "Tu Kidu")")
            menu
        }
        .padding(4)
        .frame(width: MiKiduPanelGeometry.size.width, height: MiKiduPanelGeometry.size.height)
        .background(Color.clear)
        .onChange(of: adapter.presentation) { _, presentation in
            guard presentation.identidad == .disponible else { onCerrar(); return }
        }
    }
}

private final class MiKiduNonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class MiKiduPassthroughHostingView<Content: View>: NSHostingView<Content> {
    var allowedHitRects: [CGRect] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        let x = point.x - bounds.minX
        let y = isFlipped ? point.y - bounds.minY : bounds.maxY - point.y
        let topLeft = CGPoint(x: x, y: y)
        guard allowedHitRects.contains(where: { $0.contains(topLeft) }) else { return nil }
        return super.hitTest(point)
    }
}

/// Owns the non-Sendable Foundation observer token and unregisters it on any deinit executor.
private final class MiKiduNotificationObserverToken: @unchecked Sendable {
    private let center: NotificationCenter
    private let token: NSObjectProtocol
    init(center: NotificationCenter, token: NSObjectProtocol) { self.center = center; self.token = token }
    deinit { center.removeObserver(token) }
}
#endif
