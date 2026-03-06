import SwiftUI

@main
struct WorkTrackerApp: App {
    @StateObject private var vm = TrackerViewModel()

    var body: some Scene {
        // Main window — shares the same ViewModel
        WindowGroup {
            Group {
                if vm.isMiniMode {
                    MiniWidgetView(vm: vm)
                        .onAppear { setWindowFloating(true) }
                } else {
                    ContentView(vm: vm)
                        .onAppear { setWindowFloating(false) }
                }
            }
            // Add an invisible frame change hook to snap macOS windows back
            .onChange(of: vm.isMiniMode) { mini in
                if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) {
                    if mini {
                        window.setContentSize(NSSize(width: 250, height: 110))
                        window.styleMask.remove(.resizable)
                    } else {
                        window.styleMask.insert(.resizable)
                        window.setContentSize(NSSize(width: 540, height: 640))
                    }
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 540, height: 640)

        // Menu bar extra — shares the same ViewModel
        MenuBarExtra {
            MenuBarView(vm: vm)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        // Settings
        Settings {
            SettingsView()
        }
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if let active = vm.activeEntry {
            HStack(spacing: 4) {
                Image(systemName: active.type.icon)
                Text(vm.elapsedFormatted)
                    .font(.system(.caption2, design: .monospaced))
            }
        } else {
            Image(systemName: "timer")
        }
    }

    private func setWindowFloating(_ floating: Bool) {
        // Give SwiftUI a tiny moment to render the view before grabbing the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) {
                window.level = floating ? .floating : .normal
            }
        }
    }
}
