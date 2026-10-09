import SwiftUI
import UIKit

// Template entry point. Replace RootView with your app; keep the control server and probe.

@main
struct TemplateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup { RootView().onOpenURL { url in Log.shared.add("url \(url)") } }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        ControlServer.shared.handler = { m, p, q, b in await Routes.handle(m, p, q, b) }
        ControlServer.shared.start()
        Log.shared.add("launch: available=\(DeviceProbe.availableMemory() / 1_048_576) MB")
        return true
    }
}

/// Add your app's routes here. Everything returns JSON.
enum Routes {
    static func handle(_ method: String, _ path: String, _ q: [String: String], _ b: [String: Any]) async -> (Int, Any) {
        switch (method, path) {
        case ("GET", "/ping"): return (200, ["ok": true, "app": Bundle.main.bundleIdentifier ?? "?"])
        case ("GET", "/device"): return (200, await MainActor.run { DeviceProbe.snapshot() })
        case ("GET", "/log"): return (200, ["lines": Log.shared.all()])
        case ("GET", "/rust"): return (200, ["core": RustCore.version(), "sum": RustCore.add(2, 40)])
        default: return (404, ["error": "no route \(method) \(path)"])
        }
    }
}

/// Swift side of the optional Rust core (rust/). If you delete rust/, delete this and the bridging header.
enum RustCore {
    static func version() -> String {
        guard let p = core_version() else { return "?" }
        defer { core_free_string(p) }
        return String(cString: p)
    }
    static func add(_ a: Int64, _ b: Int64) -> Int64 { core_add(a, b) }
}

struct RootView: View {
    @State private var tick = 0
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationStack {
            List {
                Section("Control server") {
                    LabeledContent("Address", value: "http://127.0.0.1:\(ControlServer.shared.port)")
                    LabeledContent("Running", value: ControlServer.shared.running ? "yes" : "no")
                    LabeledContent("Token", value: ControlServer.shared.token).textSelection(.enabled)
                    Button("Copy token") { UIPasteboard.general.string = ControlServer.shared.token }
                }
                Section("Rust core") { Text("\(RustCore.version()) · 2+40=\(RustCore.add(2, 40))") }
                Section("Log") { ForEach(Array(Log.shared.all().suffix(30).reversed().enumerated()), id: \.offset) { Text($0.element).font(.caption2.monospaced()) } }
            }
            .navigationTitle("Template")
            .onReceive(timer) { _ in tick += 1 }.id(tick)
        }
    }
}
