import SwiftUI
@main
struct MiKiduApp: App {
    @StateObject private var model = KiduAppModel()
    var body: some Scene { WindowGroup { KiduExperience(model: model) } }
}
