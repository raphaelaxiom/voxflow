import AppKit
import SwiftUI

@main
struct VoxflowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("show_menu_bar_icon") private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(appDelegate.appState)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.appState)
        }
    }
}

@MainActor
struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var notificationManager = VocabularyNotificationManager.shared

    private var iconName: String {
        if appState.isRecording { return "record.circle" }
        if appState.isTranscribing { return "ellipsis.circle" }
        if appState.pasteFailureText != nil { return "exclamationmark.circle.fill" }
        return "waveform"
    }

    var body: some View {
        HStack(spacing: 4) {
            if notificationManager.showCheckmark {
                Image(systemName: "checkmark")
            }
            if AppBuild.isDevBundle && !appState.isRecording && !appState.isTranscribing && appState.pasteFailureText == nil {
                Image(nsImage: StampedMenuBarIcon.templateImage)
                    .renderingMode(.template)
            } else if let trayIcon = VoxflowTrayIcon.templateImage,
                      !appState.isRecording && !appState.isTranscribing && appState.pasteFailureText == nil {
                Image(nsImage: trayIcon)
                    .renderingMode(.template)
            } else if appState.pasteFailureText != nil {
                // Orange alert: the last dictation was saved but not
                // pasted — the menu holds the real Copy button.
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: iconName)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: notificationManager.showCheckmark)
    }
}

/// The Voxflow tray mark: a transparent PNG shipped in the bundle,
/// used as a template image so it adapts to light and dark menu bars.
/// Falls back to the SF Symbol waveform when the resource is missing.
enum VoxflowTrayIcon {
    static let templateImage: NSImage? = {
        guard let image = NSImage(named: "VoxflowTray") else { return nil }
        image.isTemplate = true
        return image
    }()
}

enum StampedMenuBarIcon {
    static let templateImage: NSImage = {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            path.append(NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3))
            let bars: [(x: CGFloat, y: CGFloat, h: CGFloat)] = [
                (3.0,  7.0,  2.0),
                (5.5,  5.0,  6.0),
                (8.0,  3.0, 10.0),
                (10.5, 4.0,  8.0),
                (13.0, 6.0,  4.0),
            ]
            for bar in bars {
                path.append(NSBezierPath(
                    roundedRect: NSRect(x: bar.x, y: bar.y, width: 1.5, height: bar.h),
                    xRadius: 0.75, yRadius: 0.75
                ))
            }
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
