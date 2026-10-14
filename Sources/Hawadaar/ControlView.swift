import HawadaarCore
import ServiceManagement
import SwiftUI

struct ControlView: View {
    @EnvironmentObject var store: ACStore
    @EnvironmentObject var updates: UpdateChecker
    @State private var draftTemperature: Int?
    @State private var openTile: Tile?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private enum Tile { case mode, fan, airflow }

    private var status: ACStatus { store.status }
    private var shownTemperature: Int { draftTemperature ?? status.setpoint }

    var body: some View {
        VStack(spacing: 14) {
            header
            ACIllustration(isOn: status.isOn, temperature: shownTemperature, louver: status.verticalSwing)
            if !store.canControl { offlineBanner }
            Group {
                temperatureRow
                slider.disabled(!status.mode.usesSetpoint)
                    .opacity(status.mode.usesSetpoint ? 1 : 0.4)
                tiles
            }
            .disabled(!store.canControl)
            footer
        }
        .padding(16)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "thermometer.medium").foregroundStyle(Palette.secondary)
            Text("Room").foregroundStyle(Palette.secondary)
            Text(status.roomTemperature.map { String(format: "%.1f°C", $0) } ?? "—").bold()
            Circle().fill(store.isOnline ? Color.green : Color.red).frame(width: 7, height: 7)
                .help(store.isOnline ? "AC is online" : "AC is offline")
            Spacer()
            if store.devices.count > 1 {
                Menu(store.selected?.name ?? "AC") {
                    ForEach(store.devices) { device in
                        Button {
                            store.selectedId = device.id
                            openTile = nil
                        } label: {
                            let offline = store.online[device.id] == true ? "" : " (offline)"
                            if device.id == store.selected?.id {
                                Label(device.name + offline, systemImage: "checkmark")
                            } else {
                                Text(device.name + offline)
                            }
                        }
                    }
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            Button { store.send(.power(!status.isOn)) } label: {
                Image(systemName: "power").font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(status.isOn ? Palette.accent : Palette.tile))
            }
            .buttonStyle(.plain)
            .disabled(!store.canControl)
            .help(status.isOn ? "Turn off" : "Turn on")
        }
        .font(.callout)
    }

    private var offlineBanner: some View {
        Label(store.cloudConnected ? "\(store.selected?.name ?? "AC") is offline" : "Reconnecting to MirAIe…",
              systemImage: store.cloudConnected ? "wifi.slash" : "arrow.triangle.2.circlepath")
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.2)))
    }

    private var temperatureRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(shownTemperature)").font(.system(size: 52, weight: .light, design: .rounded))
                .contentTransition(.numericText())
                .animation(.snappy, value: shownTemperature)
            Text("°C").font(.title3).foregroundStyle(Palette.accent)
            Spacer()
            Toggle(isOn: Binding(get: { status.eco }, set: { store.send(.eco($0)) })) {
                Label("Eco Mode", systemImage: "leaf").font(.caption)
            }
            .toggleStyle(.switch).controlSize(.mini)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(Palette.tile))
        }
    }

    private var slider: some View {
        let range = ACStatus.temperatureRange
        return VStack(spacing: 4) {
            HStack(spacing: 10) {
                stepButton("minus", delta: -1)
                GradientSlider(value: Binding(get: { Double(shownTemperature) },
                                              set: { draftTemperature = Int($0.rounded()) }),
                               range: Double(range.lowerBound)...Double(range.upperBound)) {
                    if let draft = draftTemperature, draft != status.setpoint { store.send(.temperature(draft)) }
                    draftTemperature = nil
                }
                stepButton("plus", delta: 1)
            }
            HStack {
                Text("\(range.lowerBound)°"); Spacer(); Text("\(range.upperBound)°")
            }
            .font(.caption2).foregroundStyle(Palette.secondary).padding(.horizontal, 38)
        }
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        let target = status.setpoint + delta
        return Button { store.send(.temperature(target)) } label: {
            Image(systemName: symbol).frame(width: 26, height: 26).background(Circle().fill(Palette.tile))
        }
        .buttonStyle(.plain)
        .disabled(!ACStatus.temperatureRange.contains(target))
    }

    private var tiles: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                tileButton(.mode, title: "Mode", value: status.mode.title, icon: status.mode.symbol)
                tileButton(.fan, title: "Fan speed", value: status.fan.title, icon: "fanblades")
                tileButton(.airflow, title: "Airflow",
                           value: status.verticalSwing == 0 ? "Swing" : "L\(status.verticalSwing)",
                           icon: "arrow.up.and.down.and.sparkles")
                Button { store.send(.powerful(!status.powerful)) } label: {
                    TileLabel(title: "Powerful", value: status.powerful ? "On" : "Off", icon: "bolt",
                              highlighted: status.powerful)
                }
                .buttonStyle(.plain)
            }
            switch openTile {
            case .mode:
                OptionChips(options: ACMode.allCases.map { ($0.title, $0) }, current: status.mode) {
                    store.send(.mode($0))
                    openTile = nil
                }
            case .fan:
                OptionChips(options: FanSpeed.allCases.map { ($0.title, $0) }, current: status.fan) {
                    store.send(.fan($0))
                    openTile = nil
                }
            case .airflow:
                LouverPicker(current: status.verticalSwing) {
                    store.send(.verticalSwing($0))
                    openTile = nil
                }
            case nil:
                EmptyView()
            }
        }
        .animation(.easeOut(duration: 0.15), value: openTile)
    }

    private func tileButton(_ tile: Tile, title: String, value: String, icon: String) -> some View {
        Button { openTile = openTile == tile ? nil : tile } label: {
            TileLabel(title: title, value: value, icon: icon, highlighted: openTile == tile)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(store.cloudConnected ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(store.cloudConnected ? "Live" : "Reconnecting…")
            if let signal = status.wifiSignal {
                Text("· AC Wi-Fi \(signal) dBm")
                    .foregroundStyle(signal < -75 ? Color.orange : Palette.secondary)
                    .help(signal < -75 ? "Weak signal: the AC may drop off Wi-Fi" : "Signal the AC reports for its own Wi-Fi")
            }
            Spacer()
            if updates.installState == .installing {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Updating…")
                }
                .foregroundStyle(Palette.accent)
            } else if let release = updates.available {
                Button { updates.install() } label: {
                    Label("Update \(release.version.description)", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .help("Install Hawadaar \(release.version.description) and restart")
            }
            Menu {
                Toggle("Display Light", isOn: Binding(get: { status.display }, set: { store.send(.display($0)) }))
                    .disabled(!store.canControl)
                Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                Divider()
                Button("Refresh") { Task { await store.start() } }
                Button("Copy Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.diagnostics(), forType: .string)
                }
                Button("Open Connection Log") { NSWorkspace.shared.open(ConnectionLog.url) }
                    .disabled(!FileManager.default.fileExists(atPath: ConnectionLog.url.path))
                Divider()
                Button("About Hawadaar \(About.version)") { About.show() }
                if let release = updates.available {
                    Button("Install Hawadaar \(release.version.description) and Restart") { updates.install() }
                        .disabled(updates.installState == .installing)
                } else {
                    Button("Check for Updates…") { Task { await updates.check(userInitiated: true) } }
                }
                Button("Sign Out") { store.signOut() }
                Button("Quit Hawadaar") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .font(.caption2).foregroundStyle(Palette.secondary)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
