import SwiftUI
import Carbon
import UserNotifications

/// Shared keys and defaults for everything persisted in UserDefaults / @AppStorage.
enum Prefs {
    static let tolerance = "tolerance"
    static let unitPixels = "unitPixels"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyMods = "hotKeyMods"
    static let hotKeyLabel = "hotKeyLabel"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            tolerance: 8.0,
            unitPixels: false,
            hotKeyCode: kVK_ANSI_2,
            hotKeyMods: cmdKey | shiftKey,
            hotKeyLabel: "⇧⌘2",
        ])
    }

    static func openDonate() { NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!) }

    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Entry point: a menu-bar-only app with a MenuBarExtra panel and a Settings window.
@main
struct ScreenSpanRulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("ScreenSpanRuler", systemImage: "ruler") {
            MenuContent()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// Wires up defaults and the global hotkey once the app has launched.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        HotKeyManager.shared.onPress = { OverlayController.shared.start() }
        HotKeyManager.shared.registerFromDefaults()
    }
}

/// The MenuBarExtra panel: start/grant access, unit toggle, tolerance, settings and support.
struct MenuContent: View {
    @AppStorage(Prefs.unitPixels) private var unitPixels = false
    @AppStorage(Prefs.tolerance) private var tolerance = 8.0
    @AppStorage(Prefs.hotKeyLabel) private var hotKeyLabel = "⇧⌘2"
    @State private var hasAccess = CGPreflightScreenCaptureAccess()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasAccess {
                Button {
                    NSApp.keyWindow?.close()
                    OverlayController.shared.start()
                } label: {
                    HStack {
                        Label("Start Measuring", systemImage: "ruler")
                        Spacer()
                        Text(hotKeyLabel).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    CGRequestScreenCaptureAccess()
                    Prefs.openScreenRecordingSettings()
                } label: {
                    Label("Grant Access…", systemImage: "lock.shield").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Text("Screen Recording permission is needed to capture the screen. Enable ScreenSpanRuler in System Settings → Privacy & Security, then relaunch the app.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Units", selection: $unitPixels) {
                Text("Points").tag(false)
                Text("Pixels").tag(true)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 4) {
                Text("Edge tolerance: \(Int(tolerance))").font(.callout)
                Slider(value: $tolerance, in: 0...30, step: 1)
            }

            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Support / Donate ❤️") { Prefs.openDonate() }
            }
            Button("Quit ScreenSpanRuler") { NSApp.terminate(nil) }
                .buttonStyle(.link)
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { hasAccess = CGPreflightScreenCaptureAccess() }
    }
}

/// Posts a user notification (falling back to an alert) when something goes wrong.
enum Notifier {
    static func post(_ title: String, _ body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                guard granted else {
                    let alert = NSAlert()
                    alert.messageText = title
                    alert.informativeText = body
                    alert.runModal()
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            }
        }
    }
}
