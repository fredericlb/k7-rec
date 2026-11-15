// App entry: one library, one recorder and one player, shared by every screen.
import SwiftUI

@main
struct RehearsalApp: App {
    @State private var model = AppModel.live()

    var body: some Scene {
        WindowGroup {
            RootView().environment(model)
        }
    }
}
