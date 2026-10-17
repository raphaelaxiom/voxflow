import SwiftUI

/// Single-window app: ONE Dashboard window. Settings renders inline as a
/// Dashboard section; Setup renders inline as the first-run section of the
/// same window. There is no separate Settings window and no separate Setup
/// window — the old three-window layout (and its Settings→Dashboard
/// redirect) is gone.
class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var dashboardWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NetworkMonitor.shared.start()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSetup),
            name: .showSetup,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSettings),
            name: .showSettings,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowDashboard),
            name: .showDashboard,
            object: nil
        )

        // The permanent idle pill goes up at launch and stays until quit.
        appState.overlayManager.showIdle()

        if !appState.hasCompletedSetup {
            // First run: Setup is a section inside the Dashboard window.
            appState.showingSetupInline = true
            showDashboardWindow()
        } else {
            appState.startHotkeyMonitoring()
            appState.startAccessibilityPolling()
            Task { @MainActor in
                UpdateManager.shared.startPeriodicChecks()
            }

            if !AXIsProcessTrusted() {
                appState.showAccessibilityAlert()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard appState.hasCompletedSetup else { return true }
        if !flag {
            showDashboardWindow()
        }
        return true
    }

    /// Re-run Setup: show the wizard inline in the Dashboard window.
    @objc func handleShowSetup() {
        appState.showingSetupInline = true
        showDashboardWindow()
    }

    /// Open Settings: route to the Dashboard's inline Settings section.
    /// AppState sets `selectedSettingsTab` before posting (e.g. .general
    /// from the update pill, .runLog from the debug toggle); the embedded
    /// SettingsView honors it.
    @objc private func handleShowSettings() {
        appState.dashboardSection = .settings
        appState.showingSetupInline = false
        showDashboardWindow()
    }

    @objc private func handleShowDashboard() {
        showDashboardWindow()
    }

    private func showDashboardWindow() {
        NSApp.setActivationPolicy(.regular)

        if let dashboardWindow, dashboardWindow.isVisible {
            dashboardWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if dashboardWindow == nil {
            presentDashboardWindow()
        } else {
            dashboardWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func presentDashboardWindow() {
        let dashboardView = DashboardView()
            .environmentObject(appState)
        let hostingView = NSHostingView(rootView: dashboardView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 740),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppName.displayName) Dashboard"
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        dashboardWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(.accessory)
            self?.dashboardWindow = nil
        }
    }
}
