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
        let panel = makePanelWindow(
            title: "Runtime Stats",
            size: NSSize(width: 420, height: 400),
            theme: settings.theme,
            content: RuntimeStatsView(settings: settings, model: model)
        )
        panel.delegate = self

        let sampler = RuntimeStatsSampler(
            store: store,
            model: model,
            liveSurfaceCount: { [weak splitVC] in splitVC?.liveSurfaceCount ?? 0 }
        )
        sampler.start()
        runtimeStatsSampler = sampler
        statsWindow = panel
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
