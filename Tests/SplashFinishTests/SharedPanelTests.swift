import AppKit
import SwiftUI
import XCTest
import SplashFinishCore
import BobukUI
@testable import SplashFinish

final class SharedPanelTests: XCTestCase {
    func testSharedFrameRendersInboxEmptyAndMessageStatesWithoutOpeningWindows() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let model = AppModel(stateURL: root.appendingPathComponent("state.json"))
            model.respectFocus = false
            let previous = NSApp.appearance
            defer { NSApp.appearance = previous }
            for dark in [false, true] {
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                for state in ["empty", "inbox", "message"] {
                    model.clear()
                    if state != "empty" {
                        model.receive(AgentEvent(task: "demo", agent: "Demo", status: .done,
                            title: "Demo build completed", detail: "No personal data or live sessions", project: "Example"))
                    }
                    model.message = state == "message" ? "Demo status message" : nil
                    let host = NSHostingView(rootView: PanelView(model: model, onOpen: { _ in XCTFail("Unexpected open") }, onSize: { _ in }))
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 600),
                        styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    for _ in 0..<4 {
                        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                        window.setContentSize(host.fittingSize)
                        host.layoutSubtreeIfNeeded()
                    }
                    XCTAssertEqual(host.frame.width, 470, accuracy: 0.5)
                    XCTAssertGreaterThan(host.frame.height, 200)
                    XCTAssertLessThan(host.frame.height, 700)
                    @MainActor func surfaces(_ view: NSView) -> [PickerSurfaceView] {
                        if let surface = view as? PickerSurfaceView { return [surface] }
                        return view.subviews.flatMap { surfaces($0) }
                    }
                    XCTAssertEqual(surfaces(host).count, 1)
                    XCTAssertFalse(window.isVisible)
                    if let directory = ProcessInfo.processInfo.environment["BOBUKKIT_PREVIEW_DIR"] {
                        let output = URL(fileURLWithPath: directory)
                        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                        try png.write(to: output.appendingPathComponent("splash-\(dark ? "dark" : "light")-\(state).png"))
                    }
                    window.close()
                }
            }
        }
    }
}
