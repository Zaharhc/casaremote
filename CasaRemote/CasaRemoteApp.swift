import SwiftUI

@main
struct CasaRemoteApp: App {
    @StateObject private var api = CasaAPI()
    var body: some Scene {
        WindowGroup {
            if api.isLoggedIn {
                MainView().environmentObject(api)
            } else {
                LoginView().environmentObject(api)
            }
        }
    }
}
