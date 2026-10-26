import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var pskDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("The address is an IP or a hostname. Wake-on-LAN only travels a local network, or a subnet that forwards broadcasts.")
                    .font(.system(size: 12))
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                group("TVs") {
                    if model.settings.devices.isEmpty {
                        Text("No TV saved yet.")
                            .font(.system(size: 12))
                            .foregroundColor(Palette.muted)
                    }
                    ForEach(model.settings.devices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                Text(device.host)
                                    .font(.system(size: 11))
                                    .foregroundColor(Palette.muted)
                            }
                            Spacer()
                            if device.id == model.settings.activeDeviceID {
                                Text("Current")
                                    .font(.system(size: 11))
                                    .foregroundColor(Palette.muted)
                            }
                            Button("Use") { model.selectDevice(device.id) }
                            Button(device.preferred ? "Preferred" : "Make preferred") { model.preferDevice(device.id) }
                        }
                    }
                    Button("Add a TV…") { model.showWizard() }
                }

                group("TV") {
                    field("Address", text: hostBinding, prompt: "TV IP (e.g. 192.168.1.20)")
                        .onSubmit { model.commitAddress(); model.refreshNow() }
                    field("adb port", text: portBinding, prompt: "5555")
                    field("adb path", text: adbBinding, prompt: "Blank finds Homebrew's adb")
                    Button("Check connection") {
                        model.commitAddress()
                        model.refreshNow()
                    }
                }

                group("Sony IP control") {
                    Text("Optional, for a Sony TV. Turn on IP control and set a pre-shared key, then enter the same key here. It is stored in the Keychain, not in settings.json. The app does not print it. When Sony answers, the remote uses it for power, volume, input names, and buttons.")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    SecureField("Pre-shared key", text: $pskDraft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Pre-shared key")
                    field("Sony port", text: sonyPortBinding, prompt: "80")
                    HStack {
                        Button("Save key") {
                            model.savePreSharedKey(pskDraft)
                            pskDraft = ""
                        }
                        Button("Remove key") {
                            pskDraft = ""
                            model.clearPreSharedKey()
                        }
                    }
                    Text(model.pskSaved ? "A pre-shared key is saved in the Keychain." : "No pre-shared key. The remote uses adb only.")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.muted)
                }

                group("Wake on LAN") {
                    Toggle("Send a magic packet when the TV doesn't answer adb", isOn: wolBinding)
                    field("MAC address", text: macBinding, prompt: "AA:BB:CC:DD:EE:FF")
                    field("Broadcast", text: broadcastBinding, prompt: "255.255.255.255")
                    Text("Power sends KEYCODE_WAKEUP when the TV is connected. From standby it sends this packet instead. Hold isn't required. Sleep is the separate button on the remote.")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                group("Apps") {
                    Text("On each connect the remote reads the TV's apps. It uses the Evening Paper export when that file is there, and otherwise the leanback apps and their labels. Favourites stay first. The last list is kept on this Mac and shown with “TV offline, saved list” when the TV doesn't answer. You can still edit a package here; the next connect replaces this copy.")
                        .font(.system(size: 11))
                        .foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(model.settings.apps) { app in
                        appRow(app)
                    }
                    Button("Add an app") {
                        model.update { settings in
                            settings.apps.append(TvApp(id: UUID().uuidString, name: "App", packageName: "com.example.app"))
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 560)
        .preferredColorScheme(.dark)
        .tint(Palette.accent)
    }

    private var hostBinding: Binding<String> {
        Binding(get: { model.settings.host }, set: { value in model.editDraft { $0.host = value } })
    }

    private var portBinding: Binding<String> {
        Binding(
            get: { String(model.settings.port) },
            set: { value in
                model.editDraft { settings in
                    if let port = Int(value), (1...65535).contains(port) {
                        settings.port = port
                    }
                }
            }
        )
    }

    private var sonyPortBinding: Binding<String> {
        Binding(
            get: { String(model.settings.sonyPort) },
            set: { value in
                model.editDraft { settings in
                    if let port = Int(value), (1...65535).contains(port) {
                        settings.sonyPort = port
                    }
                }
            }
        )
    }

    private var adbBinding: Binding<String> {
        Binding(get: { model.settings.adbPath }, set: { value in model.update { $0.adbPath = value } })
    }

    private var wolBinding: Binding<Bool> {
        Binding(get: { model.settings.wolEnabled }, set: { value in model.update { $0.wolEnabled = value } })
    }

    private var macBinding: Binding<String> {
        Binding(get: { model.settings.macAddress }, set: { value in model.update { $0.macAddress = value } })
    }

    private var broadcastBinding: Binding<String> {
        Binding(get: { model.settings.broadcastAddress }, set: { value in model.update { $0.broadcastAddress = value } })
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(Palette.muted)
            TextField(title, text: text, prompt: Text(prompt))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func appRow(_ app: TvApp) -> some View {
        HStack(spacing: 8) {
            TextField("Name", text: binding(app.id, \.name))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
            TextField("Package", text: binding(app.id, \.packageName))
                .textFieldStyle(.roundedBorder)
            Button(action: { model.update { $0.apps.removeAll { $0.id == app.id } } }) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(app.name)")
        }
    }

    private func binding(_ id: String, _ keyPath: WritableKeyPath<TvApp, String>) -> Binding<String> {
        Binding(
            get: { model.settings.apps.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { value in
                model.update { settings in
                    guard let index = settings.apps.firstIndex(where: { $0.id == id }) else { return }
                    settings.apps[index][keyPath: keyPath] = value
                }
            }
        )
    }
}
