import AppKit
import Combine
import SwiftUI

/// The menu bar icon and its panel. A plain borderless panel, rather than SwiftUI's
/// `MenuBarExtra`, so every macOS version draws exactly the same thing: newer releases wrap
/// `MenuBarExtra` windows in their own glass frame.
@MainActor
final class StatusItemController: NSObject {
    private let store: ACStore
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: NSPanel
    private var monitors: [Any] = []
    private var subscriptions = Set<AnyCancellable>()

    init(store: ACStore, updates: UpdateChecker) {
        self.store = store
        let content = NSHostingController(rootView: RootView().environmentObject(store).environmentObject(updates))
        content.sizingOptions = [.preferredContentSize]
        content.view.wantsLayer = true
        content.view.layer?.cornerRadius = 12
        content.view.layer?.masksToBounds = true

        panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        panel.contentViewController = content
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        statusItem.button?.imagePosition = .imageLeading
        updateButton()
        store.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateButton() }
            .store(in: &subscriptions)
        // The panel grows when a picker opens; keep it pinned under the icon.
        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: panel)
            .sink { [weak self] _ in self?.position() }
            .store(in: &subscriptions)
    }

    /// Icon plus the setpoint while the selected AC is running.
    private func updateButton() {
        guard let button = statusItem.button else { return }
        let status = store.status
        let image = NSImage(systemSymbolName: status.isOn ? "air.conditioner.horizontal.fill" : "air.conditioner.horizontal",
                            accessibilityDescription: "Hawadaar")
        image?.isTemplate = true
        button.image = image
        button.title = store.phase == .ready && status.isOn ? " \(status.setpoint)°" : ""
    }

    @objc private func toggle() {
        panel.isVisible ? close() : open()
    }

    private func open() {
        position()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        statusItem.button?.highlight(true)
        // Close on a click anywhere else, or Escape.
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.close() }
        }) { monitors.append(outside) }
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53, self?.panel.isKeyWindow == true else { return event }
            self?.close()
            return nil
        }) { monitors.append(escape) }
    }

    private func close() {
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Centres the panel under the icon, kept on screen, 4pt below the menu bar.
    private func position() {
        guard let itemFrame = statusItem.button?.window?.frame,
              let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = min(max(itemFrame.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: itemFrame.minY - 4))
        panel.invalidateShadow()
    }
}

/// Borderless panels can't take keyboard focus by default, which the sign-in fields need.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
