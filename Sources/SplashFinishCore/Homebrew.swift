// Homebrew-aware updates: which copy Homebrew manages, the one command SplashFinish runs and what its
// result means. Pure logic over paths and text; the process run and the window live in the app.
import Foundation

/// A Splash Finish.app that a Caskroom record of the cask `splash-finish` points to.
public struct HomebrewInstall: Equatable, Sendable {
    /// The Homebrew prefix that owns the record, such as `/opt/homebrew`.
    public let prefix: URL
    /// `<prefix>/Caskroom/splash-finish/<version>/Splash Finish.app`, a symlink or a copy.
    public let record: URL
    /// The installed app the record resolves to: the place to start SplashFinish again after an update.
    public let app: URL

    /// The `brew` of the owning prefix, never one found elsewhere.
    public var brew: URL { prefix.appendingPathComponent("bin/brew") }
}

public enum HomebrewDetection {
    public static let cask = "splash-finish"
    public static let defaultPrefixes = ["/opt/homebrew", "/usr/local"]

    /// Prefixes to look at, in order: `HOMEBREW_PREFIX`, the prefix of each `brew` found in `PATH`,
    /// then the default Apple silicon and Intel prefixes. No duplicates.
    public static func prefixes(environment: [String: String],
                                fileManager: FileManager = .default) -> [URL] {
        var paths: [String] = []
        if let custom = environment["HOMEBREW_PREFIX"], custom.hasPrefix("/") { paths.append(custom) }
        for folder in (environment["PATH"] ?? "").split(separator: ":") where folder.hasPrefix("/") {
            let brew = URL(fileURLWithPath: String(folder)).appendingPathComponent("brew")
            if fileManager.isExecutableFile(atPath: brew.path) {
                // `<prefix>/bin/brew`: the prefix is the parent of `bin`.
                paths.append(brew.deletingLastPathComponent().deletingLastPathComponent().path)
            }
        }
        paths += defaultPrefixes
        var seen = Set<String>()
        return paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { seen.insert($0.path).inserted }
    }

    /// The Homebrew record of this bundle, or nil when Homebrew does not clearly manage it.
    /// Nil keeps the Sparkle updates of a directly downloaded copy: no record, a record of another
    /// path, an unreadable Caskroom, a prefix without a runnable `brew`, or two prefixes that both
    /// claim the copy.
    public static func install(of bundle: URL, prefixes: [URL],
                               fileManager: FileManager = .default) -> HomebrewInstall? {
        let target = resolved(bundle)
        var found: [HomebrewInstall] = []
        for prefix in prefixes {
            let caskroom = prefix.appendingPathComponent("Caskroom/\(cask)")
            guard let versions = try? fileManager.contentsOfDirectory(atPath: caskroom.path) else { continue }
            let match = versions.filter { !$0.hasPrefix(".") }.sorted().compactMap { version -> URL? in
                let record = caskroom.appendingPathComponent(version).appendingPathComponent("Splash Finish.app")
                var isFolder: ObjCBool = false
                guard fileManager.fileExists(atPath: record.path, isDirectory: &isFolder), isFolder.boolValue,
                      resolved(record) == target else { return nil }
                return record
            }.last
            guard let match else { continue }
            guard fileManager.isExecutableFile(atPath: prefix.appendingPathComponent("bin/brew").path) else { return nil }
            found.append(HomebrewInstall(prefix: prefix, record: match, app: bundle.standardizedFileURL))
        }
        return found.count == 1 ? found[0] : nil
    }

    private static func resolved(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// The result of one Homebrew update.
public enum HomebrewUpdateOutcome: Equatable, Sendable {
    case upgraded
    case upToDate
    case failed(exitCode: Int32, output: String)
    case cancelled(output: String)
}

public enum HomebrewUpdate {
    public static let tap = "bobuk-io/tap/splash-finish"
    /// Only Splash Finish: the cask is always named, so Homebrew never upgrades anything else.
    /// `--greedy` because the cask says `auto_updates true`, which plain upgrades skip.
    public static let arguments = ["upgrade", "--cask", "--greedy", tap]
    /// The argument with which the helper starts the installed copy again to show the result.
    public static let resultArgument = "--homebrew-update-log"
    /// The argument with which the helper starts the progress viewer, the copy of Splash Finish.app in the
    /// run folder, while the installed Splash Finish is gone.
    public static let viewerArgument = "--homebrew-update-viewer"

    /// The command as the window shows it.
    public static func commandLine(for install: HomebrewInstall) -> String {
        ([install.brew.path] + arguments).joined(separator: " ")
    }

    /// Success only on exit code 0 without a cancel. Exit 0 without an upgrade report means that
    /// nothing was upgraded ("Not upgrading splash-finish, the latest version is already installed").
    /// Every other exit code is a failure with the real output: a network error, a Homebrew lock,
    /// a refused password prompt.
    public static func outcome(exitCode: Int32, output: String, cancelled: Bool) -> HomebrewUpdateOutcome {
        if cancelled { return .cancelled(output: output) }
        guard exitCode == 0 else { return .failed(exitCode: exitCode, output: output) }
        let upgraded = output.contains("was successfully upgraded") || output.contains("Upgrading 1 outdated")
        return upgraded ? .upgraded : .upToDate
    }

    /// The run folder named by `--homebrew-update-log <folder>` (or another `argument`), accepted
    /// only directly inside `base`.
    public static func resultDirectory(in arguments: [String], base: URL,
                                       argument: String = resultArgument) -> URL? {
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        let folder = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        guard folder.deletingLastPathComponent().path == base.standardizedFileURL.path else { return nil }
        return folder
    }
}

/// Who updates this copy of Splash Finish.
public enum UpdaterChoice: Equatable, Sendable {
    case homebrew(HomebrewInstall)
    case sparkle
    /// A development build without a feed: no updates.
    case none

    public static func choose(homebrew: HomebrewInstall?, hasFeed: Bool, hasKey: Bool) -> UpdaterChoice {
        if let homebrew { return .homebrew(homebrew) }
        return hasFeed && hasKey ? .sparkle : .none
    }
}
