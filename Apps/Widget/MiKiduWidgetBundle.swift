import AppIntents
import SwiftUI
import WidgetKit
import MiKiduCore
import MiKiduPresentation
import MiKiduWidgetWatch

private struct KiduWidgetEndpoint: MiKiduCareActionEndpointV1 {
    let environment: KiduLocalEnvironment?
    func snapshot() async throws -> MiKiduSnapshotV1 {
        guard let environment else { return MiKiduSnapshotV1(state: .unlinked) }
        do { return Self.project(try await environment.store.snapshot()) }
        catch KiduError.notInitialized { return MiKiduSnapshotV1(state: .unlinked) }
    }
    func performAndPersist(_ action: MiKiduSnapshotV1.Action) async throws {
        guard let environment else { throw KiduError.notInitialized }
        let care: KiduCareAction
        switch action {
        case .feed: care = .alimentar; case .drink: care = .beberAgua; case .pet: care = .acariciar
        case .play: care = .jugar; case .sleep: care = .dormir; case .wake: care = .despertar
        }
        _ = try await environment.store.perform(care, deviceID: environment.deviceID())
    }
    static func project(_ document: KiduDocument) -> MiKiduSnapshotV1 {
        MiKiduSnapshotV1(state: .ready, name: document.profile.displayName, isSleeping: document.care.resting,
            availableActions: document.care.resting ? [.wake, .pet] : [.feed, .drink, .pet, .play, .sleep], saveSync: .saved)
    }
}
private struct KiduEntry: TimelineEntry {
    let date: Date
    let snapshot: MiKiduSnapshotV1
    let profile: KiduProfile?
}
private struct KiduProvider: TimelineProvider {
    func placeholder(in context: Context) -> KiduEntry {
        KiduEntry(date: .now, snapshot: MiKiduSnapshotV1(state: .unlinked), profile: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping @Sendable (KiduEntry) -> Void) {
        Task { completion(await entry()) }
    }
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<KiduEntry>) -> Void) {
        Task { completion(Timeline(entries: [await entry()], policy: .never)) }
    }
    private func entry() async -> KiduEntry {
        guard let environment = KiduLocalEnvironment.shared() else {
            return KiduEntry(date: .now, snapshot: MiKiduSnapshotV1(state: .unlinked), profile: nil)
        }
        do {
            let document = try await environment.store.snapshot()
            return KiduEntry(date: .now, snapshot: KiduWidgetEndpoint.project(document), profile: document.profile)
        } catch KiduError.notInitialized {
            return KiduEntry(date: .now, snapshot: MiKiduSnapshotV1(state: .unlinked), profile: nil)
        } catch {
            return KiduEntry(date: .now, snapshot: MiKiduSnapshotV1(state: .error, message: "No se pudo cargar tu Kidu."), profile: nil)
        }
    }
}
struct MiKiduCareWidget: Widget {
    let kind = "MiKiduCare"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KiduProvider()) { entry in
            MiKiduWidgetViewV1(entry: MiKiduWidgetEntryV1(date: entry.date, snapshot: entry.snapshot), style: style(entry.profile))
        }
        .configurationDisplayName("Mi Kidu")
        .description("Cuida de tu Kidu.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
    @MainActor private func style(_ profile: KiduProfile?) -> MiKiduWidgetStyleV1 {
        MiKiduWidgetStyleV1(window: KiduTheme.window, card: KiduTheme.card, line: KiduTheme.line,
            text: KiduTheme.text, secondaryText: KiduTheme.text2, accent: KiduTheme.mint, onAccent: KiduTheme.onColor,
            eyebrow: KiduTheme.font(10, .semibold), title: KiduTheme.font(18, .heavy), body: KiduTheme.font(12), button: KiduTheme.font(13, .bold)) { snapshot in
            if let profile { AnyView(KiduAvatarView(profile: profile, resting: snapshot.isSleeping)) }
            else { AnyView(EmptyView()) }
        }
    }
}
@main
struct MiKiduWidgetBundle: WidgetBundle {
    init() {
        let endpoint: any MiKiduCareActionEndpointV1 = KiduWidgetEndpoint(environment: KiduLocalEnvironment.shared())
        AppDependencyManager.shared.add(dependency: endpoint)
    }
    var body: some Widget { MiKiduCareWidget() }
}
