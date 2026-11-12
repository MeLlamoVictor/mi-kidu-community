import Foundation

public struct MiKiduMotionPointV1: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var isFinite: Bool { x.isFinite && y.isFinite }
    public func distance(to other: Self) -> Double { hypot(other.x - x, other.y - y) }
    public func translated(x dx: Double = 0, y dy: Double = 0) -> Self { .init(x: x + dx, y: y + dy) }
    public static func lerp(_ a: Self, _ b: Self, _ t: Double) -> Self {
        .init(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
}

public struct MiKiduMotionRectV1: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var isValid: Bool { x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var center: MiKiduMotionPointV1 { .init(x: x + width / 2, y: y + height / 2) }
    public var topCenter: MiKiduMotionPointV1 { .init(x: x + width / 2, y: y) }
    public func contains(_ point: MiKiduMotionPointV1) -> Bool {
        isValid && point.x >= x && point.x <= maxX && point.y >= y && point.y <= maxY
    }
    public func intersects(_ other: Self) -> Bool {
        isValid && other.isValid && x < other.maxX && maxX > other.x && y < other.maxY && maxY > other.y
    }
    public func clamped(_ point: MiKiduMotionPointV1, insetX: Double = 0, insetY: Double = 0) -> MiKiduMotionPointV1 {
        .init(x: min(max(point.x, x + insetX), maxX - insetX),
              y: min(max(point.y, y + insetY), maxY - insetY))
    }
}

public enum MiKiduMotionAnchorSourceV1: String, Codable, Sendable { case ownShellSemantic, accessibilityWindow }
public enum MiKiduMotionAnchorVisibilityV1: String, Codable, Sendable { case visible, occluded, unknown, minimized }

/// An anchor from the app's own shell may describe a named control/edge. AX anchors describe windows only.
public struct MiKiduMotionAnchorV1: Codable, Equatable, Sendable {
    public var identifier: String
    public var source: MiKiduMotionAnchorSourceV1
    public var frame: MiKiduMotionRectV1
    public var visibility: MiKiduMotionAnchorVisibilityV1
    public var processIdentifier: Int32?
    public var windowNumber: UInt32?

    public init(identifier: String, source: MiKiduMotionAnchorSourceV1,
                frame: MiKiduMotionRectV1, visibility: MiKiduMotionAnchorVisibilityV1,
                processIdentifier: Int32? = nil, windowNumber: UInt32? = nil) {
        self.identifier = identifier; self.source = source; self.frame = frame
        self.visibility = visibility; self.processIdentifier = processIdentifier; self.windowNumber = windowNumber
    }
    public static func semantic(identifier: String, frame: MiKiduMotionRectV1) -> Self {
        .init(identifier: identifier, source: .ownShellSemantic, frame: frame, visibility: .visible)
    }
}

public enum MiKiduMotionPhaseV1: String, Codable, Sendable {
    case grounded, anticipating, flying, landing, recovering, safeFloor, sleeping, hidden
}
public enum MiKiduMotionStopReasonV1: String, Codable, Sendable {
    case invalidDestination, coveredDestination, destinationUnknown, destinationBackground,
         hostHidden, sleeping, reducedMotion, missingAccessibilityPermission, unavailableGeometry
}

public struct MiKiduWindowMotionPlanV1: Codable, Equatable, Sendable {
    public let start: MiKiduMotionPointV1
    public let control1: MiKiduMotionPointV1
    public let control2: MiKiduMotionPointV1
    public let landing: MiKiduMotionPointV1
    public let effort: Double
    public let distance: Double
    public let anticipationDuration: Double
    public let flightDuration: Double
    public let landingDuration: Double
    public let recoveryDuration: Double
    public let destinationIdentifier: String

    public func point(at progress: Double) -> MiKiduMotionPointV1 {
        let t = min(max(progress, 0), 1)
        let u = 1 - t
        let a = u * u * u
        let b = 3 * u * u * t
        let c = 3 * u * t * t
        let d = t * t * t
        return MiKiduMotionPointV1(
            x: a * start.x + b * control1.x + c * control2.x + d * landing.x,
            y: a * start.y + b * control1.y + c * control2.y + d * landing.y
        )
    }
}

public enum MiKiduMotionDecisionV1: Equatable, Sendable {
    case animate(MiKiduWindowMotionPlanV1)
    case snap(MiKiduMotionPointV1)
    case safeFloor(MiKiduMotionPointV1, MiKiduMotionStopReasonV1)
    case held(MiKiduMotionStopReasonV1)
}

public struct MiKiduWindowMotionRequestV1: Sendable {
    public let start: MiKiduMotionPointV1
    public let destination: MiKiduMotionAnchorV1
    public let visibleDesktop: MiKiduMotionRectV1
    public let safeFloor: MiKiduMotionPointV1
    public let panelWidth: Double
    public let panelHeight: Double
    public let reduceMotion: Bool
    public let sleeping: Bool
    public let hostVisible: Bool

    public init(start: MiKiduMotionPointV1, destination: MiKiduMotionAnchorV1,
                visibleDesktop: MiKiduMotionRectV1, safeFloor: MiKiduMotionPointV1,
                panelWidth: Double, panelHeight: Double, reduceMotion: Bool,
                sleeping: Bool, hostVisible: Bool) {
        self.start = start; self.destination = destination; self.visibleDesktop = visibleDesktop
        self.safeFloor = safeFloor; self.panelWidth = panelWidth; self.panelHeight = panelHeight; self.reduceMotion = reduceMotion
        self.sleeping = sleeping; self.hostVisible = hostVisible
    }
}

/// Pure deterministic planner and phase machine. The caller owns timing, drawing, and persistence.
public struct MiKiduWindowMotionMachineV1: Sendable {
    public private(set) var phase: MiKiduMotionPhaseV1 = .grounded
    public private(set) var activePlan: MiKiduWindowMotionPlanV1?
    private var phaseSequence: [MiKiduMotionPhaseV1] = []
    private var phaseIndex = 0
    private var activePanelWidth = 1.0
    private var activePanelHeight = 1.0

    public init() {}

    public mutating func begin(_ request: MiKiduWindowMotionRequestV1) -> MiKiduMotionDecisionV1 {
        activePlan = nil; phaseSequence = []; phaseIndex = 0
        activePanelWidth = 1; activePanelHeight = 1
        guard request.hostVisible else { phase = .hidden; return .held(.hostHidden) }
        guard !request.sleeping else { phase = .sleeping; return .held(.sleeping) }
        guard request.visibleDesktop.isValid, request.safeFloor.isFinite else {
            phase = .grounded
            return .held(.unavailableGeometry)
        }
        guard request.panelWidth.isFinite, request.panelWidth > 0,
              request.panelHeight.isFinite, request.panelHeight > 0 else {
            phase = .grounded
            return .held(.unavailableGeometry)
        }
        guard request.visibleDesktop.width >= request.panelWidth,
              request.visibleDesktop.height >= request.panelHeight else {
            phase = .grounded
            return .held(.unavailableGeometry)
        }
        activePanelWidth = request.panelWidth
        activePanelHeight = request.panelHeight

        let landing = request.destination.frame.topCenter.translated(y: -request.panelHeight / 2)
        let contact = request.destination.frame.topCenter
        let reason: MiKiduMotionStopReasonV1?
        if !request.destination.frame.isValid || !landing.isFinite { reason = .invalidDestination }
        else if request.destination.visibility == .occluded { reason = .coveredDestination }
        else if request.destination.visibility != .visible { reason = .destinationUnknown }
        else if !request.visibleDesktop.contains(contact) ||
                    landing.x - request.panelWidth / 2 < request.visibleDesktop.x ||
                    landing.x + request.panelWidth / 2 > request.visibleDesktop.maxX ||
                    landing.y - request.panelHeight / 2 < request.visibleDesktop.y ||
                    landing.y + request.panelHeight / 2 > request.visibleDesktop.maxY { reason = .invalidDestination }
        else { reason = nil }

        if let reason {
            let floor = safePoint(request.safeFloor, in: request.visibleDesktop)
            phase = .safeFloor
            phaseSequence = [.grounded]
            return .safeFloor(floor, reason)
        }
        if request.reduceMotion {
            phase = .grounded
            return .snap(landing)
        }
        guard request.start.isFinite else {
            let floor = safePoint(request.safeFloor, in: request.visibleDesktop)
            phase = .safeFloor
            return .safeFloor(floor, .invalidDestination)
        }

        let distance = request.start.distance(to: landing)
        let effort = min(max(distance / 900, 0.12), 1)
        let arcHeight = min(max(distance * 0.22, 40), 190)
        let pathBounds = MiKiduMotionRectV1(
            x: request.visibleDesktop.x + request.panelWidth / 2,
            y: request.visibleDesktop.y + request.panelHeight / 2,
            width: request.visibleDesktop.width - request.panelWidth,
            height: request.visibleDesktop.height - request.panelHeight
        )
        guard pathBounds.contains(request.start) else {
            let floor = safePoint(request.safeFloor, in: request.visibleDesktop)
            phase = .safeFloor
            return .safeFloor(floor, .invalidDestination)
        }
        let rawControl1 = MiKiduMotionPointV1(
            x: request.start.x + (landing.x - request.start.x) * 0.27,
            y: min(request.start.y, landing.y) - arcHeight
        )
        let rawControl2 = MiKiduMotionPointV1(
            x: request.start.x + (landing.x - request.start.x) * 0.73,
            y: min(request.start.y, landing.y) - arcHeight * 0.72
        )
        let plan = MiKiduWindowMotionPlanV1(
            start: request.start,
            control1: pathBounds.clamped(rawControl1),
            control2: pathBounds.clamped(rawControl2),
            landing: landing,
            effort: effort,
            distance: distance,
            anticipationDuration: 0.10 + 0.20 * effort,
            flightDuration: 0.24 + 0.76 * effort,
            landingDuration: 0.10 + 0.16 * effort,
            recoveryDuration: 0.16 + 0.18 * effort,
            destinationIdentifier: request.destination.identifier
        )
        activePlan = plan
        phase = .anticipating
        phaseSequence = [.anticipating, .flying, .landing, .recovering, .grounded]
        phaseIndex = 0
        return .animate(plan)
    }

    @discardableResult
    public mutating func advance() -> MiKiduMotionPhaseV1 {
        guard phaseIndex + 1 < phaseSequence.count else {
            phase = phase == .safeFloor ? .grounded : phase
            activePlan = nil
            return phase
        }
        phaseIndex += 1
        phase = phaseSequence[phaseIndex]
        if phase == .grounded { activePlan = nil; phaseSequence = []; phaseIndex = 0 }
        return phase
    }

    public mutating func destinationDidEnterBackground(safeFloor: MiKiduMotionPointV1,
                                                        visibleDesktop: MiKiduMotionRectV1) -> MiKiduMotionDecisionV1 {
        guard [.anticipating, .flying, .landing, .recovering].contains(phase) else {
            return .held(phase == .sleeping ? .sleeping : .hostHidden)
        }
        activePlan = nil; phaseSequence = [.grounded]; phaseIndex = 0; phase = .safeFloor
        return .safeFloor(safePoint(safeFloor, in: visibleDesktop), .destinationBackground)
    }

    public mutating func setSleeping(_ sleeping: Bool) {
        if sleeping { activePlan = nil; phaseSequence = []; phase = .sleeping }
        else if phase == .sleeping { phase = .grounded }
    }

    public mutating func setHostVisible(_ visible: Bool) {
        if !visible { activePlan = nil; phaseSequence = []; phase = .hidden }
        else if phase == .hidden { phase = .grounded }
    }

    private func safePoint(_ proposed: MiKiduMotionPointV1,
                           in bounds: MiKiduMotionRectV1) -> MiKiduMotionPointV1 {
        guard bounds.isValid else { return .init(x: 0, y: 0) }
        let point = proposed.isFinite ? proposed : .init(x: bounds.center.x, y: bounds.maxY - 1)
        return bounds.clamped(point, insetX: activePanelWidth / 2, insetY: activePanelHeight / 2)
    }
}
