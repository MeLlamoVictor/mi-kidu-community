#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics

public enum MiKiduWindowGeometryErrorV1: Error, Equatable, Sendable {
    case accessibilityPermissionMissing
    case applicationUnavailable
    case geometryUnavailable
}

/// Reads only AX window frames, then checks on-screen frame/z-order metadata.
/// Never reads titles, values, text, children, screenshots, or tab attributes.
@MainActor
public final class MiKiduWindowMotionMacAdapterV1 {
    public private(set) var phase: MiKiduMotionPhaseV1 = .grounded
    private var machine = MiKiduWindowMotionMachineV1()
    private var motionTask: Task<Void, Never>?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var onPhaseChange: ((MiKiduMotionPhaseV1) -> Void)?
    private var currentPanel: NSWindow?
    private var currentDestination: MiKiduMotionAnchorV1?
    private var currentFloor: MiKiduMotionPointV1?
    private var currentDesktop: MiKiduMotionRectV1?

    public init() {}

    public func visibleWindowAnchors(processIdentifier: Int32) -> Result<[MiKiduMotionAnchorV1], MiKiduWindowGeometryErrorV1> {
        guard AXIsProcessTrusted() else { return .failure(.accessibilityPermissionMissing) }
        let application = AXUIElementCreateApplication(pid_t(processIdentifier))
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowValue) == .success,
              let axWindows = windowValue as? [AXUIElement] else {
            return .failure(.applicationUnavailable)
        }

