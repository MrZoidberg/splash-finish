import Darwin
import Foundation

/// Locate installed resources without SwiftPM's absolute build-directory fallback.
enum AppBundle {
    static let executableURL: URL = {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            preconditionFailure("Unable to locate the running executable")
        }
        return URL(fileURLWithPath: String(cString: buffer)).standardizedFileURL.resolvingSymlinksInPath()
    }()

    static func applicationURL(for executable: URL) -> URL? {
        let directory = executable.deletingLastPathComponent()
        let contents = directory.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard directory.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents",
              app.pathExtension == "app" else { return nil }
        return app
    }

    static var version: String {
        guard let app = applicationURL(for: executableURL),
              let value = Bundle(url: app)?.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return "0.0.0-dev"
        }
        return value
    }

    static func resources(for executable: URL = executableURL) -> Bundle? {
        let root: URL
        if let app = applicationURL(for: executable) {
            root = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        } else {
            // swift run places resources beside the executable.
            root = executable.deletingLastPathComponent()
        }
        return Bundle(url: root.appendingPathComponent("SplashFinish_SplashFinish.bundle", isDirectory: true))
    }
}
