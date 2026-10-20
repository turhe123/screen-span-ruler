import SwiftUI
import Carbon
import ServiceManagement

/// Settings window: hotkey, default unit, tolerance, launch at login and support.
struct SettingsView: View {
    @AppStorage(Prefs.unitPixels) private var unitPixels = false
    @AppStorage(Prefs.tolerance) private var tolerance = 8.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            HotKeyRecorder()
            Picker("Default unit", selection: $unitPixels) {
                Text("Points").tag(false)
                Text("Pixels").tag(true)
            }
            VStack(alignment: .leading) {
                Slider(value: $tolerance, in: 0...30, step: 1) {
                    Text("Edge tolerance (\(Int(tolerance)))")
                }
                Text("Low values stop at the slightest colour change. Above 15, pixels are compared to their neighbour so gradients are ignored.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Support / Donate ❤️") { Prefs.openDonate() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// Click-to-record control that captures a key combination and re-registers the global hotkey.
struct HotKeyRecorder: View {
    @AppStorage(Prefs.hotKeyCode) private var keyCode = kVK_ANSI_2
    @AppStorage(Prefs.hotKeyMods) private var modifiers = cmdKey | shiftKey
    @AppStorage(Prefs.hotKeyLabel) private var label = "⇧⌘2"
    @State private var monitor: Any?

    var body: some View {
        LabeledContent("Measure hotkey") {
            Button(monitor == nil ? label : "Press keys… (Esc cancels)") {
                monitor == nil ? startRecording() : stopRecording()
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stopRecording(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var mods = 0
            var text = ""
            if flags.contains(.control) { mods |= controlKey; text += "⌃" }
            if flags.contains(.option) { mods |= optionKey; text += "⌥" }
            if flags.contains(.shift) { mods |= shiftKey; text += "⇧" }
            if flags.contains(.command) { mods |= cmdKey; text += "⌘" }
            guard mods != 0 else { NSSound.beep(); return nil }
            keyCode = Int(event.keyCode)
            modifiers = mods
            label = text + (event.charactersIgnoringModifiers?.uppercased() ?? "?")
            HotKeyManager.shared.register(keyCode: UInt32(keyCode), modifiers: UInt32(mods))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Registers a single global hotkey through Carbon and forwards presses to a closure.
final class HotKeyManager {
    static let shared = HotKeyManager()
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func registerFromDefaults() {
        let defaults = UserDefaults.standard
        register(keyCode: UInt32(defaults.integer(forKey: Prefs.hotKeyCode)),
                 modifiers: UInt32(defaults.integer(forKey: Prefs.hotKeyMods)))
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyManager.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, &handlerRef)
        }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        let id = EventHotKeyID(signature: OSType(0x5353_5052), id: 1) // "SSPR"
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}
