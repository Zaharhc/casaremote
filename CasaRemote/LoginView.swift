import SwiftUI

struct LoginView: View {
    @EnvironmentObject var api: CasaAPI
    @State private var url = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Сервер") {
                    TextField("192.168.1.10 или https://casa.example.com", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("Аккаунт CasaOS") {
                    TextField("Логин", text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Пароль", text: $pass)
                }
                if let err { Text(err).foregroundStyle(.red) }
                Button {
                    Task { await go() }
                } label: {
                    if busy { ProgressView() } else { Text("Войти").frame(maxWidth: .infinity) }
                }
                .disabled(busy || url.isEmpty || user.isEmpty || pass.isEmpty)
            }
            .navigationTitle("CasaRemote")
        }
        .onAppear { url = api.baseURL; user = api.username }
    }

    func go() async {
        busy = true; err = nil
        do { try await api.login(url: url, user: user, pass: pass) }
        catch { err = error.localizedDescription }
        busy = false
    }
}
