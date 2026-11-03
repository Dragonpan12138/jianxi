import SwiftUI

@main
@MainActor
struct JianxiApp: App {
    @StateObject private var model = LaundryViewModel()

    var body: some Scene {
        WindowGroup {
            LaundryRootView(model: model)
                .onOpenURL { AlipayPayment.shared.handle($0) }
        }
    }
}
