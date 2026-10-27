import SwiftUI
import WebKit

struct MainView: View {
    @EnvironmentObject var api: CasaAPI
    var body: some View {
        TabView {
            DashboardView().tabItem { Label("Система", systemImage: "gauge") }
            AppsView().tabItem { Label("Приложения", systemImage: "square.grid.2x2") }
            WebUIView().tabItem { Label("Web UI", systemImage: "globe") }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var api: CasaAPI
    @State private var s = Stats()
    @State private var err: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Сервер") { Text(api.baseURL).foregroundStyle(.secondary) }
                Section("Нагрузка") {
                    row("CPU", s.cpu, "\(Int(s.cpu))%")
                    row("RAM", s.memPercent,
                        String(format: "%.1f / %.1f ГБ", s.memUsed / 1e9, s.memTotal / 1e9))
                    if let t = s.temp, t > 0 {
                        HStack { Text("Температура"); Spacer(); Text("\(Int(t)) °C") }
                    }
                }
                if let err { Text(err).foregroundStyle(.red) }
                Section { Button("Выйти", role: .destructive) { api.logout() } }
            }
            .navigationTitle("Система")
        }
        .task {
            while !Task.isCancelled {
                do { s = try await api.stats(); err = nil }
                catch { err = error.localizedDescription }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func row(_ name: String, _ pct: Double, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(name); Spacer(); Text(label).foregroundStyle(.secondary) }
            ProgressView(value: min(max(pct, 0), 100), total: 100)
        }
    }
}

struct AppsView: View {
    @EnvironmentObject var api: CasaAPI
    @State private var items: [AppItem] = []
    @State private var err: String?
    @State private var busyID: String?

    var body: some View {
        NavigationStack {
            List {
                if let err { Text(err).foregroundStyle(.red) }
                ForEach(items) { app in
                    HStack(spacing: 12) {
                        AsyncImage(url: app.icon) { img in img.resizable().scaledToFit() }
                            placeholder: { Image(systemName: "shippingbox") }
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading) {
                            Text(app.title)
                            Text(app.running ? "Работает" : "Остановлено")
                                .font(.caption)
                                .foregroundStyle(app.running ? .green : .secondary)
                        }
                        Spacer()
                        if busyID == app.id { ProgressView() }
                        else {
                            Menu {
                                if app.running {
                                    Button("Перезапустить", systemImage: "arrow.clockwise") { act(app, "restart") }
                                    Button("Остановить", systemImage: "stop.fill") { act(app, "stop") }
                                } else {
                                    Button("Запустить", systemImage: "play.fill") { act(app, "start") }
                                }
                            } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                        }
                    }
                }
            }
            .navigationTitle("Приложения")
            .refreshable { await load() }
        }
        .task { await load() }
    }

    func load() async {
        do { items = try await api.apps(); err = nil }
        catch { err = error.localizedDescription }
    }

    func act(_ app: AppItem, _ action: String) {
        busyID = app.id
        Task {
            do { try await api.control(app.id, action); err = nil }
            catch { err = error.localizedDescription }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await load()
            busyID = nil
        }
    }
}

struct WebUIView: View {
    @EnvironmentObject var api: CasaAPI
    var body: some View {
        WebView(url: URL(string: api.baseURL)).ignoresSafeArea(edges: .bottom)
    }
}

struct WebView: UIViewRepresentable {
    let url: URL?
    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView()
        w.allowsBackForwardNavigationGestures = true
        if let url { w.load(URLRequest(url: url)) }
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
