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

            if !state.hasScreenPermission || state.captureBlocked {
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

            if let error = state.lastErrorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            Divider()
            Button("Quit Blinded") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { state.popoverAppeared() }
        .onDisappear { state.popoverDisappeared() }
    }

    private var permissionRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(state.captureBlocked
                  ? "No screen frames — Screen Recording blocked"
                  : "Screen Recording permission needed",
                  systemImage: "lock")
                .foregroundStyle(.orange)
            if state.captureBlocked {
                Text("macOS may have revoked it. Enable Blinded under Screen Recording, then toggle Auto-brightness off and on.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Button("Open Screen Recording settings…") { state.openScreenRecordingSettings() }
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
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
