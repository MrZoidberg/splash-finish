// Updates. A copy that Homebrew manages updates with brew only, from a progress window; Sparkle
// is not created for it at all, so it neither checks nor shows its window. Every other release
// copy updates with Sparkle from the public feed (`SUFeedURL` in Info.plist), verified with the
// EdDSA public key in `SUPublicEDKey` and by Apple's code signature checks.
import AppKit
import Observation
import Sparkle
import SplashFinishCore

/// What the app needs from Sparkle; a protocol so tests can check that Sparkle is never created.
@MainActor
protocol SparkleUpdating: AnyObject {
    var automaticallyChecks: Bool { get set }
    var canCheck: Bool { get }
    func check()
}

@MainActor
private final class SparkleUpdater: SparkleUpdating {
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                          userDriverDelegate: nil)
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var canCheck: Bool { controller.updater.canCheckForUpdates }
    func check() { controller.checkForUpdates(nil) }
}

@MainActor
@Observable
final class UpdateService {
    static let shared: UpdateService = {
        let app = AppBundle.applicationURL(for: AppBundle.executableURL)
        let info = app.flatMap(Bundle.init(url:))?.infoDictionary ?? [:]
        let hasFeed = (info["SUFeedURL"] as? String)?.isEmpty == false
        let hasKey = (info["SUPublicEDKey"] as? String)?.isEmpty == false
        // Identify the actual app, including launches through a CLI symlink.
        let homebrew = app.flatMap {
            HomebrewDetection.install(of: $0,
                                        prefixes: HomebrewDetection.prefixes(environment: ProcessInfo.processInfo.environment))
        }
        return UpdateService(choice: UpdaterChoice.choose(homebrew: homebrew, hasFeed: hasFeed, hasKey: hasKey),
                             makeSparkle: { SparkleUpdater() })
    }()

    let choice: UpdaterChoice
    @ObservationIgnored private let sparkle: SparkleUpdating?

    init(choice: UpdaterChoice, makeSparkle: () -> SparkleUpdating) {
        self.choice = choice
        sparkle = choice == .sparkle ? makeSparkle() : nil
        automaticallyChecks = sparkle?.automaticallyChecks ?? false
    }

    /// True when Sparkle updates this copy; its controls are shown then.
    var isAvailable: Bool { sparkle != nil }

    /// The Homebrew record when Homebrew manages this copy.
    var homebrew: HomebrewInstall? {
        if case .homebrew(let install) = choice { return install }
        return nil
    }

    /// The one update action of the SplashFinish menu (menu-bar icon and launcher gear) and Settings.
    var menuTitle: String? {
        switch choice {
        case .homebrew: "Update Splash Finish via Homebrew…"
        case .sparkle: "Check for Updates…"
        case .none: nil
        }
    }

    /// Mirrors Sparkle's own preference, which Sparkle stores in the app's user defaults.
    var automaticallyChecks: Bool {
        didSet {
            guard let sparkle, sparkle.automaticallyChecks != automaticallyChecks else { return }
            sparkle.automaticallyChecks = automaticallyChecks
        }
    }

    var canCheck: Bool { sparkle?.canCheck ?? false }

    func checkForUpdates() {
        NSApp.activate()
        if let homebrew {
            HomebrewUpdateWindowController.shared.start(homebrew)
        } else {
            sparkle?.check()
        }
    }
}
