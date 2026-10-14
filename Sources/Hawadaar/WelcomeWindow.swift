import AppKit
import SwiftUI

/// Hawadaar has no Dock icon, so opening it can look like nothing happened. This shows a
/// small window pointing to the menu bar on first launch and whenever the app is opened again
/// while running, and warns when macOS has hidden the icon behind the notch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ACStore()
    let updates = UpdateChecker()
    private var welcomeWindow: NSWindow?
    private var controlWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !UserDefaults.standard.bool(forKey: "welcomeShown") else { return }
        UserDefaults.standard.set(true, forKey: "welcomeShown")
        // Give the status item a moment to be placed before checking whether it's visible.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showWelcome() }
    }

    /// Opening the app again while it runs: show the controls in a window if the menu bar icon is
    /// hidden, otherwise point to the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if Self.isStatusItemHidden {
            showControlWindow()
        } else {
            showWelcome()
        }
        return false
    }

    func showWelcome() {
        let view = WelcomeView(iconHidden: Self.isStatusItemHidden,
                               openWindow: { [weak self] in
                                   self?.welcomeWindow?.close()
                                   self?.showControlWindow()
                               },
                               dismiss: { [weak self] in self?.welcomeWindow?.close() })
        let window = welcomeWindow ?? Self.makeWindow()
        welcomeWindow = window
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(window.contentView?.fittingSize ?? .zero)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The menu bar panel in an ordinary window, for when macOS hides the menu bar icon.
    func showControlWindow() {
        let window = controlWindow ?? NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable],
                                               backing: .buffered, defer: false)
        if controlWindow == nil {
            window.title = "Hawadaar"
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: RootView().environmentObject(store).environmentObject(updates))
            window.setContentSize(window.contentView?.fittingSize ?? .zero)
            window.center()
            controlWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        return window
    }

    /// True when the menu bar item exists but isn't on screen, which is what macOS does when a
    /// crowded menu bar runs into the notch.
    static var isStatusItemHidden: Bool {
        let items = NSApp.windows.filter { $0.className.contains("StatusBarWindow") }
        guard !items.isEmpty else { return false }
        return items.allSatisfy { item in
            !item.occlusionState.contains(.visible)
                || !NSScreen.screens.contains { $0.frame.intersects(item.frame) }
        }
    }
}

struct WelcomeView: View {
    let iconHidden: Bool
    let openWindow: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Hawadaar lives in your menu bar").font(.title3.bold())
            Label("Click the AC icon at the top right of your screen.", systemImage: "arrow.up.right")
                .foregroundStyle(.secondary)
            if iconHidden {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Your menu bar is full", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(.orange)
                    Text("macOS is hiding Hawadaar's icon behind the notch. Quit a menu bar app you don't need, or hold ⌘ and drag other icons out of the menu bar to make room.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            }
            Text(iconHidden ? "While the icon is hidden, opening Hawadaar from Applications shows the controls in a window."
                            : "Open Hawadaar again any time to show this window.")
                .font(.caption).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if iconHidden {
                    Button("Open in a Window", action: openWindow).controlSize(.large)
                }
                Button("Got It", action: dismiss).keyboardShortcut(.defaultAction).controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 380)
    }
}
