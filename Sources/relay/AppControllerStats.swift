import AppKit
import Panels
import SwiftUI

extension AppController {
    @objc func showRuntimeStats(_: Any?) {
        if let statsWindow {
            statsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let model = RuntimeStatsModel()
        let hosting = NSHostingController(
            rootView: RuntimeStatsView(settings: settings, model: model)
        )
        hosting.preferredContentSize = NSSize(width: 420, height: 340)
        let panel = NSWindow(contentViewController: hosting)
        panel.title = "Runtime Stats"
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.center()

        let sampler = RuntimeStatsSampler(
            store: store,
            model: model,
            liveSurfaceCount: { [weak splitVC] in splitVC?.liveSurfaceCount ?? 0 }
        )
        sampler.start()
        runtimeStatsSampler = sampler
        statsWindow = panel
        applyWindowChrome(settings.theme)
        panel.makeKeyAndOrderFront(nil)
    }
}

extension AppController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === statsWindow else { return }
        runtimeStatsSampler?.stop()
        runtimeStatsSampler = nil
        statsWindow = nil
    }
}
