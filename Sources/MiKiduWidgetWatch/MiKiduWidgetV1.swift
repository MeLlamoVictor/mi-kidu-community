#if os(iOS) || os(macOS)
import AppIntents
import SwiftUI
import WidgetKit

public struct MiKiduWidgetEntryV1: TimelineEntry, Sendable {
    public let date: Date
    public let snapshot: MiKiduSnapshotV1
    public init(date: Date, snapshot: MiKiduSnapshotV1) { self.date = date; self.snapshot = snapshot }
}

public struct MiKiduWidgetProviderV1: TimelineProvider {
    private let snapshotLoader: @Sendable () async throws -> MiKiduSnapshotV1
    public init(snapshotLoader: @escaping @Sendable () async throws -> MiKiduSnapshotV1) {
        self.snapshotLoader = snapshotLoader
    }
    public func placeholder(in context: Context) -> MiKiduWidgetEntryV1 {
        MiKiduWidgetEntryV1(date: .now, snapshot: MiKiduSnapshotV1(state: .unlinked))
    }
    public func getSnapshot(in context: Context, completion: @escaping @Sendable (MiKiduWidgetEntryV1) -> Void) {
        let loader = snapshotLoader
        Task {
            let snapshot = await Self.currentSnapshot(using: loader)
            completion(MiKiduWidgetEntryV1(date: .now, snapshot: snapshot))
        }
    }
    public func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<MiKiduWidgetEntryV1>) -> Void) {
        let loader = snapshotLoader
        Task {
            let snapshot = await Self.currentSnapshot(using: loader)
            completion(Timeline(entries: [MiKiduWidgetEntryV1(date: .now, snapshot: snapshot)], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
    private static func currentSnapshot(using loader: @Sendable () async throws -> MiKiduSnapshotV1) async -> MiKiduSnapshotV1 {
        do { return try await loader() }
        catch { return MiKiduSnapshotV1(state: .error, message: "No se pudo cargar el estado") }
    }
}

/// Vista entregada al WidgetConfiguration del target. No incluye `@main` ni crea el target.
public struct MiKiduWidgetViewV1: View {
    public let entry: MiKiduWidgetEntryV1
    public let style: MiKiduWidgetStyleV1
    @Environment(\.widgetFamily) private var family

    public init(entry: MiKiduWidgetEntryV1, style: MiKiduWidgetStyleV1) {
        self.entry = entry
        self.style = style
    }

    public var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if snapshot.state == .ready { style.figure(snapshot).frame(width: family == .systemSmall ? 48 : 64, height: family == .systemSmall ? 48 : 64) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("MI KIDU").font(style.eyebrow).tracking(1.2).foregroundStyle(style.secondaryText)
                    Text(title(for: snapshot)).font(style.title).foregroundStyle(style.text).lineLimit(2)
                    status(for: snapshot).font(style.body).foregroundStyle(style.secondaryText)
                }
            }
            if snapshot.state == .ready {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: family == .systemLarge ? 3 : family == .systemMedium ? 2 : 1), spacing: 8) {
                    ForEach(actions(for: snapshot), id: \.rawValue) { action in
                        Button(intent: MiKiduWidgetCareActionIntent(actionCode: action.rawValue)) {
                            Label(action.title, systemImage: action.symbol)
                                .font(style.button).lineLimit(1).minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                        .background(action == actions(for: snapshot).first ? style.accent : style.card,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(action == actions(for: snapshot).first ? style.onAccent : style.text)
                        .accessibilityLabel(action.title)
                    }
                }
            } else if snapshot.state == .unlinked {
                Button(intent: MiKiduOpenAppIntent()) {
                    Label("Enlazar", systemImage: "link").font(style.button)
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain).background(style.accent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(style.onAccent)
            } else {
                Button(intent: MiKiduOpenAppIntent()) {
                    Label("Reintentar", systemImage: "arrow.clockwise")
                        .font(style.button).frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(.plain).background(style.card, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(style.text)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(style.window)
        .containerBackground(for: .widget) { style.window }
    }

    private func title(for snapshot: MiKiduSnapshotV1) -> String {
        switch snapshot.state {
        case .unlinked: "Kidu sin vincular"
        case .ready: snapshot.name?.isEmpty == false ? snapshot.name! : "Tu Kidu"
        case .error: "Kidu no disponible"
        }
    }
    @ViewBuilder private func status(for snapshot: MiKiduSnapshotV1) -> some View {
        switch snapshot.state {
        case .unlinked: Label("Enlaza Mi Kidu", systemImage: "link")
        case .error: Label(snapshot.message ?? "No se pudo cargar", systemImage: "exclamationmark.triangle")
        case .ready:
            switch snapshot.saveSync {
            case .saved: Label("Guardado", systemImage: "checkmark.circle")
            case .pending: Label("Pendiente", systemImage: "clock")
            case .syncing: Label("Sincronizando", systemImage: "arrow.triangle.2.circlepath")
            case .offline: Label("Sin conexión", systemImage: "wifi.slash")
            case .error: Label("Error al guardar", systemImage: "exclamationmark.triangle")
            }
        }
    }
    private func actions(for snapshot: MiKiduSnapshotV1) -> [MiKiduSnapshotV1.Action] {
        let preferred: [MiKiduSnapshotV1.Action] = snapshot.isSleeping ? [.wake, .feed, .drink, .pet, .play, .sleep] : [.feed, .drink, .pet, .play, .sleep, .wake]
        let limit = family == .systemLarge || family == .systemExtraLarge ? 6 : family == .systemMedium ? 2 : 1
        return preferred.filter(snapshot.availableActions.contains).prefix(limit).map { $0 }
    }
}

private extension MiKiduSnapshotV1.Action {
    var title: String {
        switch self { case .feed: "Alimentar"; case .drink: "Agua"; case .pet: "Acariciar"; case .play: "Jugar"; case .sleep: "Dormir"; case .wake: "Despertar" }
    }
    var symbol: String {
        switch self { case .feed: "fork.knife"; case .drink: "drop.fill"; case .pet: "hand.draw"; case .play: "figure.play"; case .sleep: "moon.zzz"; case .wake: "sun.max" }
    }
}

public struct MiKiduWidgetCareActionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Cuidar de Kidu"
    public static let openAppWhenRun = false
    @Parameter(title: "Acción") public var actionCode: String
    @Dependency private var endpoint: any MiKiduCareActionEndpointV1
    public init() { actionCode = MiKiduSnapshotV1.Action.feed.rawValue }
    public init(actionCode: String) { self.actionCode = actionCode }
    public func perform() async throws -> some IntentResult {
        guard let action = MiKiduSnapshotV1.Action(rawValue: actionCode) else { throw MiKiduWidgetActionErrorV1.invalidAction }
        let snapshot: MiKiduSnapshotV1
        do { snapshot = try await endpoint.snapshot() }
        catch { throw MiKiduWidgetActionErrorV1.unavailable }
        guard snapshot.state == .ready else {
            throw MiKiduWidgetActionErrorV1.unavailable
        }
        guard snapshot.availableActions.contains(action) else { throw MiKiduWidgetActionErrorV1.actionUnavailable }
        do { try await endpoint.performAndPersist(action) }
        catch { throw MiKiduWidgetActionErrorV1.persistenceFailed }
        return .result()
    }
}

private enum MiKiduWidgetActionErrorV1: LocalizedError {
    case invalidAction, unavailable, actionUnavailable, persistenceFailed
    var errorDescription: String? {
        switch self {
        case .invalidAction: "Esta acción no está disponible."
        case .unavailable: "No se pudo cargar el estado de Kidu."
        case .actionUnavailable: "Esta acción no está disponible ahora."
        case .persistenceFailed: "No se pudo guardar la acción. Vuelve a intentarlo."
        }
    }
}

public struct MiKiduOpenAppIntent: AppIntent {
    public static let title: LocalizedStringResource = "Enlazar Mi Kidu"
    public static let openAppWhenRun = true
    public init() {}
    public func perform() async throws -> some IntentResult { .result() }
}
#endif
