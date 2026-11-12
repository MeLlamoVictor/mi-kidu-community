import SwiftUI

/// Superficie local de Watch. El target aporta un adaptador conectado al núcleo local.
@MainActor
public struct MiKiduWatchViewV1<Adapter: MiKiduLocalCareAdapterV1>: View {
    @ObservedObject private var adapter: Adapter
    private let style: MiKiduWidgetStyleV1

    public init(adapter: Adapter, style: MiKiduWidgetStyleV1) {
        self.adapter = adapter
        self.style = style
    }

    public var body: some View {
        let snapshot = adapter.snapshot
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("MI KIDU").font(style.eyebrow).tracking(1).foregroundStyle(style.secondaryText)
                if snapshot.state == .ready {
                    HStack(spacing: 8) {
                        style.figure(snapshot).frame(width: 52, height: 52).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(snapshot.name?.isEmpty == false ? snapshot.name! : "Tu Kidu")
                                .font(style.title).foregroundStyle(style.text).lineLimit(1)
                            saveStatus(snapshot).font(style.body).foregroundStyle(style.secondaryText)
                        }
                    }
                    ForEach(orderedActions(in: snapshot), id: \.rawValue) { careButton($0) }
                    if snapshot.saveSync == .error {
                        Text(snapshot.message ?? "No se pudo guardar")
                            .font(style.body).foregroundStyle(style.secondaryText)
                        Button("Reintentar") { adapter.retry() }
                            .font(style.button).frame(maxWidth: .infinity, minHeight: 44)
                            .buttonStyle(.borderedProminent).tint(style.accent)
                    }
                } else if snapshot.state == .unlinked {
                    Label(snapshot.message ?? "Kidu sin vincular", systemImage: "link")
                        .font(style.title).foregroundStyle(style.text)
                    Button("Enlazar") { adapter.link() }.buttonStyle(.borderedProminent).tint(style.accent)
                } else {
                    Label(snapshot.message ?? "Kidu no disponible", systemImage: "exclamationmark.triangle")
                        .font(style.body).foregroundStyle(style.text)
                    Button("Reintentar") { adapter.retry() }.buttonStyle(.borderedProminent).tint(style.accent)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .background(style.window)
    }

    private func careButton(_ action: MiKiduSnapshotV1.Action) -> some View {
        Button { adapter.perform(action) } label: {
            Label(action.title, systemImage: action.symbol)
                .font(style.button).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(action == preferredAction(in: adapter.snapshot) ? style.accent : style.card)
        .foregroundStyle(action == preferredAction(in: adapter.snapshot) ? style.onAccent : style.text)
        .accessibilityLabel(action.title)
    }

    private func preferredAction(in snapshot: MiKiduSnapshotV1) -> MiKiduSnapshotV1.Action? {
        let desired: [MiKiduSnapshotV1.Action] = snapshot.isSleeping ? [.wake, .feed, .drink, .pet, .play, .sleep] : [.feed, .drink, .pet, .play, .sleep, .wake]
        return desired.first(where: snapshot.availableActions.contains)
    }
    private func orderedActions(in snapshot: MiKiduSnapshotV1) -> [MiKiduSnapshotV1.Action] {
        let preferred: [MiKiduSnapshotV1.Action] = snapshot.isSleeping ? [.wake, .feed, .drink, .pet, .play, .sleep] : [.feed, .drink, .pet, .play, .sleep, .wake]
        return preferred.filter(snapshot.availableActions.contains)
    }
    @ViewBuilder private func saveStatus(_ snapshot: MiKiduSnapshotV1) -> some View {
        switch snapshot.saveSync {
        case .saved: Label("Guardado", systemImage: "checkmark.circle")
        case .pending: Label("Pendiente", systemImage: "clock")
        case .syncing: Label("Sincronizando", systemImage: "arrow.triangle.2.circlepath")
        case .offline: Label("Sin conexión", systemImage: "wifi.slash")
        case .error: Label("Error al guardar", systemImage: "exclamationmark.triangle")
        }
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
