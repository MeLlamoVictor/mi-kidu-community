import SwiftUI
import MiKiduWidgetWatch
@main
struct MiKiduWatchApp: App {
    @StateObject private var model = KiduAppModel()
    var body: some Scene {
        WindowGroup {
            MiKiduWatchViewV1(adapter: model, style: kiduSurfaceStyle(profile: model.document?.profile, reaction: model.reaction))
                .task { await model.load() }
        }
    }
}