        guard let rawList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return .failure(.geometryUnavailable)
        }
        let ordered = rawList.compactMap { entry -> (pid: Int32, number: UInt32, frame: CGRect, alpha: Double)? in
            guard let owner = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary else { return nil }
            var frame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds as CFDictionary, &frame), frame.width > 0, frame.height > 0 else { return nil }
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return (owner.int32Value, number.uint32Value, frame, alpha)
        }

        var anchors: [MiKiduMotionAnchorV1] = []
        for window in axWindows {
            guard let frame = axFrame(of: window), frame.isValid else { continue }
            let cgIndex = ordered.firstIndex {
                $0.pid == processIdentifier && nearlyEqual($0.frame, frame)
            }
            guard let cgIndex else {
                anchors.append(.init(identifier: "ax-window:\(processIdentifier):unknown:\(anchors.count)",
                                     source: .accessibilityWindow, frame: frame, visibility: .unknown,
                                     processIdentifier: processIdentifier))
                continue
            }
            let landingProbe = frame.topCenter.translated(y: -2)
            var covered = false
            for item in ordered.prefix(upTo: cgIndex) {
                let probe = CGPoint(x: landingProbe.x, y: landingProbe.y)
                if item.pid != Int32(getpid()), item.alpha > 0.02, item.frame.contains(probe) {
                    covered = true
                    break
                }
            }
            let windowNumber = ordered[cgIndex].number
            anchors.append(.init(identifier: "ax-window:\(processIdentifier):\(windowNumber)",
                                 source: .accessibilityWindow, frame: frame,
                                 visibility: covered ? .occluded : .visible,
                                 processIdentifier: processIdentifier, windowNumber: windowNumber))
        }
        return .success(anchors)
    }

    /// Starts one jump. AX permission is checked only for AX anchors; the check never prompts.
    @discardableResult
    public func move(panel: NSWindow, to destination: MiKiduMotionAnchorV1,
                     visibleDesktop: MiKiduMotionRectV1, safeFloor: MiKiduMotionPointV1,
                     sleeping: Bool, hostVisible: Bool,
                     onPhaseChange: ((MiKiduMotionPhaseV1) -> Void)? = nil) -> MiKiduMotionDecisionV1 {
        stop()
        guard hostVisible, panel.isVisible else {
            setPhase(.hidden)
            return .held(.hostHidden)
        }
        guard !sleeping else {
            setPhase(.sleeping)
            return .held(.sleeping)
        }

        var verified = destination
        if destination.source == .accessibilityWindow {
            guard let pid = destination.processIdentifier, let number = destination.windowNumber else {
                let decision = safeFloorDecision(safeFloor, visibleDesktop, panel.frame.size, .destinationUnknown)
                applySafeFloor(decision, to: panel)
                return decision
            }
            let readResult = visibleWindowAnchors(processIdentifier: pid)
            let currentAnchors: [MiKiduMotionAnchorV1]
            switch readResult {
            case let .success(anchors): currentAnchors = anchors
            case .failure(.accessibilityPermissionMissing):
                let decision = safeFloorDecision(safeFloor, visibleDesktop, panel.frame.size, .missingAccessibilityPermission)
                applySafeFloor(decision, to: panel)
                return decision
            case .failure:
                let decision = safeFloorDecision(safeFloor, visibleDesktop, panel.frame.size, .unavailableGeometry)
                applySafeFloor(decision, to: panel)
                return decision
            }
            guard let current = currentAnchors.first(where: { $0.windowNumber == number }) else {
                let decision = safeFloorDecision(safeFloor, visibleDesktop, panel.frame.size, .destinationUnknown)
                applySafeFloor(decision, to: panel)
                return decision
            }
            verified = current
        }

        let start = accessibilityCenter(of: panel.frame)
        let request = MiKiduWindowMotionRequestV1(
            start: start, destination: verified, visibleDesktop: visibleDesktop,
            safeFloor: safeFloor, panelWidth: panel.frame.width, panelHeight: panel.frame.height,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            sleeping: sleeping, hostVisible: hostVisible
        )
        let decision = machine.begin(request)
        switch decision {
        case let .animate(plan):
            self.currentPanel = panel
            self.currentDestination = verified
            self.currentFloor = safeFloor
            self.currentDesktop = visibleDesktop
            self.onPhaseChange = onPhaseChange
            if let pid = verified.processIdentifier { observeDestination(pid) }
            motionTask = Task { @MainActor [weak self, weak panel] in
                guard let self, let panel else { return }
                await self.animate(plan, on: panel)
            }
        case let .snap(point):
            setPanelCenter(point, on: panel)
            machine = MiKiduWindowMotionMachineV1()
            setPhase(.grounded)
        case .safeFloor:
            applySafeFloor(decision, to: panel)
        case .held:
            break
        }
        return decision
    }

    /// Call when the host hides or sleeps; no window checks or observers remain active afterward.
    public func stop(hostSleeping: Bool = false, hostVisible: Bool = true) {
        motionTask?.cancel()
        motionTask = nil
        removeObservers()
        if hostSleeping { machine.setSleeping(true); setPhase(.sleeping) }
        else if !hostVisible { machine.setHostVisible(false); setPhase(.hidden) }
        else if phase == .sleeping || phase == .hidden { machine = MiKiduWindowMotionMachineV1(); setPhase(.grounded) }
        currentPanel = nil; currentDestination = nil; currentFloor = nil; currentDesktop = nil; onPhaseChange = nil
    }

    @discardableResult
    public func invalidateCurrentDestination() -> MiKiduMotionDecisionV1 {
        guard let panel = currentPanel, let floor = currentFloor, let desktop = currentDesktop else {
            return .held(.destinationUnknown)
        }
        motionTask?.cancel(); motionTask = nil
        let decision = safeFloorDecision(floor, desktop, panel.frame.size, .invalidDestination)
        applySafeFloor(decision, to: panel)
        removeObservers()
        currentPanel = nil; currentDestination = nil; currentFloor = nil; currentDesktop = nil
        return decision
    }

    public static func accessibilityRect(from appKitRect: CGRect) -> MiKiduMotionRectV1? {
        guard let top = NSScreen.screens.first?.frame.maxY, appKitRect.width > 0, appKitRect.height > 0 else { return nil }
        return .init(x: appKitRect.minX, y: top - appKitRect.maxY,
                     width: appKitRect.width, height: appKitRect.height)
    }

    public static func safeFloorPoint(panelSize: CGSize, visibleFrame: CGRect) -> MiKiduMotionPointV1? {
        guard panelSize.width > 0, panelSize.height > 0,
              let bounds = accessibilityRect(from: visibleFrame), bounds.isValid else { return nil }
        return .init(x: bounds.center.x,
                     y: bounds.maxY - panelSize.height / 2 - 10)
    }

    public static func appKitCenter(fromAccessibility point: MiKiduMotionPointV1) -> CGPoint? {
        guard point.isFinite, let top = NSScreen.screens.first?.frame.maxY else { return nil }
        return CGPoint(x: point.x, y: top - point.y)
    }

    private func animate(_ plan: MiKiduWindowMotionPlanV1, on panel: NSWindow) async {
        setPhase(.anticipating)
        guard await animateTransition(from: plan.start, to: plan.start.translated(y: 5),
                                      duration: plan.anticipationDuration, on: panel) else { return }
        guard !Task.isCancelled, destinationIsStillVisible() else { abortToSafeFloor(on: panel); return }
        machine.advance(); setPhase(.flying)
        let steps = max(1, Int((plan.flightDuration * 30).rounded(.up)))
        let frameInterval: UInt64 = 1_000_000_000 / 30
        for index in 1...steps {
            guard !Task.isCancelled else { return }
            setPanelCenter(plan.point(at: Double(index) / Double(steps)), on: panel)
            if index == max(1, steps / 2), !destinationIsStillVisible() { abortToSafeFloor(on: panel); return }
            do { try await Task.sleep(nanoseconds: frameInterval) }
            catch { return }
        }
        guard !Task.isCancelled, destinationIsStillVisible() else { abortToSafeFloor(on: panel); return }
        machine.advance(); setPhase(.landing)
        let settled = plan.landing
        setPanelCenter(settled.translated(y: 4), on: panel)
        guard await animateTransition(from: settled.translated(y: 4), to: settled,
                                      duration: plan.landingDuration, on: panel) else { return }
        guard !Task.isCancelled, destinationIsStillVisible() else { abortToSafeFloor(on: panel); return }
        machine.advance(); setPhase(.recovering)
        do { try await Task.sleep(nanoseconds: UInt64(plan.recoveryDuration * 1_000_000_000)) }
        catch { return }
        guard !Task.isCancelled else { return }
        machine.advance(); setPhase(.grounded)
        removeObservers()
        currentPanel = nil; currentDestination = nil; currentFloor = nil; currentDesktop = nil; motionTask = nil
    }

    private func animateTransition(from start: MiKiduMotionPointV1, to end: MiKiduMotionPointV1,
                                   duration: Double, on panel: NSWindow) async -> Bool {
        let steps = max(1, Int((duration * 30).rounded(.up)))
        let frameInterval = UInt64(max(duration, 0.001) * 1_000_000_000 / Double(steps))
        for step in 1...steps {
            guard !Task.isCancelled else { return false }
            let raw = Double(step) / Double(steps)
            let eased = raw * raw * (3 - 2 * raw)
            setPanelCenter(.lerp(start, end, eased), on: panel)
            do { try await Task.sleep(nanoseconds: frameInterval) }
            catch { return false }
        }
        return !Task.isCancelled
    }

    private func destinationIsStillVisible() -> Bool {
        guard let destination = currentDestination else { return false }
        guard destination.source == .accessibilityWindow else { return destination.visibility == .visible }
        guard let pid = destination.processIdentifier, let number = destination.windowNumber,
              case let .success(anchors) = visibleWindowAnchors(processIdentifier: pid),
              let refreshed = anchors.first(where: { $0.windowNumber == number }) else { return false }
        return refreshed.visibility == .visible && nearlyEqual(refreshed.frame, destination.frame)
    }

    private func abortToSafeFloor(on panel: NSWindow) {
        guard !Task.isCancelled, let floor = currentFloor, let desktop = currentDesktop else { return }
        let decision = safeFloorDecision(floor, desktop, panel.frame.size, .invalidDestination)
        applySafeFloor(decision, to: panel)
        removeObservers()
        currentPanel = nil; currentDestination = nil; currentFloor = nil; currentDesktop = nil; motionTask = nil
    }

    private func setPanelCenter(_ center: MiKiduMotionPointV1, on panel: NSWindow) {
        guard let centerNS = Self.appKitCenter(fromAccessibility: center) else { return }
        panel.setFrameOrigin(CGPoint(x: centerNS.x - panel.frame.width / 2,
                                     y: centerNS.y - panel.frame.height / 2))
    }

    private func applySafeFloor(_ decision: MiKiduMotionDecisionV1, to panel: NSWindow) {
        if case let .safeFloor(point, _) = decision { setPanelCenter(point, on: panel) }
        machine = MiKiduWindowMotionMachineV1()
        setPhase(.safeFloor)
    }

    private func safeFloorDecision(_ point: MiKiduMotionPointV1, _ bounds: MiKiduMotionRectV1,
                                   _ panelSize: CGSize,
                                   _ reason: MiKiduMotionStopReasonV1) -> MiKiduMotionDecisionV1 {
        guard bounds.isValid else { return .held(.unavailableGeometry) }
        guard bounds.width >= panelSize.width, bounds.height >= panelSize.height else { return .held(.unavailableGeometry) }
        let proposed = point.isFinite ? point : .init(x: bounds.center.x, y: bounds.maxY - 1)
        return .safeFloor(bounds.clamped(proposed, insetX: panelSize.width / 2, insetY: panelSize.height / 2), reason)
    }

    private func setPhase(_ value: MiKiduMotionPhaseV1) {
        phase = value
        onPhaseChange?(value)
    }

    private func observeDestination(_ processIdentifier: Int32) {
        removeObservers()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [NSWorkspace.didDeactivateApplicationNotification,
                                             NSWorkspace.didHideApplicationNotification]
        for name in names {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier == pid_t(processIdentifier) else { return }
                Task { @MainActor [weak self] in self?.destinationDidEnterBackground() }
            }
            observers.append((workspaceCenter, token))
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop(hostSleeping: true) }
            }
            observers.append((workspaceCenter, token))
        }
        let appCenter = NotificationCenter.default
        let hideToken = appCenter.addObserver(forName: NSApplication.didHideNotification, object: NSApp, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop(hostVisible: false) }
        }
        observers.append((appCenter, hideToken))
    }

    private func destinationDidEnterBackground() {
        guard let panel = currentPanel, let floor = currentFloor, let desktop = currentDesktop else { return }
        motionTask?.cancel(); motionTask = nil
        let result = machine.destinationDidEnterBackground(safeFloor: floor, visibleDesktop: desktop)
        applySafeFloor(result, to: panel)
        removeObservers()
        currentPanel = nil; currentDestination = nil; currentFloor = nil; currentDesktop = nil
    }

    private func removeObservers() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    private func axFrame(of element: AXUIElement) -> MiKiduMotionRectV1? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let position = unsafeDowncast(positionValue, to: AXValue.self)
        let size = unsafeDowncast(sizeValue, to: AXValue.self)
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return .init(x: point.x, y: point.y, width: dimensions.width, height: dimensions.height)
    }

    private func nsRect(_ rect: MiKiduMotionRectV1) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    private func accessibilityCenter(of appKitFrame: CGRect) -> MiKiduMotionPointV1 {
        guard let top = NSScreen.screens.first?.frame.maxY else { return .init(x: .nan, y: .nan) }
        return .init(x: appKitFrame.midX, y: top - appKitFrame.midY)
    }

    private func nearlyEqual(_ a: CGRect, _ b: MiKiduMotionRectV1) -> Bool {
        abs(a.minX - b.x) < 3 && abs(a.minY - b.y) < 3 &&
        abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
    }

    private func nearlyEqual(_ a: MiKiduMotionRectV1, _ b: MiKiduMotionRectV1) -> Bool {
        abs(a.x - b.x) < 2 && abs(a.y - b.y) < 2 &&
        abs(a.width - b.width) < 2 && abs(a.height - b.height) < 2
    }
}
#endif
