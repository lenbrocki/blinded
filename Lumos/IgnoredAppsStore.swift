import Foundation

/// One application for which auto-brightness is paused, plus the backlight level it should
/// hold — remembered per display so each panel keeps its own preferred level for the app.
struct IgnoredApp: Codable, Equatable {
    var bundleID: String
    var name: String
    /// Preferred backlight level (0...1) per display, keyed by `DisplayInfo.persistKey`.
    var preferred: [String: Double] = [:]
}

/// Persistent set of apps that pause content-adaptive brightness while frontmost, each holding
/// a remembered per-display level. Inspired by lumen's ignore list, adapted to Lumos's
/// multi-display model (lumen remembered a single level for the main display).
///
/// Small structured config, so it lives in `UserDefaults` rather than the per-display curve files.
final class IgnoredAppsStore {
    private static let defaultsKey = "ignoredApps.v1"
    private var apps: [String: IgnoredApp]   // keyed by bundleID

    init() { apps = Self.load() }

    /// Ignored apps, sorted by name for stable display.
    var all: [IgnoredApp] {
        apps.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func isIgnored(_ bundleID: String) -> Bool { apps[bundleID] != nil }

    func add(bundleID: String, name: String) {
        guard apps[bundleID] == nil else { return }
        apps[bundleID] = IgnoredApp(bundleID: bundleID, name: name)
        save()
    }

    func remove(bundleID: String) {
        guard apps[bundleID] != nil else { return }
        apps[bundleID] = nil
        save()
    }

    func preferredBrightness(bundleID: String, persistKey: String) -> Double? {
        apps[bundleID]?.preferred[persistKey]
    }

    func setPreferredBrightness(_ value: Double, bundleID: String, persistKey: String) {
        guard var app = apps[bundleID] else { return }
        app.preferred[persistKey] = value
        apps[bundleID] = app
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func load() -> [String: IgnoredApp] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: IgnoredApp].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
