import AppKit
import SwiftUI

@main
struct BlindedApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("Blinded", systemImage: state.isEnabled ? "sun.max.fill" : "sun.max") {
            ContentView(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Auto-brightness", isOn: Binding(
                get: { state.isEnabled },
                set: { state.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            .font(.headline)

            if !state.hasScreenPermission {
                permissionRow
            }
            if !state.builtInBrightnessAvailable {
                Label("Brightness control unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if state.isEnabled {
                if state.displays.isEmpty {
                    Text("Detecting displays…").foregroundStyle(.secondary)
                } else {
                    ForEach(state.displays) { display in
                        DisplayRow(state: state, display: display)
                    }
                }
            }

            Divider()
            settleTimePicker

            if let error = state.lastErrorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Divider()
            Button("Quit Blinded") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 320)
    }

    private var permissionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Screen Recording permission needed", systemImage: "lock")
                .foregroundStyle(.orange)
            Button("Open Screen Recording settings…") { state.openScreenRecordingSettings() }
        }
    }

    private var settleTimePicker: some View {
        HStack {
            Text("Settle time").foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: Binding(
                get: { Int((state.settleTime * 1000).rounded()) },
                set: { state.settleTime = Double($0) / 1000 }
            )) {
                ForEach(AppState.settleTimeOptionsMs, id: \.self) { ms in
                    Text(ms == 0 ? "off" : "\(ms) ms").tag(ms)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
        }
    }
}

struct DisplayRow: View {
    @ObservedObject var state: AppState
    let display: AppState.DisplayVM

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                Text(display.name).fontWeight(.medium).lineLimit(1)
                Spacer()
                Button {
                    state.resetLearning(display.id)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset learned curve for this display")
            }

            HStack(spacing: 6) {
                Image(systemName: "sun.min")
                Slider(
                    value: Binding(
                        get: { display.brightness },
                        set: { state.previewBrightness(display.id, $0) }
                    ),
                    in: 0 ... 1,
                    onEditingChanged: { editing in
                        if !editing { state.commitBrightness(display.id, display.brightness) }
                    }
                )
                Image(systemName: "sun.max")
            }

            HStack {
                Text("luminance \(Int((display.luminance * 100).rounded()))%")
                Spacer()
                Text("brightness \(Int((display.brightness * 100).rounded()))%")
                Spacer()
                Text("learned \(display.corrections)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
